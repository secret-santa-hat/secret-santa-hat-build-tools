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

# Print owner/name for the current repo via the GitHub CLI.
function get_github_repo_info() {
    gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null
}

# Create a GitHub release for the given version, using changelog notes.
#
# The notes are piped to gh on stdin (`-F -`) rather than passed as a `-n`
# argument. A release body is the whole changelog section for the version, which
# routinely runs to tens of kilobytes, and Windows caps an entire command line at
# 32,767 characters - so a large section killed the call with "Argument list too
# long" before gh ever ran. Stdin has no such limit on any platform.
function github_create_release() {
    local VERSION="$1"
    local output

    if changelog_exists; then
        local RELEASE_NOTES
        RELEASE_NOTES=$(extract_version_updates_from_changelog "$VERSION")

        if ! output=$(printf '%s\n' "$RELEASE_NOTES" | gh release create "v$VERSION" -F - -t "v$VERSION" 2>&1); then
            echo "Error: failed to create GitHub release v$VERSION" >&2
            printf '   %s\n' "$output" >&2

            return 1
        fi
    else
        if ! output=$(gh release create "v$VERSION" -t "v$VERSION" --generate-notes 2>&1); then
            echo "Error: failed to create GitHub release v$VERSION" >&2
            printf '   %s\n' "$output" >&2

            return 1
        fi
    fi
}

# Generate a GitHub compare URL between two tags.
function github_generate_tags_compare_link() {
    local prev_tag="$1"
    local current_tag="$2"
    local repo
    repo=$(get_github_repo_info)

    echo "https://github.com/${repo}/compare/${prev_tag}...${current_tag}"
}

# Append a "Full Changelog" compare link to an existing GitHub release.
function github_release_add_compare_link() {
    local current_version="$1"
    local current_tag="v${current_version}"
    local prev_tag
    prev_tag=$(git tag -l --sort=-version:refname "v*" | sed -n '2p')

    if [ -z "$prev_tag" ]; then
        return 0
    fi

    local compare_url
    compare_url=$(github_generate_tags_compare_link "$prev_tag" "$current_tag")

    local display="${prev_tag}...${current_tag}"
    local compare_line="**Full Changelog:** [\`${display}\`](${compare_url})"

    local existing_notes
    existing_notes=$(gh release view "$current_tag" --json body -q '.body' 2>/dev/null)

    local updated_notes="${existing_notes}"$'\n\n'"${compare_line}"

    # Piped on stdin for the same reason as github_create_release: the body being
    # rewritten here is the one that was just published, so passing it back as a
    # `--notes` argument hits the same command-line length ceiling.
    local output
    if ! output=$(printf '%s\n' "$updated_notes" | gh release edit "$current_tag" -F - 2>&1); then
        echo "Warning: failed to add compare link to release $current_tag" >&2
        printf '   %s\n' "$output" >&2

        return 1
    fi
}
