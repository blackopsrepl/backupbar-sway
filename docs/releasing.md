# Releasing BackupBar

BackupBar releases are published to the `blackopsrepl/backupbar-sway` repository on the local Forgejo instance. GitHub workflows, GitHub releases, and GitHub-specific actions are not part of this process.

## Prepare

Work from a clean `main` checkout with the Forgejo remote configured as `origin`:

```bash
npm ci
make check
git status --short --branch
```

Use conventional commit subjects. The release tool uses them to generate `CHANGELOG.md`; do not edit that file by hand.

## Cut A Release

Choose the semantic version increment explicitly:

```bash
npm run release -- --release-as patch
```

Use `minor` or `major` when the public API requires it. Inspect the generated version bump, changelog, release commit, and tag before publishing:

```bash
git show --stat --oneline HEAD
git show --format=fuller HEAD
git tag --points-at HEAD
git status --short --branch
```

Publish the release commit and tag to Forgejo:

```bash
git push origin main --follow-tags
```

## Forgejo Actions

Pushing a `v*` tag starts `.forgejo/workflows/release.yml`. The workflow:

1. Runs `make check` on the Ruby runner and installs the QML lint tooling required by the project.
2. Verifies that the tag version matches `BackupBar::VERSION`.
3. Builds `backupbar-<version>.tar.gz` from the tagged tree.
4. Builds the matching `backupbar-<version>.tar.gz.sha256` checksum.
5. Creates or reuses the Forgejo release for the tag and uploads both assets through the Forgejo API using its temporary repository token.

The `main` and pull-request checks run from `.forgejo/workflows/ci.yml`. A release is not complete until the release workflow is successful and the assets are visible on the Forgejo release page.

## Recovery

If a release workflow fails before publishing, fix the issue and rerun the workflow for the same tag from Forgejo. The publish step is idempotent for an existing release and skips assets that are already present.

Do not move or recreate a tag to hide a failed release. If the tagged source itself is wrong, create the next corrective version and publish that tag normally.
