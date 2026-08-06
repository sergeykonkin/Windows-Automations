# Windows-Automations

Personal collection of Windows automation scripts and scheduled-task definitions, kept on `D:\Automations` so they survive a Windows reinstall on the C: drive.

## Layout

Each folder is a self-contained automation:

- **AudioStartup** — sets default output device and volumes at logon via SoundVolumeView.
- **CS2ProfileReminder** — shows a toast notification when `cs2.exe` starts, reminding to switch keyboard profile.
- **ConvertTo720pContextMenu** — adds a "Convert to 720p" right-click context menu entry for video files (ffmpeg + NVENC).
- **WatchConvertTo720p** — watches `D:\Videos\CaptureCuts` for new `.mkv` files and auto-converts them to 720p.
- **StartHWiNFOAfterRTSS** — starts HWiNFO64 once RTSS is running (registered disabled by default).
- **ObsAutoGameCapture** — polls for Steam games starting/exiting under `D:\Games\Steam\steamapps\common` and switches OBS's "Game Capture" source to match via obs-websocket, disabling it when no game is running. See its `README.md` for details.
- **ObsReplayGameTag** — OBS Lua script (loaded via Tools > Scripts, not a scheduled task) that renames each saved replay buffer file to include the currently captured game's name. See its `README.md` for the one-time setup step.
- **_shared** — small VBScript helpers (`run-silent.vbs`, `start-after.vbs`) used by the scheduled tasks above.

Each automation folder that registers a scheduled task has its own `register-task.ps1`; `ConvertTo720pContextMenu` has `register.ps1` for its registry entry instead. `ObsReplayGameTag` is loaded directly by OBS and registers nothing.

## Usage

After a fresh Windows install, with the D: drive mounted and this repo present at `D:\Automations`:

```powershell
D:\Automations\setup.ps1
```

It self-elevates, runs a dependency check, then re-registers all scheduled tasks and the context-menu entry.

### Dependencies

- [ffmpeg](https://ffmpeg.org/) on `PATH` (with NVENC support)
- [SoundVolumeView](https://www.nirsoft.net/utils/sound_volume_view.html) at `D:\Portable Programs\SoundVolumeView\SoundVolumeView.exe`
- [BurntToast](https://github.com/Windos/BurntToast) PowerShell module (`Install-Module BurntToast`)
- [HWiNFO64](https://www.hwinfo.com/) at `C:\Program Files\HWiNFO64\HWiNFO64.EXE` (optional — only needed for the disabled task)
- OBS with the obs-websocket server enabled on `ws://localhost:4455` (used by ObsAutoGameCapture)
- A user-scope `OBS_WS_SERVER_PASSWORD` environment variable holding the obs-websocket server password — set this manually (`[Environment]::SetEnvironmentVariable('OBS_WS_SERVER_PASSWORD','<value>','User')`), it is never committed to this repo. **Setting or changing it requires a log off/on** (or at least a restart of the "OBS Auto Game Capture" task) before the already-running watcher picks it up — Scheduled Tasks inherit the environment from the logon session, not live.

`setup.ps1` reports which of these are missing.
