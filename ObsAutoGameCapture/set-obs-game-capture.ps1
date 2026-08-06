# One-shot obs-websocket v5 client: retarget "Game Capture" at a game's
# window, fit it to the canvas, and enable/disable the scene item.
# Invoked per-event by obs-auto-game-capture.ps1 - see README.md.
#
# Uses game_capture (not window_capture) so anti-cheat-protected games get
# properly hooked (anti_cheat_hook) and exclusive-fullscreen games remain
# capturable - window_capture can't see either case reliably.
#
# Usage:
#   set-obs-game-capture.ps1 -Exe <name.exe> [-GamePid <pid>]   retarget + enable
#   set-obs-game-capture.ps1 -Off                                disable + clear
#   set-obs-game-capture.ps1 -List                               debug dump, no changes
#
# Exit codes: 0 ok, 1 OBS unreachable, 2 auth failed, 3 timed out,
# 4 not found (scene/input/window - normal "not ready yet" case), 5 unexpected, 6 no password.

param(
    [string]$Exe,
    [string]$GamePid,
    [switch]$Off,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

$CONFIG = @{
    Url       = 'ws://127.0.0.1:4455'
    SceneName = 'Scene'
    InputName = 'Game Capture'
}
$TimeoutMs = 10000

$sw = [System.Diagnostics.Stopwatch]::StartNew()
function Get-RemainingMs {
    $remaining = $TimeoutMs - $sw.ElapsedMilliseconds
    if ($remaining -lt 0) { return 0 }
    return [int]$remaining
}

# Writes straight to the real console stdout stream, deliberately bypassing
# PowerShell's object pipeline - Write-Output here would get captured into the
# return value of whichever function calls Write-Log (e.g. $exitCode = Invoke-
# ListMode would silently collect every logged line into $exitCode alongside
# the real 0/4 return code). The watcher captures this process's real stdout
# either way, so nothing is lost.
function Write-Log {
    param([string]$Message)
    [Console]::Out.WriteLine($Message)
}

function Get-ObsAuthResponse {
    param([string]$Password, [string]$Salt, [string]$Challenge)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $secretBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Password + $Salt))
    $secret = [Convert]::ToBase64String($secretBytes)
    $authBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($secret + $Challenge))
    return [Convert]::ToBase64String($authBytes)
}

function Send-WsText {
    param($Ws, [string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    $task = $Ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
    if (-not $task.Wait((Get-RemainingMs))) {
        throw [System.TimeoutException]::new('send timed out')
    }
}

# Reads one complete (possibly multi-frame) WebSocket message.
function Receive-WsMessage {
    param($Ws)
    $buffer = New-Object byte[] 8192
    $segment = [System.ArraySegment[byte]]::new($buffer)
    $ms = New-Object System.IO.MemoryStream
    $result = $null
    do {
        $task = $Ws.ReceiveAsync($segment, [System.Threading.CancellationToken]::None)
        if (-not $task.Wait((Get-RemainingMs))) {
            throw [System.TimeoutException]::new('receive timed out')
        }
        $result = $task.Result
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            return [PSCustomObject]@{ IsClose = $true; CloseStatus = [int]$result.CloseStatus; CloseStatusDescription = $result.CloseStatusDescription }
        }
        $ms.Write($buffer, 0, $result.Count)
    } until ($result.EndOfMessage)
    return [PSCustomObject]@{ IsClose = $false; Text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) }
}

