Add-Type -AssemblyName System.Windows.Forms

$WatchPath = "D:\Videos\CaptureCuts"
if (-not (Test-Path -LiteralPath $WatchPath)) {
    New-Item -ItemType Directory -Force -Path $WatchPath | Out-Null
}

$Processed = New-Object 'System.Collections.Generic.HashSet[string]'
$InProgress = [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()

function Wait-ForFileReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $lastSize = -1

    while ($true) {
        if (-not (Test-Path -LiteralPath $Path)) {
            Start-Sleep -Seconds 1
            continue
        }

        try {
            $item = Get-Item -LiteralPath $Path -ErrorAction Stop
            $size = $item.Length

            $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
            $stream.Close()

            if ($size -eq $lastSize) {
                return
            }

            $lastSize = $size
        }
        catch {
        }

        Start-Sleep -Seconds 1
    }
}

function Copy-FileToClipboard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $files = New-Object System.Collections.Specialized.StringCollection
    [void]$files.Add($Path)
    [System.Windows.Forms.Clipboard]::SetFileDropList($files)
}

function Convert-To720p {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        return
    }

    $fullPath = [System.IO.Path]::GetFullPath($InputPath)

    if ($Processed.Contains($fullPath)) {
        return
    }

    if (-not $InProgress.TryAdd($fullPath, $true)) {
        return
    }

    try {
        Wait-ForFileReady -Path $fullPath

        $directory = [System.IO.Path]::GetDirectoryName($fullPath)
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
        $outputPath = Join-Path $directory ($nameWithoutExt + "_720p.mp4")

        if (Test-Path -LiteralPath $outputPath) {
            [void]$Processed.Add($fullPath)
            Copy-FileToClipboard -Path $outputPath
            return
        }

        $process = Start-Process `
            -FilePath "ffmpeg.exe" `
            -ArgumentList @(
                "-hwaccel", "cuda",
                "-i", $fullPath,
                "-vf", "scale=-1:720",
                "-c:v", "h264_nvenc",
                "-preset", "slow",
                "-b:v", "8M",
                "-c:a", "aac",
                "-b:a", "128k",
                $outputPath
            ) `
            -PassThru `
            -Wait

        if ($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $outputPath)) {
            [void]$Processed.Add($fullPath)
            Copy-FileToClipboard -Path $outputPath
        }
    }
    finally {
        $removedValue = $false
        [void]$InProgress.TryRemove($fullPath, [ref]$removedValue)
    }
}

Get-EventSubscriber | Where-Object {
    $_.SourceObject -is [System.IO.FileSystemWatcher] -and
    $_.SourceObject.Path -eq $WatchPath
} | Unregister-Event

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $WatchPath
$watcher.Filter = "*.mkv"
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$action = {
    $path = $Event.SourceEventArgs.FullPath
    Convert-To720p -InputPath $path
}

Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action | Out-Null

while ($true) {
    Start-Sleep -Seconds 5
}
