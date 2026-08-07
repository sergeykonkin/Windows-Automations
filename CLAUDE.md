# CLAUDE.md

This repo is machine-specific Windows automation tooling, meant to live at the fixed path `D:\Automations` and be re-applied via `setup.ps1` after a Windows reinstall. See [README.md](README.md) for the full layout and usage.

## Conventions

- Each automation folder owns its own `register-task.ps1` (or `register.ps1` for the context-menu registry entry) — a small, self-contained script that defines and registers just that one thing. `setup.ps1` at the root is a thin orchestrator: dependency checks, then calling each folder's register script.
- Register scripts resolve their own paths via `$PSScriptRoot` (and `Split-Path $PSScriptRoot -Parent` for the shared `_shared` folder), and resolve the current user dynamically via `$env:USERDOMAIN\$env:USERNAME` — never hardcode a SID or username. This is what makes the tasks re-register cleanly after a reinstall, when Windows assigns a fresh SID.
- Hardcoded absolute paths (`D:\Automations`, `D:\Portable Programs\...`, `D:\Videos\Captures\Raw`, `D:\Videos\Captures\Cuts`, `C:\Program Files\HWiNFO64\...`) are intentional, not bugs — this tooling assumes a fixed D: drive layout that persists across reinstalls. Don't "fix" these into relative paths or parameters unless asked.
- New dependency on an external tool or PowerShell module? Add a check for it to the dependency-check block in `setup.ps1` (matching the existing `Test-Path` / `Get-Command` / `Get-Module` pattern) rather than assuming it'll be there.

## Things to watch for

- No secrets belong in this repo (it's scripts and Task Scheduler registration logic only). Double-check before committing anything new.
