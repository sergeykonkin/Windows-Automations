$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$user = "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew

$action = New-ScheduledTaskAction -Execute "$root\_shared\start-after.vbs" -Argument '"C:\Program Files\HWiNFO64\HWiNFO64.EXE" "RTSS.exe"'
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName 'Start HWiNFO After RTSS' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Disable-ScheduledTask -TaskName 'Start HWiNFO After RTSS' | Out-Null
Write-Host "OK  Start HWiNFO After RTSS (disabled)"
