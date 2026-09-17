# Runtime Contracts

## Config

Default: `~/.config/backupbar/config.json`.

The config schema is version `1`. It controls refresh cadence, command timeouts, state location, source paths, and display bounds. It does not contain backup credentials.

## Snapshot

Default: `~/.local/state/backupbar/snapshot.json`.

The snapshot contains `snapshotVersion`, `generatedAt`, `status`, `source`, `systems`, `storage`, `timeline`, `summary`, and presenter-owned `view` data. `state-event.json` is the single QuickShell reload marker.

## Safety

All source commands use fixed argument arrays and bounded timeouts. The application reads existing Restic configuration but never writes it. Passphrase files are passed to Restic as paths and are never loaded into persisted state.
