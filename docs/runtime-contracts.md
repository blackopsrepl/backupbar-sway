# Runtime Contracts

## Config

Default: `~/.config/backupbar/config.json`.

The config schema is version `1`. It controls refresh cadence, command timeouts, state location, source paths, and display bounds. It does not contain backup credentials.

## Snapshot

Default: `~/.local/state/backupbar/snapshot.json`.

The snapshot contains `snapshotVersion`, `generatedAt`, `status`, `source`, `systems`, `storage`, `timeline`, `summary`, and presenter-owned `view` data. `state-event.json` is the single QuickShell reload marker.

### View projection

The panel renders only `view` facts; it derives nothing from raw sources.

- Per system: `latestText` / `ageSeconds` (last successful observation age), `nextAtText` ("in 47m"; `nextAt` is the source's own next scheduled elapse), `overdue` (a surfacing judgment only: `nextAt` is already past, or a backup has not completed within 48 hours — the same threshold collectors use for warning), and `repoUsageText` (repository footprint as the tool reports it, e.g. Borg's deduplicated "All archives" column).
- Summary: `headlineText` ("N systems / M overdue" on the same all-systems basis the Waybar chip uses, `N` = `systemCount`), `overdueCount`, plus the existing healthy/attention/storage fields.
- `view.context`: the earliest upcoming scheduled run across systems (`nextRunAt`, `nextRunLabel`, `nextRunText`), or `nil` when nothing is scheduled.

## Safety

All source commands use fixed argument arrays and bounded timeouts. The application reads existing Restic configuration but never writes it. Passphrase files are passed to Restic as paths and are never loaded into persisted state.