# Connects and performs the Identify handshake. Throws a TimeoutException on any
# stalled step, or a PSCustomObject{ConnKind='auth'|'unreachable'; Message} if the
# socket closes before Identified - the caller's catch classifies both into exit codes.
function Connect-Obs {
    param([string]$Password)

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $connectTask = $ws.ConnectAsync([Uri]$CONFIG.Url, [System.Threading.CancellationToken]::None)
    $completed = $false
    try {
        $completed = $connectTask.Wait((Get-RemainingMs))
    } catch {
        throw [PSCustomObject]@{ ConnKind = 'unreachable'; Message = "connect failed: $($_.Exception.GetBaseException().Message)" }
    }
    if (-not $completed) {
        throw [System.TimeoutException]::new('connect timed out')
    }

    $helloMsg = Receive-WsMessage -Ws $ws
    if ($helloMsg.IsClose) {
        throw [PSCustomObject]@{ ConnKind = 'unreachable'; Message = "closed before Hello (code $($helloMsg.CloseStatus))" }
    }
    $hello = $helloMsg.Text | ConvertFrom-Json

    # eventSubscriptions: 0 - a one-shot has no interest in the event stream.
    $identify = @{ rpcVersion = $hello.d.rpcVersion; eventSubscriptions = 0 }
    if ($hello.d.authentication) {
        $identify.authentication = Get-ObsAuthResponse -Password $Password -Salt $hello.d.authentication.salt -Challenge $hello.d.authentication.challenge
    }
    Send-WsText -Ws $ws -Text (@{ op = 1; d = $identify } | ConvertTo-Json -Depth 10 -Compress)

    $identifiedMsg = Receive-WsMessage -Ws $ws
    if ($identifiedMsg.IsClose) {
        $kind = if ($identifiedMsg.CloseStatus -eq 4009) { 'auth' } else { 'unreachable' }
        throw [PSCustomObject]@{ ConnKind = $kind; Message = $identifiedMsg.CloseStatusDescription }
    }

    return $ws
}

$script:RequestCounter = 0

# Sends a request and blocks until its matching response arrives (there's never
# more than one request in flight, so no need to track multiple pending replies).
# Throws a PSCustomObject{Code; Comment; RequestType} on an OBS-side failure.
function Invoke-ObsRequest {
    param($Ws, [string]$RequestType, [hashtable]$RequestData = @{})

    $script:RequestCounter++
    $requestId = [string]$script:RequestCounter
    $payload = @{ op = 6; d = @{ requestType = $RequestType; requestId = $requestId; requestData = $RequestData } } | ConvertTo-Json -Depth 10 -Compress
    Send-WsText -Ws $Ws -Text $payload

    while ($true) {
        $msg = Receive-WsMessage -Ws $Ws
        if ($msg.IsClose) {
            throw [PSCustomObject]@{ ConnKind = 'unreachable'; Message = "connection closed while waiting for $RequestType response (code $($msg.CloseStatus))" }
        }
        $parsed = $msg.Text | ConvertFrom-Json
        if ($parsed.op -eq 7 -and $parsed.d.requestId -eq $requestId) {
            if ($parsed.d.requestStatus.result) {
                return $parsed.d.responseData
            }
            throw [PSCustomObject]@{ Code = $parsed.d.requestStatus.code; Comment = $parsed.d.requestStatus.comment; RequestType = $RequestType }
        }
        # else: not our response (e.g. a stray event) - keep waiting
    }
}

