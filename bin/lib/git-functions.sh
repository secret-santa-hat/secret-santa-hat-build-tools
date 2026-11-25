#!/bin/bash

# Git and GitHub helpers for secret-santa-hat-build-tools.

# True when the current directory is inside a git repository.
function is_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Print the current branch name.
function get_current_branch() {
    git branch --show-current
}

# Determine the default branch to merge releases into. Honors an override from
# release.conf (SSH_RELEASE_MAIN_BRANCH), otherwise prefers main, then master.
function get_default_branch() {
    if [ -n "${SSH_RELEASE_MAIN_BRANCH:-}" ]; then
        echo "$SSH_RELEASE_MAIN_BRANCH"

        return 0
    fi

    if git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    elif git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    else
        echo "main"
    fi
}

# Seconds to wait before each repeat of a GitHub call that failed for a reason
# that can pass, such as a server error or a dropped connection.
GITHUB_RETRY_DELAYS="${SSH_RELEASE_GITHUB_RETRY_DELAYS:-2 5 10 20}"

# True when a GitHub CLI error cannot be cured by repeating the call: any 4xx
# answer other than a timeout (408) or a rate limit (429).
#
# @since  [NEXT_VERSION]
function _github_error_is_permanent() {
    local http_status
    http_status=$( printf '%s\n' "$1" | sed -n 's/.*HTTP \([0-9][0-9][0-9]\).*/\1/p' | sed -n '1p' )

    case "$http_status" in
        408|429)
            return 1
            ;;
        4??)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Run a GitHub CLI command, repeating it while it fails for a reason that can
# pass. The first argument is given to the command on stdin. Standard output is
# printed only when the command succeeds, and its last error only when it does
# not, so a caller capturing the output never receives part of an error as data.
#
# Only for calls that are safe to repeat. Creating a release is not one of them:
# see github_create_release.
#
# @since  [NEXT_VERSION]
function _github_with_retry() {
    local input="$1"
    shift

    local error_file output delay
    error_file=$( mktemp )

    for delay in 0 $GITHUB_RETRY_DELAYS; do
        sleep "$delay"

        if output=$( "$@" <<< "$input" 2>"$error_file" ); then
            rm -f -- "$error_file"
            printf '%s\n' "$output"

            return 0
        fi

        if _github_error_is_permanent "$( cat -- "$error_file" )"; then
            break
        fi
    done

    sed 's/^/   /' "$error_file" >&2
    rm -f -- "$error_file"

    return 1
}

# Print whether a published release exists for a tag: "exists", "absent", or
# "unknown" when GitHub did not give an answer either way.
#
# @since  [NEXT_VERSION]
function _github_release_state() {
    local output

    if output=$( gh release view "$1" --json isDraft -q '.isDraft' 2>&1 ); then
        if [ "$output" = "false" ]; then
            echo "exists"
        else
            echo "unknown"
        fi

        return 0
    fi

    case "$output" in
        *"release not found"*)
            echo "absent"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Create a GitHub release for the given version, using changelog notes.
#
# The notes are given to gh on stdin (`-F -`) rather than passed as a `-n`
# argument. A release body is the whole changelog section for the version, which
# routinely runs to tens of kilobytes, and Windows caps an entire command line at
# 32,767 characters - so a large section killed the call with "Argument list too
# long" before gh ever ran. Stdin has no such limit on any platform.
#
# A server error does not mean the release was not created: GitHub can publish
# it, start its workflows, and then fail to answer. So a failure is followed by a
# lookup of the tag, and the release is created again only when GitHub confirms
# that it does not exist. GitHub allows one release per tag, so when that lookup
# was out of date the repeat is refused as already existing, which is also proof
# that the release is there. On the first attempt the same refusal means that an
# earlier run made the release, and it is reported as a failure.
function github_create_release() {
    local VERSION="$1"
    local tag="v$VERSION"
    local RELEASE_NOTES="" output delay state
    local -a create_command

    if changelog_exists; then
        RELEASE_NOTES=$(extract_version_updates_from_changelog "$VERSION")
        create_command=( gh release create "$tag" -F - -t "$tag" )
    else
        create_command=( gh release create "$tag" -t "$tag" --generate-notes )
    fi

    if output=$( "${create_command[@]}" <<< "$RELEASE_NOTES" 2>&1 ); then
        return 0
    fi

    if ! _github_error_is_permanent "$output"; then
        for delay in $GITHUB_RETRY_DELAYS; do
            sleep "$delay"
            state=$( _github_release_state "$tag" )

            if [ "$state" = "exists" ]; then
                echo "    - GitHub answered with an error, but release $tag was created."

                return 0
            fi

            if [ "$state" = "unknown" ]; then
                continue
            fi

            if output=$( "${create_command[@]}" <<< "$RELEASE_NOTES" 2>&1 ); then
                return 0
            fi

            case "$output" in
                *"already exists"*|*"already_exists"*)
                    echo "    - GitHub answered with an error, but release $tag was created."

                    return 0
                    ;;
            esac

            if _github_error_is_permanent "$output"; then
                break
            fi
        done

        if [ "$( _github_release_state "$tag" )" = "exists" ]; then
            echo "    - GitHub answered with an error, but release $tag was created."

            return 0
        fi
    fi

    echo "Error: failed to create GitHub release $tag" >&2
    printf '   %s\n' "$output" >&2

    return 1
}

# Generate a GitHub compare URL between two tags. Prints nothing and fails when
# the repository cannot be determined.
function github_generate_tags_compare_link() {
    local prev_tag="$1"
    local current_tag="$2"
    local repo

    if ! repo=$( _github_with_retry "" gh repo view --json nameWithOwner -q '.nameWithOwner' ) || [ -z "$repo" ]; then
        return 1
    fi

    echo "https://github.com/${repo}/compare/${prev_tag}...${current_tag}"
}

# Append a "Full Changelog" compare link to an existing GitHub release.
#
# The edit replaces the whole body, so it is made only when the published notes
# were read. Without them it would leave a release whose notes are the link alone.
function github_release_add_compare_link() {
    local current_version="$1"
    local current_tag="v${current_version}"
    local prev_tag
    prev_tag=$(git tag -l --sort=-version:refname "v*" | sed -n '2p')

    if [ -z "$prev_tag" ]; then
        return 0
    fi

    local compare_url
    if ! compare_url=$( github_generate_tags_compare_link "$prev_tag" "$current_tag" ); then
        echo "Warning: could not read the repository name for the compare link of release $current_tag" >&2

        return 1
    fi

    local display="${prev_tag}...${current_tag}"
    local compare_line="**Full Changelog:** [\`${display}\`](${compare_url})"

    local existing_notes
    if ! existing_notes=$( _github_with_retry "" gh release view "$current_tag" --json body -q '.body' ) || [ -z "$existing_notes" ]; then
        echo "Warning: could not read the notes of release $current_tag, so they were left as they are" >&2

        return 1
    fi

    if [[ "$existing_notes" == *"$compare_url"* ]]; then
        return 0
    fi

    local updated_notes="${existing_notes}"$'\n\n'"${compare_line}"

    # Given on stdin for the same reason as github_create_release: the body being
    # rewritten here is the one that was just published, so passing it back as a
    # `--notes` argument hits the same command-line length ceiling.
    if ! _github_with_retry "$updated_notes" gh release edit "$current_tag" -F - >/dev/null; then
        echo "Warning: failed to add compare link to release $current_tag" >&2

        return 1
    fi
}
