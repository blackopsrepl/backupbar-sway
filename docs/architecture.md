# Architecture

BackupBar follows the established SolverForge bar pattern:

```text
existing backup infrastructure
        -> bounded Ruby collectors
        -> normalized presenter state
        -> atomic snapshot.json
        -> Waybar chip + QuickShell panel
```

Waybar never calls Borg, Restic, Snapper, systemd, journalctl, or `df`. QuickShell never calls those sources either. The daemon is the only live-observation path.

The collectors are intentionally additive. They report what the machine already does: user anacron schedules, systemd timers, repository metadata, snapshot freshness, maintenance state, and storage pressure. They do not become a second backup orchestrator.

The state directory is private and atomic. Source errors are retained as structured status without persisting credentials, passphrase contents, raw command arguments, or unbounded command output.