# Resolves CONFIG.SceneName/InputName against what's actually in OBS, falling back
# to the unique game_capture input by kind if the configured name is stale.
# Returns $null (after logging a diagnostic dump) if resolution fails.
function Resolve-Targets {
    param($Ws)

    $sceneList = Invoke-ObsRequest -Ws $Ws -RequestType 'GetSceneList'
    $scenes = @($sceneList.scenes | ForEach-Object { $_.sceneName })
    if ($scenes -notcontains $CONFIG.SceneName) {
        Write-Log "ERROR scene `"$($CONFIG.SceneName)`" not found. Available scenes: $($scenes -join ', ')"
        return $null
    }

    $inputList = Invoke-ObsRequest -Ws $Ws -RequestType 'GetInputList'
    $inputName = $CONFIG.InputName
    $names = @($inputList.inputs | ForEach-Object { $_.inputName })
    if ($names -notcontains $inputName) {
        $gcInputs = @($inputList.inputs | Where-Object { $_.inputKind -eq 'game_capture' })
        if ($gcInputs.Count -eq 1) {
            $inputName = $gcInputs[0].inputName
            Write-Log "WARN input `"$($CONFIG.InputName)`" not found, falling back to unique game_capture input `"$inputName`""
        } else {
            $desc = ($inputList.inputs | ForEach-Object { "$($_.inputName) ($($_.inputKind))" }) -join ', '
            Write-Log "ERROR input `"$($CONFIG.InputName)`" not found and $($gcInputs.Count) game_capture inputs exist. Available inputs: $desc"
            return $null
        }
    }

    return @{ SceneName = $CONFIG.SceneName; InputName = $inputName }
}

# itemValue is "Title:Class:exe" with colons inside title/class escaped by OBS,
# so the exe name is always safely recoverable as the last ':'-segment.
function Find-WindowMatch {
    param($Items, [string]$ExeName)

    $wanted = $ExeName.ToLowerInvariant()
    $matches = @($Items | Where-Object {
        $parts = $_.itemValue -split ':'
        $parts[-1].ToLowerInvariant() -eq $wanted
    })
    $enabled = $matches | Where-Object { $_.itemEnabled } | Select-Object -First 1
    if ($enabled) { return $enabled }
    return $matches | Select-Object -First 1
}

function Invoke-Launch {
    param($Ws, [string]$ExeName)

    $targets = Resolve-Targets -Ws $Ws
    if (-not $targets) { return 4 }

    $props = Invoke-ObsRequest -Ws $Ws -RequestType 'GetInputPropertiesListPropertyItems' -RequestData @{ inputName = $targets.InputName; propertyName = 'window' }
    $match = Find-WindowMatch -Items $props.propertyItems -ExeName $ExeName
    if (-not $match) {
        Write-Log "NOTFOUND no OBS-visible window for exe `"$ExeName`" yet"
        return 4
    }

    # capture_mode: 'window' targets a specific window rather than "any fullscreen
    # app" or the hotkey-driven mode. priority: 2 = "match title, otherwise find
    # window of same executable" (window classes are shared across unrelated apps,
    # a real mistargeting risk if left on the title-then-class fallback).
    # anti_cheat_hook enables OBS to hook anti-cheat-protected games (EAC,
    # BattlEye, VAC) - the main reason to use game_capture over window_capture.
    # All three already match game_capture's OBS defaults; set explicitly anyway
    # so this call self-heals the source if someone changes it in the OBS UI.
    Invoke-ObsRequest -Ws $Ws -RequestType 'SetInputSettings' -RequestData @{
        inputName     = $targets.InputName
        inputSettings = @{ capture_mode = 'window'; window = $match.itemValue; priority = 2; anti_cheat_hook = $true }
        overlay       = $true
    } | Out-Null

    $video = Invoke-ObsRequest -Ws $Ws -RequestType 'GetVideoSettings'
    $sceneItemId = (Invoke-ObsRequest -Ws $Ws -RequestType 'GetSceneItemId' -RequestData @{ sceneName = $targets.SceneName; sourceName = $targets.InputName }).sceneItemId

    # OBS_BOUNDS_SCALE_INNER rescales the source into these bounds every frame,
    # regardless of source size - resolution-independent, no race to guard against.
    Invoke-ObsRequest -Ws $Ws -RequestType 'SetSceneItemTransform' -RequestData @{
        sceneName          = $targets.SceneName
        sceneItemId        = $sceneItemId
        sceneItemTransform = @{
            boundsType      = 'OBS_BOUNDS_SCALE_INNER'
            boundsAlignment = 0
            boundsWidth     = $video.baseWidth
            boundsHeight    = $video.baseHeight
            alignment       = 0
            positionX       = $video.baseWidth / 2
            positionY       = $video.baseHeight / 2
            scaleX          = 1
            scaleY          = 1
            rotation        = 0
        }
    } | Out-Null

    # Enable last, so the previous game's dead window never flashes on screen.
    Invoke-ObsRequest -Ws $Ws -RequestType 'SetSceneItemEnabled' -RequestData @{
        sceneName        = $targets.SceneName
        sceneItemId      = $sceneItemId
        sceneItemEnabled = $true
    } | Out-Null

    Write-Log "OK captured `"$($match.itemValue)`" for exe `"$ExeName`""
    return 0
}

