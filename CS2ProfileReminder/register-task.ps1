$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$user = "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew

$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$root\_shared\run-silent.vbs`" powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\cs2-profile-reminder.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName 'CS2 Keyboard Profile Reminder' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "OK  CS2 Keyboard Profile Reminder"
