# Autonomous RX18 playback capture. Requires local GRP Chrome CDP at localhost:9222.
# Never accepts arbitrary commands, remote hosts, or non-owned song URLs.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RecorderExe,
    [Parameter(Mandatory=$true)][string]$LogsDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$songId = '133f9e23-e0f3-4acf-b95b-934c37cb125c'
$songUrl = 'https://suno.com/song/' + $songId
$cdpBase = 'http://127.0.0.1:9222'

function Send-CDPCommand([System.Net.WebSockets.ClientWebSocket]$socket, [int]$id, [string]$method, [hashtable]$parameters) {
    $payload = @{id=$id;method=$method;params=$parameters} | ConvertTo-Json -Depth 12 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $segment = [ArraySegment[byte]]::new($bytes)
    $socket.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $buffer = New-Object byte[] 65536
    while ($true) {
        $stream = New-Object IO.MemoryStream
        do {
            $part = [ArraySegment[byte]]::new($buffer)
            $cts = New-Object Threading.CancellationTokenSource(12000)
            try { $response = $socket.ReceiveAsync($part, $cts.Token).GetAwaiter().GetResult() }
            finally { $cts.Dispose() }
            if ($response.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'CDP_SOCKET_CLOSED' }
            $stream.Write($buffer, 0, $response.Count)
            if ($stream.Length -gt 1048576) { throw 'CDP_MESSAGE_TOO_LARGE' }
        } while (-not $response.EndOfMessage)
        $reply = [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
        if ($reply.id -eq $id) {
            if ($reply.error) { throw ('CDP_ERROR '+$method+': '+$reply.error.message) }
            return $reply.result
        }
    }
}
function Get-SongTab {
    $response = @(Invoke-RestMethod -Uri ($cdpBase + '/json/list') -TimeoutSec 8 -ErrorAction Stop)
    $tabs = @($response | Where-Object {
        $_.type -eq 'page' -and $_.url -match ('^https://suno[.]com/song/' + [Regex]::Escape($songId) + '([?]|$)') -and
        $_.webSocketDebuggerUrl -match '^ws://(127[.]0[.]0[.]1|localhost):9222/devtools/page/'
    })
    if ($tabs.Count -eq 0) { return $null }
    return $tabs[0]
}
function Invoke-CDPOnSong([string]$expression, [string]$action = 'evaluate') {
    $tab = Get-SongTab
    if (-not $tab) { throw 'CDP_SUNO_TAB_NOT_FOUND' }
    $socket = New-Object Net.WebSockets.ClientWebSocket
    try {
        $cts = New-Object Threading.CancellationTokenSource(12000)
        try { $socket.ConnectAsync([Uri]$tab.webSocketDebuggerUrl, $cts.Token).GetAwaiter().GetResult() }
        finally { $cts.Dispose() }
        $result = Send-CDPCommand $socket 1 'Runtime.evaluate' @{expression=$expression;returnByValue=$true;awaitPromise=$false}
        $value = $result.result.value
        if ($action -eq 'inspect') { return $value }
        if (-not $value -or -not $value.ok) { throw ('SUNO_PLAY_CONTROL_NOT_FOUND: '+$value.reason) }
        if ($value.x -lt 0 -or $value.y -lt 0 -or $value.x -gt 10000 -or $value.y -gt 10000) { throw 'BAD_PLAY_GEOMETRY' }
        $null = Send-CDPCommand $socket 2 'Input.dispatchMouseEvent' @{type='mouseMoved';x=[int]$value.x;y=[int]$value.y}
        $null = Send-CDPCommand $socket 3 'Input.dispatchMouseEvent' @{type='mousePressed';x=[int]$value.x;y=[int]$value.y;button='left';clickCount=1}
        $null = Send-CDPCommand $socket 4 'Input.dispatchMouseEvent' @{type='mouseReleased';x=[int]$value.x;y=[int]$value.y;button='left';clickCount=1}
        return $value
    } finally { try { $socket.Dispose() } catch {} }
}
$findPlay = @'
(() => {
 const btns=[...document.querySelectorAll('button,[role="button"]')];
 const nameOf=x=>(x.getAttribute('aria-label')||x.getAttribute('title')||x.textContent||'').trim();
 const play=btns.find(b=>/^(play|riproduci)$/i.test(nameOf(b))&&b.getBoundingClientRect().width>8&&b.getBoundingClientRect().height>8);
 if(!play)return {ok:false,reason:'NO_PLAY_CONTROL'};
 play.scrollIntoView({block:'center'});
 const rect=play.getBoundingClientRect();
 return {ok:true,x:Math.round(rect.left+rect.width/2),y:Math.round(rect.top+rect.height/2),label:nameOf(play)};
})()
'@
$readPlayback = @'
(() => {
 const m=[...document.querySelectorAll('audio,video')];
 const times=m.map(a=>Math.round(a.currentTime*10)/10);
 return {playing:m.some(a=>!a.paused && a.currentTime>0.2),times,
   pauseControl:[...document.querySelectorAll('button')].some(b=>/^(pause|pausa)$/i.test((b.getAttribute('aria-label')||b.getAttribute('title')||'').trim()))};
})()
'@

if (-not (Test-Path -LiteralPath $RecorderExe -PathType Leaf)) { throw 'RECORDER_EXE_MISSING' }
if (-not (Test-Path -LiteralPath $LogsDirectory -PathType Container)) { throw 'LOG_DIRECTORY_MISSING' }
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdoutPath=Join-Path $LogsDirectory ('cdp-stdout-'+$runId+'.log')
$stderrPath=Join-Path $LogsDirectory ('cdp-stderr-'+$runId+'.log')
# Pre-open the exact song while not recording, avoiding loading delays and wrong tabs.
Start-Process $songUrl
$tabDeadline=(Get-Date).AddSeconds(35)
$tabReady=$false
while ((Get-Date) -lt $tabDeadline) {
    try {
        $info=Invoke-CDPOnSong $findPlay 'inspect'
        if ($info -and $info.ok) { $tabReady=$true;break }
    } catch { Write-Host ('CDP_PREPARE_RETRY: '+$_.Exception.Message) }
    Start-Sleep -Seconds 2
}
if (-not $tabReady) { throw 'CDP_SUNO_PAGE_NOT_READY; recording not started' }
Write-Host 'CDP_SUNO_TAB_READY'
$start=Get-Date
$audioName='Capagross_Take2_C1_'+$runId
$arguments='capture --seconds 370 --start-delay 0 --root "'+$OutputDirectory+'" --name '+$audioName+' --record-own-audio'
$proc=Start-Process -FilePath $RecorderExe -ArgumentList $arguments -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
Write-Host ('AUTOMATION_CAPTURE_CHILD_STARTED pid='+$proc.Id)
try {
    $captureReady=$false
    $deadline=(Get-Date).AddSeconds(75)
    while ((Get-Date) -lt $deadline) {
        $proc.Refresh()
        if ($proc.HasExited) { throw ('WASAPI_CHILD_EXIT_EARLY: '+$proc.ExitCode) }
        $partials=@(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.wav.partial' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $start.AddSeconds(-3) -and $_.Length -gt 8192 })
        if ($partials.Count -gt 0) {$captureReady=$true;break}
        Start-Sleep -Milliseconds 500
    }
    if (-not $captureReady) { throw 'WASAPI_NOT_ACTIVE_AFTER_75_SECONDS' }
    Write-Host ('WASAPI_CAPTURE_READY: '+$partials[0].Name)
    # Child opens an extra song tab. Choose the preloaded original by Get-SongTab ordering.
    $play=Invoke-CDPOnSong $findPlay
    Write-Host ('CDP_TRUSTED_PLAY_CLICK: '+($play|ConvertTo-Json -Compress))
    Start-Sleep -Seconds 4
    $playback=Invoke-CDPOnSong $readPlayback 'inspect'
    Write-Host ('CDP_AUDIO_STATE: '+($playback|ConvertTo-Json -Compress))
    if (-not ($playback.playing -or $playback.pauseControl)) { throw 'PLAYBACK_NOT_CONFIRMED' }
    if (-not $proc.WaitForExit(430000)) { throw 'AUDIO_CAPTURE_TIMEOUT' }
    $mp3=Join-Path $OutputDirectory ($audioName+'.mp3')
    $manifestPath=Join-Path $OutputDirectory ($audioName+'.json')
    if (-not (Test-Path -LiteralPath $mp3 -PathType Leaf)) { throw ('MP3_NOT_GENERATED: process exit='+$proc.ExitCode) }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'MP3_MANIFEST_NOT_GENERATED' }
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $actualHash=(Get-FileHash -LiteralPath $mp3 -Algorithm SHA256).Hash
    if (-not $manifest.ok -or $manifest.duration_seconds -lt 350 -or $manifest.duration_seconds -gt 385 -or
        $manifest.rms -lt 0.003 -or $manifest.bytes -lt 1000000 -or $actualHash -ne $manifest.sha256) {
        throw 'MP3_VALIDATION_FAILED'
    }
    if ($null -ne $proc.ExitCode -and $proc.ExitCode -ne 0) { throw ('AUDIO_CAPTURE_EXIT_'+$proc.ExitCode) }
    Write-Host ('CAPAGROSS_MP3_CREATED: '+$mp3)
    Write-Host ('CAPAGROSS_MP3_SHA256: '+$actualHash)
} finally {
    $proc.Refresh()
    if (-not $proc.HasExited) { try { $proc.Kill() } catch {} }
    if (Test-Path -LiteralPath $stdoutPath) {
        Write-Host '=== CAPTURE STDOUT ==='
        Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue | ForEach-Object {Write-Host $_}
    }
    if (Test-Path -LiteralPath $stderrPath) {
        Write-Host '=== CAPTURE STDERR ==='
        Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue | ForEach-Object {Write-Host $_}
    }
    $proc.Dispose()
}