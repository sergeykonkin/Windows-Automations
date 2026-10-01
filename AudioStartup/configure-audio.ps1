param([switch]$Check)

$ErrorActionPreference = 'Stop'
$soundVolumeView = 'D:\Portable Programs\SoundVolumeView\SoundVolumeView.exe'
$logPath = Join-Path $PSScriptRoot 'audio-startup.log'
$snapshot = Join-Path $env:TEMP "audio-startup-$PID.csv"

function Write-Log([string]$Message) {
    if ($Check) {
        Write-Host $Message
        return
    }
    $dir = Split-Path $logPath -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1MB) {
        Move-Item -LiteralPath $logPath -Destination "$logPath.old" -Force
    }
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) $Message" -Encoding UTF8
}

function Invoke-SoundVolumeView([string]$Arguments) {
    $process = Start-Process -FilePath $soundVolumeView -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "SoundVolumeView failed ($($process.ExitCode)): $Arguments"
    }
}

function Get-Devices {
    Remove-Item -LiteralPath $snapshot -ErrorAction SilentlyContinue
    Invoke-SoundVolumeView "/scomma `"$snapshot`""
    if (-not (Test-Path $snapshot)) {
        throw 'SoundVolumeView did not export the device list.'
    }
    @(Import-Csv -LiteralPath $snapshot | Where-Object { $_.Type -eq 'Device' -and $_.'Device State' -eq 'Active' })
}

function Find-Device($Devices, [string]$Name, [string]$Direction) {
    $matches = @($Devices | Where-Object { $_.Name -eq $Name -and $_.Direction -eq $Direction })
    if ($matches.Count -gt 1) {
        throw "Ambiguous device: $Name ($Direction)"
    }
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Set-IfNeeded([bool]$Needed, [string]$Description, [string]$Arguments) {
    if (-not $Needed) { return }
    Write-Log $Description
    if (-not $Check) { Invoke-SoundVolumeView $Arguments }
}

function Set-AudioConfiguration {
    if (-not (Test-Path -LiteralPath $soundVolumeView)) {
        throw "SoundVolumeView is missing: $soundVolumeView"
    }
    $devices = Get-Devices
    $headphones = Find-Device $devices 'Headphones' 'Render'
    $speakers = Find-Device $devices 'Speakers' 'Render'
    $microphone = Find-Device $devices 'Microphone' 'Capture'
    if ($null -eq $headphones -or $null -eq $speakers -or $null -eq $microphone) {
        throw 'Waiting for active Speakers, Headphones, and Microphone devices.'
    }

    $headphonesArg = '"' + $headphones.'Command-Line Friendly ID' + '"'
    Set-IfNeeded ($headphones.'Default Communications' -ne 'Render') 'Set Headphones as communications output' "/SetDefault $headphonesArg 2"

    $speakersArg = '"' + $speakers.'Command-Line Friendly ID' + '"'
    Set-IfNeeded ($speakers.Default -ne 'Render') 'Set Speakers as console output' "/SetDefault $speakersArg 0"
    Set-IfNeeded ($speakers.'Default Multimedia' -ne 'Render') 'Set Speakers as multimedia output' "/SetDefault $speakersArg 1"
    Set-IfNeeded ([math]::Abs([double]::Parse($speakers.'Volume Percent'.TrimEnd('%'), [cultureinfo]::InvariantCulture) - 50) -gt 0.5) 'Set Speakers volume to 50%' "/SetVolume $speakersArg 50"

    Set-IfNeeded ([math]::Abs([double]::Parse($headphones.'Volume Percent'.TrimEnd('%'), [cultureinfo]::InvariantCulture) - 75) -gt 0.5) 'Set Headphones volume to 75%' "/SetVolume $headphonesArg 75"

    $microphoneArg = '"' + $microphone.'Command-Line Friendly ID' + '"'
    Set-IfNeeded ($microphone.Muted -ne 'Yes') 'Mute Microphone' "/Mute $microphoneArg"

    if (-not $Check) {
        $final = Get-Devices
        $finalHeadphones = Find-Device $final 'Headphones' 'Render'
        $finalSpeakers = Find-Device $final 'Speakers' 'Render'
        $finalMicrophone = Find-Device $final 'Microphone' 'Capture'
        if ($null -eq $finalHeadphones -or $finalHeadphones.'Default Communications' -ne 'Render') {
            $currentCommunications = @($final | Where-Object { $_.Direction -eq 'Render' -and $_.'Default Communications' -eq 'Render' } | ForEach-Object { $_.Name }) -join ', '
            if (-not $currentCommunications) { $currentCommunications = 'none' }
            throw "Headphones are not the default communications output; current: $currentCommunications."
        }
        if ($null -eq $finalSpeakers -or $finalSpeakers.Default -ne 'Render' -or $finalSpeakers.'Default Multimedia' -ne 'Render') {
            throw 'Speakers are still not the default console and multimedia output.'
        }
        if ([math]::Abs([double]::Parse($finalSpeakers.'Volume Percent'.TrimEnd('%'), [cultureinfo]::InvariantCulture) - 50) -gt 0.5) {
            throw 'Speakers volume is still not 50%.'
        }
        if ([math]::Abs([double]::Parse($finalHeadphones.'Volume Percent'.TrimEnd('%'), [cultureinfo]::InvariantCulture) - 75) -gt 0.5) {
            throw 'Headphones volume is still not 75%.'
        }
        if ($null -eq $finalMicrophone -or $finalMicrophone.Muted -ne 'Yes') {
            throw 'Microphone is still not muted.'
        }
    }
}

if ($Check) {
    try { Set-AudioConfiguration } finally { Remove-Item -LiteralPath $snapshot -ErrorAction SilentlyContinue }
    return
}

Write-Log 'Audio startup run began.'
while ($true) {
    try {
        Set-AudioConfiguration
        Write-Log 'Audio configuration verified; startup task finished.'
        break
    } catch {
        Write-Log "Retrying audio configuration in 5 seconds: $_"
    } finally {
        Remove-Item -LiteralPath $snapshot -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 5
}
