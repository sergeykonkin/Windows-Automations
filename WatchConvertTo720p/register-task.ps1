$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$user = "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew

$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$root\_shared\run-silent.vbs`" powershell.exe -ExecutionPolicy Bypass -File `"$PSScriptRoot\watch-convert-to-720p.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName 'Watch Convert To 720p' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "OK  Watch Convert To 720p"
