# ==============================================================================
#  OmniVoice Studio — Windows PowerShell Installer
#
#  Run with ONE command (no Git clone needed beforehand):
#
#    irm https://raw.githubusercontent.com/debpalash/OmniVoice-Studio/main/scripts/install.ps1 | iex
#
#  Or locally (from inside the repo):
#
#    powershell -ExecutionPolicy Bypass -File scripts\install.ps1
#
#  Options (append after the file path when running locally):
#    -NoOpen        Don't auto-open the browser after install
#    -SkipFrontend  Skip npm/bun install + frontend build
#    -Verbose       Show all sub-command output
#    -InstallDir    Where to clone the repo (default: $HOME\OmniVoice)
#
#  Requirements: Windows 10/11 x64, PowerShell 5.1+ or PowerShell 7+,
#                Internet connection, NVIDIA GPU with CUDA 12.x drivers.
#
#  After install, run the app again anytime with:
#    powershell -ExecutionPolicy Bypass -File scripts\run.ps1
# ==============================================================================
[CmdletBinding()]
param(
    [string]  $InstallDir  = "$HOME\OmniVoice",
    [switch]  $NoOpen,
    [switch]  $SkipFrontend,
    [switch]  $SkipRun       # Install only, do not start the server
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Colour helpers ─────────────────────────────────────────────────────────────
function Write-Step  { param($label,$msg) Write-Host "  $(($label).PadRight(18))" -NoNewline -ForegroundColor DarkGray; Write-Host $msg -ForegroundColor Green }
function Write-Note  { param($msg)        Write-Host "  $(''.PadRight(18))$msg"   -ForegroundColor DarkGray }
function Write-Warn  { param($msg)        Write-Host "  ⚠  $msg"                  -ForegroundColor Yellow }
function Write-Fail  { param($msg)        Write-Host "  ✗  $msg"                  -ForegroundColor Red; exit 1 }

# ── Banner ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  🎙  OmniVoice Studio Installer" -ForegroundColor Magenta
Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Require 64-bit PowerShell ──────────────────────────────────────────────────
if (-not [Environment]::Is64BitProcess) { Write-Fail "Please run this script in a 64-bit PowerShell session." }

# ── Helper: run a command, throw on non-zero exit ──────────────────────────────
function Invoke-Cmd {
    param([string]$Exe, [string[]]$Args, [string]$Cwd = $PWD)
    $result = & $Exe @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ($result | Out-String) -ForegroundColor DarkGray
        Write-Fail "'$Exe $($Args -join ' ')' failed (exit $LASTEXITCODE)"
    }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-Host ($result | Out-String) -ForegroundColor DarkGray }
}

# ── Helper: refresh PATH in current session ────────────────────────────────────
function Update-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = "$machinePath;$userPath;$HOME\.local\bin;$HOME\.bun\bin;$HOME\.cargo\bin"
}

# ── Helper: check if a command exists ─────────────────────────────────────────
function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# ── STEP 0: Clone or update repo ──────────────────────────────────────────────
$repoUrl = "https://github.com/debpalash/OmniVoice-Studio.git"
$scriptPath = $MyInvocation.MyCommand.Path

# Detect if we are already running *inside* the repo
$repoRoot = $null
if ($scriptPath) {
    $candidate = Split-Path (Split-Path $scriptPath -Parent) -Parent
    if (Test-Path (Join-Path $candidate "pyproject.toml")) {
        $repoRoot = $candidate
    }
}

if ($repoRoot) {
    Write-Step "repo" "already at $repoRoot"
} else {
    # Running via irm | iex — need to clone
    Write-Step "repo" "cloning OmniVoice Studio..."
    if (Test-Path (Join-Path $InstallDir ".git")) {
        Write-Note "Updating existing clone at $InstallDir"
        Push-Location $InstallDir
        git pull --ff-only 2>$null | Out-Null
        Pop-Location
    } else {
        if (-not (Test-Command "git")) {
            # Try to install Git via winget silently
            Write-Note "Git not found. Trying to install via winget..."
            winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements 2>$null | Out-Null
            Update-SessionPath
            if (-not (Test-Command "git")) {
                Write-Fail "git is required. Install from https://git-scm.com/download/win and re-run."
            }
        }
        git clone --depth 1 $repoUrl $InstallDir
    }
    $repoRoot = $InstallDir
}

Set-Location $repoRoot
Write-Step "working dir" $repoRoot

# ── STEP 1: ffmpeg ─────────────────────────────────────────────────────────────
Write-Step "ffmpeg" "checking..."
if (-not (Test-Command "ffmpeg")) {
    Write-Note "Installing ffmpeg via winget..."
    winget install --id Gyan.FFmpeg -e --silent --accept-package-agreements --accept-source-agreements 2>$null | Out-Null
    Update-SessionPath
}
if (Test-Command "ffmpeg") {
    $ffver = (ffmpeg -version 2>&1 | Select-Object -First 1) -replace 'ffmpeg version ',''
    Write-Step "ffmpeg" $ffver.Split(' ')[0]
} else {
    Write-Warn "ffmpeg not found — some features (audio splitting, dub pipeline) will be unavailable."
}

# ── STEP 2: uv (Python package manager) ───────────────────────────────────────
Write-Step "uv" "checking..."
$UV_MIN = [version]"0.7.0"
$uvOk   = $false
if (Test-Command "uv") {
    $uvVerStr = (uv --version 2>&1) -replace 'uv ',''
    try { if ([version]($uvVerStr.Split('-')[0]) -ge $UV_MIN) { $uvOk = $true } } catch {}
}

