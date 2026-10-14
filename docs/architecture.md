# Architecture

BackupBar follows the established SolverForge bar pattern:

```text
existing backup infrastructure
    -> bounded Ruby collectors
    -> normalized presenter state
    -> atomic snapshot.json
    -> Waybar chip + QuickShell drop-down panel
```

Waybar never calls Borg, Restic, Snapper, systemd, journalctl, or `df`. QuickShell never calls those sources either. The daemon is the only live-observation path.

The collectors are intentionally additive. They report what the machine already does: user anacron schedules, systemd timers, repository metadata, snapshot freshness, maintenance state, and storage pressure. They do not become a second backup orchestrator.

## Panel surface

The QuickShell panel is a **bounded bar drop-down**, not a screen overlay. The `PanelWindow` is anchored to the top bar edge on the chip's side (left, where the `custom/backupbar` module sits), hung below the Waybar island by a fixed 52px margin, and sized to exactly the card's rect: the height is counted from the parts actually laid out (visible job rows times row height, plus fixed chrome, plus the timeline strip) and capped to the real viewport minus the bar strip; the width is a fixed bar-drop width clamped to the viewport with a floor (never the screen's width). The surface reserves no layout space (`ExclusionMode.Ignore`) and never dims the desktop: there is no scrim and no backdrop catcher — the desktop under and beside the card stays visible and interactive.

Because the surface is bounded and transparent, Wayland input follows it exactly: clicks the card does not consume land on the desktop, and clicks inside the panel's own gutter strip (the window area outside the card's rounded corners) dismiss the panel. A bounded surface cannot see clicks that land on the desktop outside it, so the earlier "click anywhere on the desktop outside the card closes the panel" behavior of the full-screen surface is retired by design; dismissal is Esc (after clicking the panel — the surface takes keyboard focus only on demand), the Close button, or the gutter strip.

The state directory is private and atomic. Source errors are retained as structured status without persisting credentials, passphrase contents, raw command arguments, or unbounded command output.
