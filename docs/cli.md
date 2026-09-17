# CLI

```text
backupbar config init|validate
backupbar snapshot [--format json] [--pretty]
backupbar refresh [--format json]
backupbar status [--format json]
backupbar daemon [--once]
backupbar panel
backupbar ui open|close|toggle|status
backupbar waybar render|refresh|panel
```

`waybar render` is cache-only. `refresh` and `snapshot` perform bounded read-only observation. `panel` and `ui` only control the QuickShell surface.
