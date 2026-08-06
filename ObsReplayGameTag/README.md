# OBS Replay Game Tag

Renames each replay-buffer save to include the name of the currently
captured game, e.g. `Replay_2026-08-06_01-13-54.mkv` ->
`Replay_2026-08-06_01-13-54_Counter_Strike_2.mkv`.

## Files

- `replay-game-tag.lua` — OBS script. Hooks
  `OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED`, reads the game name off the
  `"Game Capture"` input's `window` setting (the same value
  `ObsAutoGameCapture`'s `set-obs-game-capture.ps1` writes there when it
  binds a game), and renames the saved file. Pure Lua, no obs-websocket, no
  scheduled task — OBS's bundled Lua interpreter runs it with no separate
  install, and OBS keeps the script loaded across restarts once added.

## Requirements

- OBS running with an input named `"Game Capture"` (`inputKind: game_capture`)
  — configurable via the script's "Game Capture input name" property if
  named differently. Falls back to the unique `game_capture`-kind input if
  the configured name isn't found.
- Depends on something else (e.g. `ObsAutoGameCapture`) having already
  pointed that input's `window` setting at a game. If no game is currently
  captured when a replay saves, the file is left unchanged.

## Setup

One-time manual step (not driven by `setup.ps1` — there's no CLI hook into
OBS's script list):

1. OBS -> Tools -> Scripts.
2. Click **+**, select `replay-game-tag.lua` from this folder.

Re-add after a Windows reinstall, same as re-entering `OBS_WS_SERVER_PASSWORD`
for `ObsAutoGameCapture`.

## Debugging

- OBS -> Tools -> Scripts -> Script Log button shows this script's log
  lines (info on skip/tag, warnings on parse/rename failure).
