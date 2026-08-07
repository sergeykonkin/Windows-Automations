# OBS Screenshot Mover

OBS saves screenshots (`Tools > ...` hotkey action, or the "Screenshot" button)
into the same folder as recordings/streaming output. This moves each one out
to a separate destination folder right after it's saved, defaulting to
Windows' `Pictures\Screenshots` folder.

## Files

- `screenshot-mover.lua` — OBS script. Hooks
  `OBS_FRONTEND_EVENT_SCREENSHOT_TAKEN`, reads the saved path via
  `obs_frontend_get_last_screenshot()`, and moves the file to the
  configured destination folder (creating it if needed), disambiguating
  with a numeric suffix on a filename collision. Falls back to copy+delete
  when a plain rename fails (crossing drives, e.g. `D:\Videos\CaptureCuts`
  -> `D:\Pictures\Screenshots`). Pure Lua, no obs-websocket, no scheduled
  task — OBS's bundled Lua interpreter runs it with no separate install, and
  OBS keeps the script loaded across restarts once added.

  The default destination is computed by shelling out to
  `[Environment]::GetFolderPath('MyPictures')` via `powershell.exe`, so it
  follows the Pictures library's configured location (Explorer > Pictures >
  Properties > Location tab) instead of assuming `%USERPROFILE%\Pictures` —
  the latter is wrong if the library has been redirected (e.g. to `D:\Pictures`).

## Requirements

- OBS running (any recent version — `OBS_FRONTEND_EVENT_SCREENSHOT_TAKEN`
  and `obs_frontend_get_last_screenshot()` were added in OBS 29.0).

## Setup

One-time manual step (not driven by `setup.ps1` — there's no CLI hook into
OBS's script list):

1. OBS -> Tools -> Scripts.
2. Click **+**, select `screenshot-mover.lua` from this folder.
3. Optionally set "Destination folder" — defaults to `<Pictures library
   location>\Screenshots`.

Re-add after a Windows reinstall, same as `ObsReplayGameTag`.

The default is only computed once, the first time OBS initializes the
script's settings — if you added an earlier version of this script before
this default was Pictures-library-aware, it may have saved
`%USERPROFILE%\Pictures\Screenshots` already. Fix it by editing the
"Destination folder" field directly in the Scripts dialog rather than
removing and re-adding the script (removing and re-adding also works, but
loses nothing extra either way since there's no other state here).

## Debugging

- OBS -> Tools -> Scripts -> Script Log button shows this script's log
  lines (info on move, warnings on missing path/destination or move
  failure).
