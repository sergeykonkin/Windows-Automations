# Polls for Steam games starting/exiting and drives set-obs-game-capture.ps1
# to retarget OBS's "Game Capture" source accordingly. See README.md.
#
# Polling instead of Win32_ProcessStartTrace (WMI) deliberately: that class
# requires admin rights, which conflicts with this task running at
# -RunLevel Limited.

$ErrorActionPreference = 'Stop'

$ConnectorPath = Join-Path $PSScriptRoot 'set-obs-game-capture.ps1'
$LogPath = Join-Path $PSScriptRoot 'obs-auto-game-capture.log'
$PollIntervalSeconds = 3

$GameRoots = @(
    'D:\Games\Steam\steamapps\common\'
)

# Windows that live under a matched root but aren't games.
$PathDenyContains = @('\_CommonRedist\', '\Steamworks Shared\', '\SteamVR\', '\redist\')
$ExeDenylist = @(
    'UnityCrashHandler64.exe', 'UnityCrashHandler32.exe', 'crashpad_handler.exe',
    'steamerrorreporter.exe', 'steamerrorreporter64.exe', 'EasyAntiCheat_Setup.exe'
)

$StickyFatal = $false

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -LiteralPath $LogPath -Value $line
}

# Guards against duplicate instances. This matters because this watcher is
# launched via _shared\run-silent.vbs's `shell.Run cmd, 0, False`, which detaches
# the real long-running powershell.exe from the wscript.exe process Task
# Scheduler tracks - so Stop-ScheduledTask (and -MultipleInstances IgnoreNew,
# which keys off that same tracked process) can't actually prevent or stop a
# second instance. Without this, every restart piles on another instance
# fighting over the same OBS scene item, which looks like constant flicker.
$createdNewMutex = $false
$instanceMutex = New-Object System.Threading.Mutex($true, 'Local\ObsAutoGameCaptureWatcher', [ref]$createdNewMutex)
if (-not $createdNewMutex) {
    Write-Log 'EXIT another instance already holds the mutex - not starting a duplicate'
    exit
}

function Initialize-Log {
    if (Test-Path -LiteralPath $LogPath) {
        $len = (Get-Item -LiteralPath $LogPath).Length
        if ($len -gt 1MB) {
            Move-Item -LiteralPath $LogPath -Destination "$LogPath.1" -Force
        }
    }
}

# Runs the connector, logs its output, and sets a sticky fatal flag on
# auth-failed (2) / missing-password (6) so a misconfiguration doesn't spam
# retries into the log forever - it only clears on watcher restart.
#
# Deliberately not merging stderr (2>&1) here: with $ErrorActionPreference =
# 'Stop' (set script-wide), each merged stderr line from a native exe becomes
# a terminating NativeCommandError. The connector writes its log lines to the
# real console stdout stream (see its own Write-Log), so plain stdout capture
# is sufficient and avoids that trap.
function Invoke-Connector {
    param([Parameter(Mandatory)][string[]]$ConnectorArgs)

    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ConnectorPath @ConnectorArgs
    $code = $LASTEXITCODE
    foreach ($line in $out) {
        Write-Log "[obs] $line"
    }
    Write-Log "[obs] exit=$code args=$($ConnectorArgs -join ' ')"

    if (($code -eq 2 -or $code -eq 6) -and -not $script:StickyFatal) {
        $script:StickyFatal = $true
        Write-Log "FATAL sticky flag set (connector exit $code) - suppressing further connector calls until watcher restart"
    }
    return $code
}

function Get-MatchingProcesses {
    $result = @()
    foreach ($p in (Get-Process)) {
        $path = $null
        try { $path = $p.Path } catch { continue }
        if (-not $path) { continue }

        $inRoot = $false
        foreach ($root in $GameRoots) {
            if ($path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                $inRoot = $true
                break
            }
        }
        if (-not $inRoot) { continue }

        $denied = $false
        foreach ($d in $PathDenyContains) {
            if ($path -like "*$d*") { $denied = $true; break }
        }
        if ($denied) { continue }

        $exeName = [System.IO.Path]::GetFileName($path)
        if ($ExeDenylist -contains $exeName) { continue }

        $startTime = Get-Date
        try { $startTime = $p.StartTime } catch { }

        $result += [PSCustomObject]@{
            Pid       = $p.Id
            Exe       = $exeName
            StartTime = $startTime
            HasWindow = ($p.MainWindowHandle -ne [IntPtr]::Zero)
        }
    }
    return $result
}

