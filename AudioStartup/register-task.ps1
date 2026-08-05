$ErrorActionPreference = 'Stop'

$user = "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew

$soundVolumeView = 'D:\Portable Programs\SoundVolumeView\SoundVolumeView.exe'
$actions = @(
    New-ScheduledTaskAction -Execute $soundVolumeView -Argument '/SetDefault "Speakers" 1'
    New-ScheduledTaskAction -Execute $soundVolumeView -Argument '/SetVolume "Speakers" 50'
    New-ScheduledTaskAction -Execute $soundVolumeView -Argument '/SetVolume "Headphones" 75'
    New-ScheduledTaskAction -Execute $soundVolumeView -Argument '/Mute "Microphone"'
)
$trigger = New-ScheduledTaskTrigger -AtLogOn
$trigger.Delay = 'PT10S'
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName 'Audio Startup' -Action $actions -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "OK  Audio Startup"
