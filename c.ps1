# Small public bootstrap; the authoritative capture script remains in private Google Drive.
# Drive export is SHA256-pinned. No secrets, admin, Codex or third-party downloader.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$docId = '1vamb69WAMoWMxxnowgs5sy5nllbDJ_z33Z2cFiufXOM'
$expected = '4B2FAD34EB9CD4916E040774EB34E0F18392BBC7A1759B8E4E8B21FFE5E9BD35'
$docDownload = "https://docs.google.com/document/d/$docId/export?format=txt"
$root = Join-Path $env:LOCALAPPDATA 'CapagrossRX18'
$logs = Join-Path $root 'logs'
$script = Join-Path $root 'Capagross-RX18-ONE-SHOT.ps1'
$part = Join-Path $root 'Drive-script-download.txt'
$downloads = Join-Path $env:USERPROFILE 'Downloads'
New-Item -ItemType Directory -Path $root,$logs -Force | Out-Null
$log = Join-Path $logs ("bootstrap-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$bundleHash = '9589A3A31885DD7441E8D99D3496078D3B4658CCBBF86D7784FA7D107F848300'
$bundleDest = Join-Path $root 'CapagrossRX18-Pronto.zip'

function Test-VerifiedFile([string] $path, [string] $hash, [long] $min, [long] $max) {
    try {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Length -lt $min -or $item.Length -gt $max) { return $false }
        return ((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -eq $hash)
    } catch { return $false }
}
function Get-SyncRoots {
    # Known Drive Desktop (virtual or mirrored) and Dropbox locations; no unbounded disk scans.
    $userProfileDir = $env:USERPROFILE
    $roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($path in @(
        (Join-Path $userProfileDir 'Dropbox'),
        (Join-Path $userProfileDir 'Google Drive'),
        (Join-Path $userProfileDir 'My Drive'),
        (Join-Path $userProfileDir 'Il mio Drive'),
        (Join-Path $userProfileDir 'Downloads'),
        (Join-Path $userProfileDir 'Music')
    )) { $roots.Add($path) }
    foreach ($info in @((Join-Path $env:LOCALAPPDATA 'Dropbox\info.json'), (Join-Path $env:APPDATA 'Dropbox\info.json'))) {
        if (Test-Path -LiteralPath $info -PathType Leaf) {
            try {
                $db = Get-Content -LiteralPath $info -Raw | ConvertFrom-Json
                foreach ($kind in @('personal', 'business')) {
                    $entry = $db.PSObject.Properties[$kind]
                    if ($entry -and $entry.Value.path) { $roots.Add([string]$entry.Value.path) }
                }
            } catch { Write-Warning 'Dropbox info.json non leggibile; continuo.' }
        }
    }
    foreach ($disk in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($disk.Root) { $roots.Add([string]$disk.Root) }
    }
    $subdirs = @('', 'MUSICA - Production', 'Musica', 'musica', 'sharedrx18',
        'My Drive', 'Il mio Drive', 'My Drive\MUSICA - Production',
        'Il mio Drive\MUSICA - Production', 'Dropbox', 'Dropbox\sharedrx18')
    $seen = @{}
    foreach ($rootPath in $roots) {
        foreach ($sub in $subdirs) {
            $folder = if ($sub) { Join-Path $rootPath $sub } else { $rootPath }
            if (-not $folder -or $seen.ContainsKey($folder)) { continue }
            $seen[$folder] = $true
            # Google Drive virtual and offline Dropbox roots can raise IOException even during Test-Path.
            # A missing/unreachable sync folder is optional: continue to the next candidate.
            try {
                if (Test-Path -LiteralPath $folder -PathType Container -ErrorAction Stop) {
                    Write-Output $folder
                }
            } catch [System.IO.IOException] {
                Write-Warning ('Cartella sincronizzata non accessibile, salto: ' + $folder)
                continue
            } catch {
                Write-Warning ('Percorso sincronizzato non disponibile, salto: ' + $folder)
                continue
            }
        }
    }
}
function Stage-SyncedFiles([string[]]$dirs) {
    if (-not (Test-VerifiedFile $script $expected 8000 15000)) {
        foreach ($dir in $dirs) {
            foreach ($name in @('Capagross-RX18-ONE-SHOT.ps1', 'Capagross-RX18-ONE-SHOT.ps1.txt', 'Capagross RX18 - sorgente OneShot locale v3.txt')) {
                $candidate = Join-Path $dir $name
                if (Test-VerifiedFile $candidate $expected 8000 15000) {
                    Copy-Item -LiteralPath $candidate -Destination $script -Force
                    Write-Host ("Script sincronizzato verificato: " + $candidate) -ForegroundColor Green
                    break
                }
            }
            if (Test-VerifiedFile $script $expected 8000 15000) { break }
        }
    }
    if (-not (Test-VerifiedFile $bundleDest $bundleHash 45000000 50000000)) {
        foreach ($dir in $dirs) {
            foreach ($name in @('CapagrossRX18-Pronto-20261110.zip',
                                'CapagrossRX18-Pronto.zip',
                                'CapagrossRX18-Portatile-20261110.zip')) {
                $candidate = Join-Path $dir $name
                if (Test-VerifiedFile $candidate $bundleHash 45000000 50000000) {
                    Copy-Item -LiteralPath $candidate -Destination $bundleDest -Force
                    Write-Host ("ZIP sincronizzato verificato: " + $candidate) -ForegroundColor Green
                    break
                }
            }
            if (Test-VerifiedFile $bundleDest $bundleHash 45000000 50000000) { break }
        }
    }
}

# Keep a local full log and publish it after transcript closes.
$runStartedAt = Get-Date
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID
$fullLog = Join-Path $logs ("Capagross-RX18-FULL-" + $runId + ".log")
$statusFile = Join-Path $logs ("Capagross-RX18-STATUS-" + $runId + ".json")
$phase = 'bootstrap'
$resultCode = 1
$errorDetail = $null
$syncTargets = @()
$transcript = $false

function Get-SyncedLogDirectories([string[]]$availableDirs) {
    # Personal Drive first; private Dropbox root as fallback. No sharedrx18.
    $drive = @($availableDirs | Where-Object {
        ($_ -match '(^|[\\/])(MUSICA - Production)$') -and
        ($_ -match '(^|[\\/])(My Drive|Il mio Drive|Google Drive)([\\/]|$)')
    } | Select-Object -Unique)
    $dropbox = @($availableDirs | Where-Object {
        ($_ -match '(^|[\\/])Dropbox$')
    } | Select-Object -Unique)
    foreach ($infoFile in @((Join-Path $env:LOCALAPPDATA 'Dropbox\info.json'), (Join-Path $env:APPDATA 'Dropbox\info.json'))) {
        try {
            if (Test-Path -LiteralPath $infoFile -PathType Leaf -ErrorAction Stop) {
                $cfg = Get-Content -LiteralPath $infoFile -Raw -ErrorAction Stop | ConvertFrom-Json
                foreach ($kind in @('personal', 'business')) {
                    $property = $cfg.PSObject.Properties[$kind]
                    if ($property -and $property.Value.path) {
                        $candidate = [string]$property.Value.path
                        if ($availableDirs -contains $candidate) { $dropbox += $candidate }
                    }
                }
            }
        } catch {
            Write-Warning ('Dropbox sync root unavailable: ' + $_.Exception.Message)
        }
    }
    foreach ($base in @($drive) + @($dropbox | Select-Object -Unique)) {
        try {
            $candidate = Join-Path $base 'Capagross-RX18-Logs'
            if (-not (Test-Path -LiteralPath $candidate -PathType Container -ErrorAction Stop)) {
                New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
            }
            $probe = Join-Path $candidate ("write-test-" + $PID + ".tmp")
            [System.IO.File]::WriteAllText($probe, 'test')
            Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
            Write-Output $candidate
        } catch {
            Write-Warning ('Cartella sync non scrivibile: ' + $base + ' -- ' + $_.Exception.Message)
        }
    }
}
function Publish-RunLogs([string]$sourceLog,[string]$sourceStatus,[string[]]$targets) {
    $published = @()
    foreach ($target in $targets) {
        try {
            $logDest = Join-Path $target 'Capagross-RX18-LATEST.log'
            $statusDest = Join-Path $target 'Capagross-RX18-LATEST.json'
            Copy-Item -LiteralPath $sourceLog -Destination $logDest -Force -ErrorAction Stop
            Copy-Item -LiteralPath $sourceStatus -Destination $statusDest -Force -ErrorAction Stop
            Copy-Item -LiteralPath $sourceLog -Destination (Join-Path $target ([IO.Path]::GetFileName($sourceLog))) -Force -ErrorAction Stop
            Write-Host ('LOG_SYNC_OK: ' + $logDest) -ForegroundColor Green
            $published += $logDest
        } catch {
            Write-Warning ('LOG_SYNC_FAILED: ' + $target + ' -- ' + $_.Exception.Message)
        }
    }
    return @($published)
}
try {
    Start-Transcript -Path $log -Force | Out-Null
    $transcript = $true
    Write-Host ("BOOTSTRAP RX18 - log: " + $log) -ForegroundColor Cyan
    $phase = 'local_sync_discovery'
    $syncDirs = @(Get-SyncRoots)
    Write-Host ("Cartelle Drive/Dropbox rilevate: " + $syncDirs.Count) -ForegroundColor Cyan
    $syncTargets = @(Get-SyncedLogDirectories $syncDirs)
    Write-Host ("Destinazioni log sincronizzate: " + $syncTargets.Count) -ForegroundColor Cyan
    if ($syncTargets.Count -eq 0) {
        Write-Warning 'Nessuna cartella Drive/Dropbox scrivibile: log conservato in AppData.'
    }
    $phase = 'stage_audio'
    Stage-SyncedFiles $syncDirs
    # The private Drive script is no longer needed: invoke the bundled recorder EXE directly.
    # Prefer a verified ZIP staged from local Drive/Dropbox/Downloads.
    $phase = 'verify_recorder_package'
    if (-not (Test-VerifiedFile $bundleDest $bundleHash 45000000 50000000)) {
        $zipUrl = 'https://drive.google.com/uc?export=download&confirm=t&id=1CpeXX10j9GojCfGVG91mxfp2XqH9ZSVB'
        $zipTemp = Join-Path $root 'Capagross-recorder-download.partial'
        try {
            Write-Host 'Recupero il registratore verificato da Google Drive...' -ForegroundColor Cyan
            Invoke-WebRequest -Uri $zipUrl -UseBasicParsing -OutFile $zipTemp -TimeoutSec 180 -ErrorAction Stop
            if (Test-VerifiedFile $zipTemp $bundleHash 45000000 50000000) {
                Move-Item -LiteralPath $zipTemp -Destination $bundleDest -Force
            }
        } catch {
            Write-Warning ('Download cloud non disponibile; nessun file non verificato eseguito: ' + $_.Exception.Message)
        } finally {
            if (Test-Path -LiteralPath $zipTemp) { Remove-Item -LiteralPath $zipTemp -Force }
        }
    }
    if (-not (Test-VerifiedFile $bundleDest $bundleHash 45000000 50000000)) {
        throw 'RECORDER_PACKAGE_NOT_AVAILABLE_IN_LOCAL_SYNC_OR_DRIVE'
    }
    # Download approved, SHA-pinned CDP orchestrator (no user prompt).
    $phase = 'cdp_orchestrator_setup'
    $autoUrl = 'https://raw.githubusercontent.com/ruggeropaolobasile/ruggero/e51e8c65c95d696b8c800613b1e2d3ef68b513e7/auto.ps1'
    $autoPath = Join-Path $root 'Capagross-AutoCapture-CDP.ps1'
    $autoTemp = Join-Path $root 'auto.ps1.partial'
    $autoHash = 'CBE471EC2DF6BBA75D42D99C08FA0F6DB47A9887F4E45F5C02C7191DB4BCD350'
    if (-not (Test-VerifiedFile $autoPath $autoHash 9000 11000)) {
        Invoke-WebRequest -Uri $autoUrl -UseBasicParsing -TimeoutSec 40 -OutFile $autoTemp -ErrorAction Stop
        if (-not (Test-VerifiedFile $autoTemp $autoHash 9000 11000)) {
            throw 'AUTOCAPTURE_SCRIPT_SHA256_MISMATCH'
        }
        Move-Item -LiteralPath $autoTemp -Destination $autoPath -Force
    }
    $phase = 'audio_capture_cdp'
    $outDir = Join-Path $env:USERPROFILE 'Music\Capagross'
    if (-not (Test-VerifiedFile $bundleDest $bundleHash 45000000 50000000)) {
        throw 'VERIFIED_RECORDER_ZIP_MISSING: cannot start unattended recording'
    }
    $packageDir = Join-Path $root 'package'
    $exe = Join-Path $packageDir 'CapagrossRX18.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
        Expand-Archive -LiteralPath $bundleDest -DestinationPath $packageDir -Force
    }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'RECORDER_EXE_MISSING_AFTER_EXTRACT' }
    $doctorResult = (& $exe doctor 2>&1 | Out-String) | ConvertFrom-Json
    if (-not $doctorResult.windows -or -not $doctorResult.ffmpeg -or
        -not $doctorResult.pyaudiowpatch -or -not $doctorResult.loopback_available) {
        throw 'RX18_AUDIO_DOCTOR_NOT_READY'
    }
    Write-Host 'CDP_AUTOMATION: capture starts first; Suno PLAY happens without manual action.' -ForegroundColor Green
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $autoPath -RecorderExe $exe -LogsDirectory $logs -OutputDirectory $outDir
    if ($LASTEXITCODE -ne 0) {
        throw ('CDP_AUTONOMOUS_RECORDING_FAILED exit=' + $LASTEXITCODE)
    }
    $resultCode = 0
    $phase = 'completed'
    Write-Host 'Registrazione conclusa: consultare il MP3 e il manifest nella cartella Musica\Capagross.' -ForegroundColor Green
} catch {
    $errorDetail = ($_ | Format-List * -Force | Out-String)
    Write-Host ("ERRORE [" + $phase + "]: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host $errorDetail -ForegroundColor Red
    Write-Host ("Log di bootstrap: " + $log) -ForegroundColor Yellow
    throw
} finally {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
    try {
        $parts = New-Object 'System.Collections.Generic.List[string]'
        $parts.Add(('CAPAGROSS RX18 COMPLETE EXECUTION / RUN ' + $runId))
        $parts.Add(('Started: ' + $runStartedAt.ToString('o')))
        $parts.Add(('Completed: ' + (Get-Date).ToString('o')))
        $parts.Add(('Status: ' + $(if ($resultCode -eq 0) { 'SUCCESS' } else { 'FAILED' })))
        $parts.Add(('Phase: ' + $phase))
        $parts.Add(('Exit code: ' + $resultCode))
        $parts.Add(('Bootstrap transcript: ' + $log))
        $parts.Add('===== BOOTSTRAP OUTPUT =====')
        if (Test-Path -LiteralPath $log -PathType Leaf) {
            $parts.Add([System.IO.File]::ReadAllText($log))
        } else { $parts.Add('Bootstrap transcript unavailable') }
        $children = @(Get-ChildItem -LiteralPath $logs -Filter 'Capagross-RX18-*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $runStartedAt.AddSeconds(-3) -and $_.FullName -ne $fullLog } |
            Sort-Object LastWriteTime)
        foreach ($child in $children) {
            $parts.Add(('===== CHILD TRANSCRIPT ' + $child.Name + ' ====='))
            try { $parts.Add([System.IO.File]::ReadAllText($child.FullName)) }
            catch { $parts.Add(('Unable to read child log: ' + $_.Exception.Message)) }
        }
        if ($errorDetail) {
            $parts.Add('===== FULL ERROR RECORD =====')
            $parts.Add($errorDetail)
        }
        [System.IO.File]::WriteAllText($fullLog, [string]::Join([Environment]::NewLine, $parts.ToArray()), [System.Text.Encoding]::UTF8)
        # If discovery failed early, retry at exit to avoid losing a failed-run log.
        if ($syncTargets.Count -eq 0) {
            try {
                $syncTargets = @(Get-SyncedLogDirectories @(Get-SyncRoots))
                if ($syncTargets.Count -gt 0) {
                    Add-Content -LiteralPath $fullLog -Value ('Log sync recovered after failure: ' + ($syncTargets -join ', ')) -Encoding UTF8
                }
            } catch {
                Write-Warning ('Drive/Dropbox retry for logs failed: ' + $_.Exception.Message)
            }
        }
        $status = [ordered]@{
            runId = $runId
            status = $(if ($resultCode -eq 0) { 'success' } else { 'failed' })
            exitCode = $resultCode
            phase = $phase
            startedAt = $runStartedAt.ToString('o')
            completedAt = (Get-Date).ToString('o')
            fullLog = $fullLog
            childLogCount = $children.Count
            syncedLogTargets = $syncTargets
            error = $(if ($errorDetail) { ($errorDetail.Split([char]10) | Select-Object -First 3) -join ' | ' } else { $null })
        }
        $status | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statusFile -Encoding UTF8
        $published = @(Publish-RunLogs -sourceLog $fullLog -sourceStatus $statusFile -targets $syncTargets)
        if ($published.Count -eq 0) {
            Write-Warning ('Nessun log condiviso: log completo locale in ' + $fullLog)
        } else {
            Write-Host ('LOG_COMPLETO_SINCRONIZZATO: ' + ($published -join ', ')) -ForegroundColor Green
        }
        Write-Host ('LOG_COMPLETO_LOCALE: ' + $fullLog)
    } catch {
        Write-Warning ('Impossibile finalizzare il bundle log: ' + $_.Exception.Message)
        Write-Warning ('Transcript base conservato in: ' + $log)
    }
}