Initialize-Log
Write-Log '=== watcher starting ==='
Write-Log "roots: $($GameRoots -join '; ')"
Write-Log "poll interval: ${PollIntervalSeconds}s"
Write-Log "OBS_WS_SERVER_PASSWORD: $(if ($env:OBS_WS_SERVER_PASSWORD) { 'present' } else { 'MISSING' })"

# pid -> { Pid, Exe, FirstSeen, SortTime, Attempts, LastAttempt, Captured }
$tracked = @{}
$currentTarget = $null

while ($true) {
    try {
        $matched = Get-MatchingProcesses
        $liveIds = @($matched | ForEach-Object { $_.Pid })

        foreach ($p in $matched) {
            if (-not $tracked.ContainsKey($p.Pid)) {
                $tracked[$p.Pid] = [PSCustomObject]@{
                    Pid         = $p.Pid
                    Exe         = $p.Exe
                    FirstSeen   = Get-Date
                    SortTime    = $p.StartTime
                    Attempts    = 0
                    LastAttempt = [DateTime]::MinValue
                    Captured    = $false
                }
                Write-Log "TRACK new process pid=$($p.Pid) exe=$($p.Exe)"
            }
        }

        # Drop processes that exited. If the current OBS target just exited,
        # retarget to whichever tracked process is newest, or disable capture
        # if none are left ("newest wins" policy).
        $deadPids = @($tracked.Keys | Where-Object { $liveIds -notcontains $_ })
        foreach ($deadPid in $deadPids) {
            $wasCurrent = ($currentTarget -eq $deadPid)
            $deadExe = $tracked[$deadPid].Exe
            $tracked.Remove($deadPid)
            Write-Log "UNTRACK exited pid=$deadPid exe=$deadExe"
            if (-not $wasCurrent) { continue }

            $currentTarget = $null
            if ($StickyFatal) { continue }

            $remaining = @($tracked.Values | Sort-Object SortTime -Descending)
            if ($remaining.Count -gt 0) {
                $target = $remaining[0]
                $code = Invoke-Connector -ConnectorArgs @('-Exe', $target.Exe, '-GamePid', $target.Pid)
                $target.Attempts++
                $target.LastAttempt = Get-Date
                if ($code -eq 0) {
                    $target.Captured = $true
                    $currentTarget = $target.Pid
                }
            } else {
                Invoke-Connector -ConnectorArgs @('-Off') | Out-Null
            }
        }

        # Try to capture any not-yet-captured tracked process, oldest first,
        # so that if several become eligible in the same tick, the newest
        # ends up as the final OBS target.
        $pending = @($tracked.Values | Where-Object { -not $_.Captured } | Sort-Object SortTime)
        foreach ($entry in $pending) {
            if ($StickyFatal) { break }
            if ($entry.Attempts -ge 10) { continue }
            if ($entry.LastAttempt -ne [DateTime]::MinValue -and ((Get-Date) - $entry.LastAttempt).TotalSeconds -lt 10) { continue }

            $current = $matched | Where-Object { $_.Pid -eq $entry.Pid } | Select-Object -First 1
            if (-not $current) { continue }

            $age = ((Get-Date) - $entry.FirstSeen).TotalSeconds
            if (-not ($current.HasWindow -or $age -gt 20)) { continue }
            if (-not (Get-Process -Name 'obs64' -ErrorAction SilentlyContinue)) { continue }

            $code = Invoke-Connector -ConnectorArgs @('-Exe', $entry.Exe, '-GamePid', $entry.Pid)
            $entry.Attempts++
            $entry.LastAttempt = Get-Date
            if ($code -eq 0) {
                $entry.Captured = $true
                $currentTarget = $entry.Pid
            }
        }
    } catch {
        Write-Log "ERROR tick failed: $_"
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}
