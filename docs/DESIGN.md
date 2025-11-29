# Bottleneck Design

## Architecture

- Modular PowerShell (src/ps)
- Entry scripts (scripts/)
- Reports (artifacts/)
- Extensible for GUI (Tauri/React)

## Object Model

Each check returns:

```
{ Id, Tier, Category, Impact, Confidence, Effort, Priority, Evidence, FixId, Message }
```

## Scoring

Score = (Impact × Confidence) ÷ (Effort + 1)

## Fixes

All fixes create a restore point before changes.
