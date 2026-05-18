# Descarga apex-latest.zip de Oracle a ./downloads/ si no existe.
# Uso: powershell -ExecutionPolicy Bypass -File scripts\download-apex.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'downloads\apex-latest.zip'

if (Test-Path $dest) {
    $sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
    Write-Host "apex-latest.zip ya existe ($sizeMB MB). Borra el archivo si querés re-descargar." -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null

Write-Host "Descargando apex-latest.zip (~300 MB)..."
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri "https://download.oracle.com/otn_software/apex/apex-latest.zip" -OutFile $dest -UseBasicParsing

$sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
Write-Host "Listo. $dest ($sizeMB MB)" -ForegroundColor Green
