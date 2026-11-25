# Changelog

## [NEXT_VERSION] - [UNRELEASED]
* ENH: Release - GitHub calls that fail with a server error, a rate limit or a dropped connection are repeated, up to four times over 37 seconds. `SSH_RELEASE_GITHUB_RETRY_DELAYS` changes the waits.
* ENH: Release - When the GitHub release cannot be created or confirmed, the error lists what was pushed and the commands that finish the release.
* BUG: Release - A GitHub error while the release is created no longer stops a release that GitHub did create. The tag is looked up, and the release is created again only when GitHub confirms it does not exist.
* BUG: Release - The compare link is added only when the published notes were read. A failed read followed by a working edit replaced the notes with the link alone.
* BUG: Release - A failed repository lookup no longer publishes a compare link with no repository in its address.

## [0.2.10] - 2026-11-23
* TSK: Dependencies - Weekly action bumps ( Dependabot #1 ): `actions/checkout` 7.0.1, `actions/setup-node` 7.1.0. Workflow pins only.

## [0.2.9] - 2026-11-18
* BUG: Release - A file the release adds that survives the switch to the default branch as an untracked copy no longer stops the merge. On Windows, `git checkout` only warns when another process holds the file open, so the copy stays behind and git refuses to merge over it. An untracked copy identical to the release version is now removed before the merge; one that differs is left for git to report.
* BUG: Release - A merge that git refuses without starting is no longer reported as conflicts with Dependabot bumps. The error now prints what git said and, when no merge was started, the two commands that finish the release.
* TSK: Workflows - Every action is pinned to a commit hash with its version recorded alongside, so a moved tag cannot change what publishes the package.
* TSK: Workflows - A zizmor config, so the workflow can be audited with `uvx zizmor .github/workflows`. Its one suppression is cache poisoning on the publish workflow, which runs only from a published release.
* TSK: Dependencies - A Dependabot config for GitHub Actions. The package has no runtime dependencies, so the pinned actions are the only thing here with a version to keep current.

## [0.2.8] - 2026-08-08
* BUG: Release - A release that fails partway now says so. The whole run happens inside `ssh_create_release`, and bash executes an `ERR` trap only in the shell that installed it unless `errtrace` is set, which it was not - so every failure inside that function exited `1` having printed nothing at all. The last thing on screen was whichever step had just succeeded, which reads exactly like a release that finished. `set -E` puts the trap back in reach of the function.
* BUG: Release - Switching to the default branch for the merge reports what git said instead of discarding it. The step is the first one after the release branch, the tag and the GitHub release are all published, so it fails for reasons that have nothing to do with the release - an index lock an editor is holding, a file a running dev server has open - and when it does the release is stranded half-finished with the shell still sitting on the release branch. That is where the next commit then lands by mistake. The failure now names itself and prints the three commands that finish the release.
* BUG: Release - Returning to the working branch at the end warns when it fails rather than passing silently. The release is complete by then, but the alternative is being left on the default branch holding an uncommitted changelog template with nothing said about it.

## [0.2.7] - 2026-08-02
* BUG: Release - Hand the release notes to `gh` on stdin instead of passing them as a command-line argument. Windows caps an entire command line at 32,767 characters, so a changelog section of any real size - a major release runs to tens of kilobytes - killed the call with "Argument list too long" and aborted the release after the version bump, branch and tag had already been pushed. The compare-link edit that follows rewrites that same body and had the same ceiling. A failed `gh` call now also reports what it said rather than discarding its output.

## [0.2.6] - 2026-07-22
* BUG: Release - Sync the default branch with its remote before merging a release into it. Commits that land on the default branch directly on the remote - most often Dependabot pull requests merged from the GitHub UI - left the local branch stale, so the release merged onto an out-of-date base and the push was rejected as a non-fast-forward. Because the tag and GitHub release were already created, the release aborted half-finished and stranded the working branch on the default branch. The default branch is now fast-forwarded to its remote first, and a failed sync, merge, or push stops with a clear reason instead of ending silently.

## [0.2.5] - 2026-07-21
* TSK: Metadata - Point the package `repository`, `bugs` and `homepage` URLs at the `secret-santa-hat` GitHub org after the repository transfer.

## [0.2.4] - 2026-07-16
* BUG: Release - Don't display the tag URL in stdout.

## [0.2.3] - 2026-07-16
* BUG: Run the `preflight` checks on `--dry-run` too. A dry run should exercise the same pre-release checks a real release does; only the git operations are skipped. 0.2.2 wrongly skipped preflight on a dry run.

## [0.2.2] - 2026-07-16
* FEA: Run pre-release checks from `ssh-release`. When the project defines a `preflight` script, `ssh-release` runs it with output captured - one line on success, the full output only on failure - so a normal release stays quiet. Name it `preflight` rather than the yarn/npm `prerelease` hook, which runs verbosely in a separate process before `ssh-release` and cannot be quieted. Skipped on `--dry-run`.

## [0.2.1] - 2026-07-16
* TWK: Bump the service worker `APP_VERSION` in place at release time (like `package.json`) instead of swapping it to and from a `[NEXT_VERSION]` template, so `public/sw.js` always holds the real version. Removes the post-release reset.

## [0.2.0] - 2026-07-16
* FEA: Self-update the build tools at the start of a release - when a newer `@secret-santa-hat/build-tools` is published, `ssh-release` upgrades it, records a `TSK: Updated @secret-santa-hat/build-tools to vX` changelog entry, and commits and pushes it (so every release runs on the latest tooling). Also available standalone as `ssh-update`; opt out with `SSH_RELEASE_NO_SELF_UPDATE=1`.

## [0.1.2] - 2026-07-16
* BUG: Release - Exclude `README.md` from the `[NEXT_VERSION]` placeholder replacement, so documentation that shows the literal `[NEXT_VERSION]` is no longer rewritten to the version number at release time.
* TSK: Publish releases from CI via GitHub Actions with npm OIDC trusted publishing, so releases no longer need a local npm token. `npmcr` detects the `publish-npm.yml` workflow and skips the manual publish.

## [0.1.1] - 2026-07-16
* TSK: Publish under the `@secret-santa-hat` npm organization as `@secret-santa-hat/build-tools`, moving it out of `@dream-encode`.

## [0.1.0] - 2026-07-16
* FEA: Initial release. Ships the `ssh-release` command, a JavaScript-tailored port of the `gcrq` (`git_create_release_quiet`) bash flow: branch and changelog guards, version bump across `package.json` and `public/manifest.json`, `[NEXT_VERSION]` placeholder replacement, changelog finalize and re-seed, release branch and tag, GitHub release with a compare link, merge to the default branch, and a service-worker version reset. Includes a postinstall that offers to wire a `release` script into the consuming project.
