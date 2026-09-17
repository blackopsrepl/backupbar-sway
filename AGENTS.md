# Repository Guidelines

## Product Contract

- BackupBar is a Linux-first Ruby application for observing existing backup infrastructure.
- The supported stack is Ruby + QuickShell QML + Waybar.
- The human-facing UI is `frontend/quickshell/shell.qml`.
- Waybar is a cached-state chip and launcher; it never performs live source reads.
- The application is read-only with respect to backup infrastructure. It must not trigger backups, prune repositories, remove locks, run repairs, or change credentials.
- Restic’s normal schedule is the user anacron configuration at `~/.anacrontab`; do not add another scheduler.

## Runtime Boundaries

- `backupbar daemon` owns bounded source observation and cached snapshots.
- `backupbar refresh` performs one read-only observation cycle.
- `backupbar waybar render` reads cached state only.
- `backupbar panel` opens QuickShell through the Ruby CLI.
- QuickShell reads `snapshot.json`, `ui.json`, and `state-event.json`; it does not call backup tools directly.
- External commands are invoked through `lib/backupbar/core/process.rb` with timeouts and fixed argument arrays.
- Secrets and passphrase contents must never enter runtime JSON, logs, tooltips, or QML.

## Sources

- Borg: systemd timer/service state, bounded journal state, and optional read-only `borg-timemachine info` through non-interactive sudo.
- Restic: existing SolverForge shell configuration, user anacron schedule, tagged snapshot metadata, and existing Restic repository state.
- Secret archive: existing `solverforge-backup-secrets.timer` and tagged Restic snapshots.
- Native metadata: `backup-rpmdb.timer` and `backup-sysconfig.timer`.
- Snapper: root config, snapshot directory inventory, and timeline/cleanup timers.
- Btrfs: scrub, balance, and trim timer state.
- Storage: bounded `df` reads for configured mount paths.

## UI Rules

- Use the existing Hackerman palette and Fira Code.
- Keep the bar terse; put system detail in QuickShell.
- The panel must remain centered, bounded, scroll-safe, and usable on narrow screens.
- Refresh is observation-only. Do not expose backup execution or destructive repository controls.
- Presenter output is view-ready; QML should not reproduce source classification rules.

## Validation

Run `make syntax`, `make test`, `make smoke`, `make qml-lint`, and `make check` before handoff.
