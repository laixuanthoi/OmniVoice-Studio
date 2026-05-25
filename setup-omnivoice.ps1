# Run PowerShell as Administrator the first time
$ErrorActionPreference = "Stop"

function Has-Cmd($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
  $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $user    = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = "$machine;$user"
}

Write-Host "== OmniVoice Windows bootstrap ==" -ForegroundColor Cyan

if (-not (Has-Cmd winget)) {
  throw "Không tìm thấy winget. Hãy cập nhật App Installer từ Microsoft Store."
}

# 1) Install dependencies if missing
if (-not (Has-Cmd git)) {
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
}
if (-not (Has-Cmd bun)) {
  winget install --id Oven-sh.Bun -e --source winget --accept-package-agreements --accept-source-agreements
}
if (-not (Has-Cmd uv)) {
  winget install --id Astral-sh.uv -e --source winget --accept-package-agreements --accept-source-agreements
}

Refresh-Path

# Verify tools
git --version
bun --version
uv --version

# 2) Clone / update repo
$REPO_URL = "https://github.com/<your-org>/OmniVoice-Studio.git"   # <-- sửa URL repo
$APP_DIR  = "$HOME\OmniVoice-Studio"

if (!(Test-Path "$APP_DIR\.git")) {
  git clone $REPO_URL $APP_DIR
}

Set-Location $APP_DIR
git pull --rebase

# 3) Network-friendly uv settings (for restricted/slow networks)
$env:UV_HTTP_TIMEOUT = "120"
$env:UV_HTTP_CONNECT_TIMEOUT = "30"
$env:UV_HTTP_RETRIES = "5"

# Optional mirrors (uncomment if needed):
# $env:UV_PYTHON_INSTALL_MIRROR = "https://ghproxy.com/https://github.com/astral-sh/python-build-standalone/releases/download"
# $env:UV_DEFAULT_INDEX = "https://pypi.tuna.tsinghua.edu.cn/simple"

# 4) Backend setup
Set-Location "$APP_DIR\backend"
try {
  uv venv --python 3.11
} catch {
  Write-Host "uv download Python fail -> fallback only-system" -ForegroundColor Yellow
  $env:UV_PYTHON_PREFERENCE = "only-system"
  uv venv --python 3.11
}
uv sync

# 5) Frontend setup
Set-Location $APP_DIR
bun install

Write-Host "`n== SETUP DONE ==" -ForegroundColor Green
Write-Host "Run backend : cd `"$APP_DIR\backend`"; uv run python main.py"
Write-Host "Run frontend: cd `"$APP_DIR`"; bun run tauri dev"
