$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$user = "$env:USERDOMAIN\$env:USERNAME"

# Default ExecutionTimeLimit is 3 days (PT72H) - this watcher needs to run
# indefinitely, and should restart itself if it ever crashes.
#
# -MultipleInstances IgnoreNew doesn't actually prevent duplicate instances here:
# run-silent.vbs's `shell.Run cmd, 0, False` detaches the real long-running
# powershell.exe from the wscript.exe process Task Scheduler tracks, so neither
# this setting nor Stop-ScheduledTask can see or stop it. The watcher script
# guards against duplicates itself instead, via a named mutex - see its top.
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$root\_shared\run-silent.vbs`" powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\obs-auto-game-capture.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$trigger.Delay = 'PT15S'
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName 'OBS Auto Game Capture' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "OK  OBS Auto Game Capture"
