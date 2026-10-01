$ErrorActionPreference = 'Stop'

$user = "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
$root = Split-Path $PSScriptRoot -Parent
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$root\_shared\run-hidden-wait.vbs`" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSScriptRoot\configure-audio.ps1`""

# The script retries inside this single logon run until all settings are verified.
$logon = New-ScheduledTaskTrigger -AtLogOn
$logon.Delay = 'PT10S'
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName 'Audio Startup' -Action $action -Trigger $logon -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
if (Get-ScheduledTask -TaskName 'Audio Communications Repair' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'Audio Communications Repair' -Confirm:$false -ErrorAction Stop
}
Write-Host 'OK  Audio Startup'
