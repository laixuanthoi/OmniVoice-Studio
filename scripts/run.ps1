# ==============================================================================
#  OmniVoice Studio — Windows Launcher
#
#  Run this script any time AFTER install to start the app:
#
#    powershell -ExecutionPolicy Bypass -File scripts\run.ps1
#
#  Options:
#    -NoOpen     Don't auto-open the browser
#    -Port       Override port (default: 3900)
#    -Host       Override bind address (default: 127.0.0.1)
# ==============================================================================
[CmdletBinding()]
param(
    [switch] $NoOpen,
    [int]    $Port = 3900,
    [string] $BindHost = "127.0.0.1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Colour helpers ─────────────────────────────────────────────────────────────
function Write-Step { param($label,$msg) Write-Host "  $(($label).PadRight(16))" -NoNewline -ForegroundColor DarkGray; Write-Host $msg -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "  ✗  $msg" -ForegroundColor Red; exit 1 }

# ── Resolve repo root (handles both "run from repo" and "run from anywhere") ───
$scriptDir = if ($MyInvocation.MyCommand.Path) { Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent } else { $PWD.Path }
if (-not (Test-Path (Join-Path $scriptDir "pyproject.toml"))) {
    Write-Fail "Cannot find pyproject.toml. Run from inside the OmniVoice-Studio repo, or use install.ps1 first."
}
Set-Location $scriptDir

# ── Sanity checks ──────────────────────────────────────────────────────────────
if (-not (Test-Path ".venv")) {
    Write-Fail ".venv not found. Run scripts\install.ps1 first."
}
if (-not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
    Write-Fail "uv not found. Run scripts\install.ps1 first."
}

# ── Banner ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  🎙  OmniVoice Studio" -ForegroundColor Magenta
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Kill any stale process on our port ────────────────────────────────────────
$stale = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($stale) {
    Write-Step "cleanup" "Killing stale process on port $Port..."
    $stale | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
}

# ── Set PYTHONPATH ─────────────────────────────────────────────────────────────
$env:PYTHONPATH = "$scriptDir\backend"

# ── Start backend ──────────────────────────────────────────────────────────────
Write-Step "backend" "starting on http://${BindHost}:${Port} ..."

$proc = Start-Process -FilePath "uv" `
    -ArgumentList "run", "uvicorn", "main:app", "--app-dir", "backend",
                  "--host", $BindHost, "--port", "$Port" `
    -WorkingDirectory $scriptDir `
    -PassThru -WindowStyle Hidden

Write-Step "PID" $proc.Id

# ── Wait for health ────────────────────────────────────────────────────────────
$deadline = 120
$elapsed  = 0
$healthy  = $false

Write-Host "  Waiting for backend" -NoNewline -ForegroundColor DarkGray
while ($elapsed -lt $deadline) {
    Start-Sleep -Seconds 2
    $elapsed += 2
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:${Port}/system/info" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($r.StatusCode -eq 200) { $healthy = $true; break }
    } catch {}
    if ($proc.HasExited) { Write-Host ""; Write-Fail "Backend exited unexpectedly." }
    Write-Host "." -NoNewline -ForegroundColor DarkGray
}
Write-Host ""

if (-not $healthy) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Write-Fail "Backend didn't respond in ${deadline}s."
}

Write-Step "status" "UP — http://localhost:${Port}"

if (-not $NoOpen) {
    Start-Process "http://localhost:${Port}"
}

Write-Host ""
Write-Host "  OmniVoice Studio is running. Press Ctrl+C to stop." -ForegroundColor Green
Write-Host ""

try {
    while (-not $proc.HasExited) { Start-Sleep -Seconds 5 }
} finally {
    if (-not $proc.HasExited) {
        $proc.Kill()
        Write-Host "`n  Stopped." -ForegroundColor DarkGray
    }
}
