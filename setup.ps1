<#
Run this once after a fresh Windows install, with the D: drive already
mounted and D:\Automations intact, to re-register all scheduled-task
automations and the "Convert to 720p" context menu.

Just double-click / right-click "Run with PowerShell" - it self-elevates.
#>

$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isElevated) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = 'Stop'
$root = 'D:\Automations'

if (-not (Test-Path $root)) {
    throw "D:\Automations not found. Is the D: drive mounted and the Automations folder present?"
}

Write-Host "--- dependency check ---"
$checks = @(
    @{ Path = 'D:\Portable Programs\SoundVolumeView\SoundVolumeView.exe'; Name = 'SoundVolumeView.exe' }
    @{ Path = "$root\_shared\run-silent.vbs"; Name = 'run-silent.vbs' }
    @{ Path = "$root\_shared\start-after.vbs"; Name = 'start-after.vbs' }
    @{ Path = "$root\CS2ProfileReminder\cs2-profile-reminder.ps1"; Name = 'cs2-profile-reminder.ps1' }
    @{ Path = "$root\WatchConvertTo720p\watch-convert-to-720p.ps1"; Name = 'watch-convert-to-720p.ps1' }
    @{ Path = "$root\ConvertTo720pContextMenu\convert-to-720p.bat"; Name = 'convert-to-720p.bat' }
    @{ Path = "$root\ConvertTo720pContextMenu\convert-to-720p.reg"; Name = 'convert-to-720p.reg' }
    @{ Path = 'C:\Program Files\HWiNFO64\HWiNFO64.EXE'; Name = 'HWiNFO64.EXE (used by disabled task, optional)' }
)
foreach ($c in $checks) {
    if (Test-Path $c.Path) {
        Write-Host "OK       $($c.Name)" -ForegroundColor Green
    } else {
        Write-Host "MISSING  $($c.Name) -> $($c.Path)" -ForegroundColor Yellow
    }
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "MISSING  ffmpeg not found on PATH (needed by Convert to 720p / Watch Convert To 720p)" -ForegroundColor Yellow
} else {
    Write-Host "OK       ffmpeg on PATH" -ForegroundColor Green
}
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Host "MISSING  BurntToast PowerShell module (needed by CS2 Keyboard Profile Reminder) -> Install-Module BurntToast" -ForegroundColor Yellow
} else {
    Write-Host "OK       BurntToast module" -ForegroundColor Green
}

Write-Host "`n--- registering tasks ---"
& "$root\AudioStartup\register-task.ps1"
& "$root\CS2ProfileReminder\register-task.ps1"
& "$root\WatchConvertTo720p\register-task.ps1"
& "$root\StartHWiNFOAfterRTSS\register-task.ps1"

Write-Host "`n--- registry: Convert to 720p context menu ---"
& "$root\ConvertTo720pContextMenu\register.ps1"

Write-Host "`nDone. Reboot (or log off/on) and confirm the tasks show LastTaskResult 0."
Read-Host "Press Enter to close"
