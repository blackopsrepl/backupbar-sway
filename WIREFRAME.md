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

Cards expose status, freshness (last successful run), next scheduled run, repository usage, retention, coverage, and source detail. The metric row carries the like-for-like headline (`N systems / M overdue`, the chip's own basis), the next run, latest good, attention detail, and storage peak. The constellation sits in a bounded list with a `scroll` overflow cue; the whole panel scrolls when the viewport is shorter than the content. The constellation graphic is decorative telemetry: it does not imply a second backup mechanism.

## Drop-down Surface

The panel is a bounded bar drop-down, not a screen overlay:

```text
 ▔▔▔▔▔▔▔▔▔▔▔ Waybar ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
 BB 5/6 ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
        │ ┌─────────────── card ───────┐ │
        │ └────────────────────────────┘ │
 ────── desktop stays visible ──────────
```

- The `PanelWindow` anchors to the top edge (and the chip's left edge) with `ExclusionMode.Ignore`: the surface is exactly the card's rect plus a 16px gutter, hung 52px below the bar for the shadow.
- Height is counted from the laid-out parts (visible job rows × 160, fixed chrome, the timeline strip) and capped to the real viewport minus the bar strip; width is a fixed bar-drop width clamped to the viewport with a floor. Nothing is ever a full-screen surface, and the card never covers the whole desktop.
- Dismissal: Esc (after clicking the panel), the Close button, or a click inside the gutter strip. There is no scrim and no backdrop catcher, and a bounded surface cannot see outside clicks — the older "click anywhere outside closes" behavior is retired.

## Status Contract

- `healthy`: source is reachable and its latest observation is within the expected cadence.
- `active`: a backup service is currently running.
- `warning`: the source is stale, a timer is inactive, storage is pressured, or a maintenance observation is overdue.
- `critical`: a recent backup cycle failed, a required source is unavailable, or a mount is critically full.
- `unknown`: the source cannot provide enough evidence.
- `stale`: the cached BackupBar snapshot itself exceeded its display age.