function Invoke-Off {
    param($Ws)

    $targets = Resolve-Targets -Ws $Ws
    if (-not $targets) { return 4 }

    $sceneItemId = (Invoke-ObsRequest -Ws $Ws -RequestType 'GetSceneItemId' -RequestData @{ sceneName = $targets.SceneName; sourceName = $targets.InputName }).sceneItemId

    Invoke-ObsRequest -Ws $Ws -RequestType 'SetSceneItemEnabled' -RequestData @{
        sceneName        = $targets.SceneName
        sceneItemId      = $sceneItemId
        sceneItemEnabled = $false
    } | Out-Null

    # Clear the target window too, not just hide it - otherwise the source keeps
    # pointing at the exited game's (now-dead) window until the next launch.
    Invoke-ObsRequest -Ws $Ws -RequestType 'SetInputSettings' -RequestData @{
        inputName     = $targets.InputName
        inputSettings = @{ window = '' }
        overlay       = $true
    } | Out-Null

    Write-Log "OK disabled and cleared $($targets.InputName)"
    return 0
}

function Invoke-ListMode {
    param($Ws)

    $sceneList = Invoke-ObsRequest -Ws $Ws -RequestType 'GetSceneList'
    Write-Log "Scenes: $(($sceneList.scenes | ForEach-Object { $_.sceneName }) -join ', ')"

    $inputList = Invoke-ObsRequest -Ws $Ws -RequestType 'GetInputList'
    foreach ($i in $inputList.inputs) {
        Write-Log "Input: $($i.inputName) ($($i.inputKind))"
    }

    $targets = Resolve-Targets -Ws $Ws
    if (-not $targets) { return 4 }

    $props = Invoke-ObsRequest -Ws $Ws -RequestType 'GetInputPropertiesListPropertyItems' -RequestData @{ inputName = $targets.InputName; propertyName = 'window' }
    foreach ($it in $props.propertyItems) {
        Write-Log "Window: enabled=$($it.itemEnabled) value=`"$($it.itemValue)`" name=`"$($it.itemName)`""
    }

    return 0
}

$mode = if ($List) { 'list' } elseif ($Off) { 'off' } elseif ($Exe) { 'launch' } else { $null }
if (-not $mode) {
    Write-Log 'Usage: set-obs-game-capture.ps1 (-Exe <name.exe> [-GamePid <pid>] | -Off | -List)'
    exit 5
}

$password = $env:OBS_WS_SERVER_PASSWORD
if (-not $password) {
    Write-Log 'ERROR OBS_WS_SERVER_PASSWORD is not set'
    exit 6
}

$exitCode = 5
$ws = $null
try {
    $ws = Connect-Obs -Password $password
    switch ($mode) {
        'launch' { $exitCode = Invoke-Launch -Ws $ws -ExeName $Exe }
        'off' { $exitCode = Invoke-Off -Ws $ws }
        'list' { $exitCode = Invoke-ListMode -Ws $ws }
    }
} catch [System.TimeoutException] {
    Write-Log "ERROR timed out talking to OBS: $($_.Exception.Message)"
    $exitCode = 3
} catch {
    $obj = $_.TargetObject
    if ($obj -and $obj.ConnKind) {
        if ($obj.ConnKind -eq 'auth') {
            Write-Log "ERROR auth failed: $($obj.Message)"
            $exitCode = 2
        } else {
            Write-Log "ERROR could not reach OBS: $($obj.Message)"
            $exitCode = 1
        }
    } elseif ($obj -and ($null -ne $obj.Code)) {
        Write-Log "ERROR $($obj.RequestType) failed: [$($obj.Code)] $($obj.Comment)"
        $exitCode = if ($obj.Code -eq 600) { 4 } else { 5 }
    } else {
        Write-Log "ERROR unexpected: $($_.Exception.Message)"
        $exitCode = 5
    }
} finally {
    if ($ws) {
        try { $ws.Dispose() } catch { }
    }
}

exit $exitCode
