# BackupBar Wireframe

## Waybar Chip

```text
BB 5/6       all observed systems healthy
BB LIVE      a backup service is currently active
BB 3/6 !2    two systems need attention
BB !1         a critical system or mount is failing
```

The chip is cached. A middle click requests a new observation cycle; a left click opens the panel.

## QuickShell Panel

```text
 +---------------------------------------------------------------------+
 | [orbit mark] BACKUPBAR   live backup telemetry    HEALTHY Refresh X |
 |             no-touch observer                                      |
 +---------------------------------------------------------------------+
 | systems healthy | latest good | attention | storage peak            |
 +---------------------------------------------------------------------+
 | BACKUP CONSTELLATION                         | PRESSURE MAP          |
 | [Borg] [Restic] [Secrets] [Metadata]         | /  76%               |
  | [Snapper] [Btrfs care]                       | /data 88%            |
  |                                              | /mnt/backup 89%      |
 +---------------------------------------------------------------------+
 | OBSERVATION STREAM  [Borg] [Restic] [Secrets] [storage pressure]    |
 +---------------------------------------------------------------------+
 | Refresh reads existing telemetry only. It never runs a backup.      |
 +---------------------------------------------------------------------+
```

Cards expose status, freshness, schedule, target, retention, coverage, and source detail. The constellation graphic is decorative telemetry: it does not imply a second backup mechanism.

## Status Contract

- `healthy`: source is reachable and its latest observation is within the expected cadence.
- `active`: a backup service is currently running.
- `warning`: the source is stale, a timer is inactive, storage is pressured, or a maintenance observation is overdue.
- `critical`: a recent backup cycle failed, a required source is unavailable, or a mount is critically full.
- `unknown`: the source cannot provide enough evidence.
- `stale`: the cached BackupBar snapshot itself exceeded its display age.
