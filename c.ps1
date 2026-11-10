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
$transcript = $false
try {
    Start-Transcript -Path $log -Force | Out-Null
    $transcript = $true
    Write-Host ("BOOTSTRAP RX18 - log: " + $log) -ForegroundColor Cyan
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
