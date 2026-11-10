# Small public bootstrap; the authoritative capture script remains in private Google Drive.
# Drive export is SHA256-pinned. No secrets, admin, Codex or third-party downloader.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$docId = '1hyIQiU8Z3MPOJJqOtV9sCLfc-m2rp78TA-P61toD9zs'
$expected = '2CA89F4219809371024C4EF1043C4DAFCE38E6F411F8C1308DBCFFFB6CD49605'
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
    $home = $env:USERPROFILE
    $roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($path in @(
        (Join-Path $home 'Dropbox'),
        (Join-Path $home 'Google Drive'),
        (Join-Path $home 'My Drive'),
        (Join-Path $home 'Il mio Drive'),
        (Join-Path $home 'Downloads'),
        (Join-Path $home 'Music')
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
            if (Test-Path -LiteralPath $folder -PathType Container -ErrorAction SilentlyContinue) {
                Write-Output $folder
            }
        }
    }
}
function Stage-SyncedFiles([string[]]$dirs) {
    if (-not (Test-VerifiedFile $script $expected 8000 12000)) {
        foreach ($dir in $dirs) {
            foreach ($name in @('Capagross-RX18-ONE-SHOT.ps1', 'Capagross-RX18-ONE-SHOT.ps1.txt')) {
                $candidate = Join-Path $dir $name
                if (Test-VerifiedFile $candidate $expected 8000 12000) {
                    Copy-Item -LiteralPath $candidate -Destination $script -Force
                    Write-Host ("Script sincronizzato verificato: " + $candidate) -ForegroundColor Green
                    break
                }
            }
            if (Test-VerifiedFile $script $expected 8000 12000) { break }
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

$transcript = $false
try {
    Start-Transcript -Path $log -Force | Out-Null
    $transcript = $true
    Write-Host ("BOOTSTRAP RX18 - log: " + $log) -ForegroundColor Cyan
    $syncDirs = @(Get-SyncRoots)
    Write-Host ("Sorgenti Drive/Dropbox locali disponibili: " + $syncDirs.Count) -ForegroundColor Cyan
    Stage-SyncedFiles $syncDirs
    $verified = $false
    if (Test-Path $script -PathType Leaf) {
        $verified = ((Get-FileHash -LiteralPath $script -Algorithm SHA256).Hash -eq $expected)
    }
    if (-not $verified) {
        try {
            Invoke-WebRequest -Uri $docDownload -UseBasicParsing -OutFile $part -TimeoutSec 35 -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash -eq $expected) {
                Move-Item -LiteralPath $part -Destination $script -Force
                $verified = $true
            }
        } catch {
            Write-Host 'Drive richiede il login; utilizzo il browser gia autenticato.' -ForegroundColor Yellow
        } finally {
            if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
        }
    }
    if (-not $verified) {
        Write-Host 'Apro Drive nel browser per scaricare lo script di 8 KB...' -ForegroundColor Cyan
        Start-Process $docDownload
        $deadline = (Get-Date).AddMinutes(3)
        while ((Get-Date) -lt $deadline -and -not $verified) {
            $candidates = @(Get-ChildItem -LiteralPath $downloads -File -Filter '*.txt' -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt 8000 -and $_.Length -lt 12000 -and $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) } |
                Sort-Object LastWriteTime -Descending)
            foreach ($candidate in $candidates) {
                if ((Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256).Hash -eq $expected) {
                    Copy-Item -LiteralPath $candidate.FullName -Destination $script -Force
                    $verified = $true
                    break
                }
            }
            if (-not $verified) { Start-Sleep -Seconds 3 }
        }
    }
    if (-not $verified -or -not (Test-Path $script -PathType Leaf)) {
        throw 'Impossibile scaricare lo script privato da Drive. Controllare il browser o il login.'
    }
    if ((Get-FileHash -LiteralPath $script -Algorithm SHA256).Hash -ne $expected) {
        throw 'Hash SHA-256 script non corrispondente: esecuzione bloccata.'
    }
    Write-Host 'Script Drive autenticato e verificato. Eseguo...' -ForegroundColor Green
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script
    if ($LASTEXITCODE -ne 0) { throw ("Registrazione fallita (exit " + $LASTEXITCODE + "); consultare i log sotto " + $logs) }
    Write-Host 'Registrazione conclusa: consultare il MP3 e il manifest nella cartella Musica\Capagross.' -ForegroundColor Green
} catch {
    Write-Host ("ERRORE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Log di bootstrap: " + $log) -ForegroundColor Yellow
    throw
} finally {
    if ($transcript) { Stop-Transcript | Out-Null }
}
