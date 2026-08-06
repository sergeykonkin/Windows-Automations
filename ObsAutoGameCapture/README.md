# OBS Auto Game Capture

Watches for Steam games starting/exiting and points OBS's "Game Capture"
source at the game's window automatically, disabling it again on exit.
Replaces Display Capture, which introduces latency/performance overhead.
At the same time, retargets the "Game Audio" source
(`wasapi_process_output_capture`) at the same game, so its audio switches
along with the video.

## Files

- `obs-auto-game-capture.ps1` — long-running watcher, registered as a
  scheduled task at logon. Polls `Get-Process` every 3s for processes under
  `D:\Games\Steam\steamapps\common\`, and shells out to the connector on
  launch/exit. Guards against duplicate instances via a named mutex.
- `set-obs-game-capture.ps1` — one-shot PowerShell connector, invoked per
  event via a raw `System.Net.WebSockets.ClientWebSocket`. Talks to
  obs-websocket v5 (`ws://127.0.0.1:4455`) to retarget the "Game Capture"
  input, fit it to the canvas, and enable/disable the scene item. Also
  retargets and enables/disables "Game Audio" at the same exe,
  best-effort (a missing/renamed audio input logs a warning but doesn't fail
  the game-capture side). Pure PowerShell + .NET, no external runtime
  dependency.
- `register-task.ps1` — registers the watcher as the "OBS Auto Game Capture"
  scheduled task.

## Requirements

- OBS running with obs-websocket enabled, a scene named `Scene` containing
  an input named `Game Capture` (`inputKind: game_capture`) and, optionally,
  an input named `Game Audio` (`inputKind:
  wasapi_process_output_capture`) for audio to switch alongside it.
- A user-scope `OBS_WS_SERVER_PASSWORD` environment variable holding the
  obs-websocket server password (never committed to this repo). Setting or
  changing it requires a fresh logon (or a task restart) to take effect.

## Debugging

- Log: `obs-auto-game-capture.log` in this folder (rotates at ~1MB).
- `powershell -File set-obs-game-capture.ps1 -List` dumps OBS's current
  scenes, inputs, and the live list of windows it can capture — the main
  tool for figuring out why a game isn't being picked up.