if (-not $uvOk) {
    Write-Note "Installing uv package manager..."
    $uvInstallScript = (Invoke-WebRequest "https://astral.sh/uv/install.ps1" -UseBasicParsing).Content
    Invoke-Expression $uvInstallScript
    Update-SessionPath
    if (-not (Test-Command "uv")) { Write-Fail "uv installation failed. Install manually: https://docs.astral.sh/uv/getting-started/installation/" }
}
Write-Step "uv" (uv --version 2>&1)

# ── STEP 3: Python 3.11 venv ───────────────────────────────────────────────────
$PYTHON_VERSION = "3.11"
Write-Step "python" "checking venv..."

if (-not (Test-Path ".venv")) {
    Write-Note "Creating virtualenv with Python $PYTHON_VERSION..."
    uv venv --python $PYTHON_VERSION
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to create venv. uv will auto-download Python $PYTHON_VERSION if needed." }
}

# ── STEP 4: Python dependencies (PyTorch CUDA + all ML libs) ──────────────────
Write-Step "python" "syncing dependencies (first run: 10-20 min for PyTorch+CUDA)..."
Write-Note "Downloads: PyTorch 2.8+CUDA12.8, WhisperX, Demucs, AudioSeal, FastAPI..."
uv sync
if ($LASTEXITCODE -ne 0) { Write-Fail "uv sync failed. Check your internet connection or run with -Verbose for details." }
Write-Step "python" "OK — virtualenv at .venv\"

# ── STEP 5: cuDNN 8 compat (needed by CTranslate2 / faster-whisper) ───────────
Write-Step "cudnn8" "setting up compatibility shim..."
uv run python scripts/setup_cudnn.py
Write-Step "cudnn8" "OK"

# ── STEP 6: Alembic DB migration ───────────────────────────────────────────────
Write-Step "database" "running migrations..."
$env:PYTHONPATH = "$repoRoot\backend"
uv run --directory $repoRoot alembic -c alembic.ini upgrade head 2>$null | Out-Null
Write-Step "database" "OK"

# ── STEP 7: Bun + Frontend ─────────────────────────────────────────────────────
if (-not $SkipFrontend) {
    Write-Step "bun" "checking..."
    if (-not (Test-Command "bun")) {
        Write-Note "Installing Bun JavaScript runtime..."
        $bunInstall = (Invoke-WebRequest "https://bun.sh/install.ps1" -UseBasicParsing).Content
        Invoke-Expression $bunInstall
        Update-SessionPath
        if (-not (Test-Command "bun")) { Write-Fail "Bun installation failed. Install manually: https://bun.sh/docs/installation" }
    }
    Write-Step "bun" "bun $(bun --version 2>&1)"

    Write-Step "frontend" "installing JS dependencies..."
    bun install --cwd $repoRoot
    if ($LASTEXITCODE -ne 0) { Write-Fail "bun install failed." }

    Write-Step "frontend" "building production bundle..."
    bun run --cwd (Join-Path $repoRoot "frontend") build
    if ($LASTEXITCODE -ne 0) { Write-Fail "Frontend build failed." }
    Write-Step "frontend" "OK — output at frontend\dist\"
}

# ── Done ───────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ✓  Install complete!" -ForegroundColor Magenta
Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Note "First launch downloads ~5 GB of ML model weights (OmniVoice TTS + Whisper)."
Write-Note "After that, launches are instant."
Write-Host ""

# ── STEP 8: Start server (unless -SkipRun) ────────────────────────────────────
if ($SkipRun) {
    Write-Step "next step" "Run .\scripts\run.ps1 to start OmniVoice Studio"
    Write-Host ""
    exit 0
}

Write-Step "server" "starting on http://localhost:3900 ..."
$env:PYTHONPATH = "$repoRoot\backend"

$proc = Start-Process -FilePath "uv" `
    -ArgumentList "run", "uvicorn", "main:app", "--app-dir", "backend", "--host", "127.0.0.1", "--port", "3900" `
    -WorkingDirectory $repoRoot `
    -PassThru -WindowStyle Hidden

Write-Note "Backend PID: $($proc.Id) — waiting for health check..."

# Wait for health (up to 120 s)
$deadline = 120
$elapsed  = 0
$healthy  = $false
while ($elapsed -lt $deadline) {
    Start-Sleep -Seconds 2
    $elapsed += 2
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:3900/system/info" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($r.StatusCode -eq 200) { $healthy = $true; break }
    } catch {}
    if ($proc.HasExited) { Write-Fail "Backend process exited unexpectedly (PID $($proc.Id))." }
    Write-Host "." -NoNewline -ForegroundColor DarkGray
}
Write-Host ""

if (-not $healthy) { Write-Fail "Backend didn't respond in ${deadline}s. Check the console window for errors." }

Write-Step "server" "UP — http://localhost:3900"

if (-not $NoOpen) {
    Start-Process "http://localhost:3900"
}

Write-Host ""
Write-Host "  OmniVoice Studio is running." -ForegroundColor Green
Write-Host "  Close this window or press Ctrl+C to shut down." -ForegroundColor DarkGray
Write-Host ""

# Keep the script alive so the background server continues
try {
    while (-not $proc.HasExited) { Start-Sleep -Seconds 5 }
} finally {
    if (-not $proc.HasExited) { $proc.Kill() }
    Write-Host "`n  Shut down." -ForegroundColor DarkGray
}
