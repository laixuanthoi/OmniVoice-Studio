#!/usr/bin/env bash
# Start OmniVoice Studio backend + frontend for local development.
#
# Defaults are tuned for this machine:
#   - TTS model: drbaph/OmniVoice-bf16
#   - ASR backend: faster-whisper
#   - ASR model: turbo
#
# Usage:
#   bash scripts/start-app.sh
#   bash scripts/start-app.sh --no-open
#   OMNIVOICE_MODEL=k2-fsa/OmniVoice bash scripts/start-app.sh

set -euo pipefail

NO_OPEN=false
for arg in "$@"; do
  case "$arg" in
    --no-open) NO_OPEN=true ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

BACKEND_PORT="${BACKEND_PORT:-3900}"
FRONTEND_PORT="${FRONTEND_PORT:-3901}"
BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
FRONTEND_HOST="${FRONTEND_HOST:-127.0.0.1}"

export OMNIVOICE_MODEL="${OMNIVOICE_MODEL:-drbaph/OmniVoice-bf16}"
export OMNIVOICE_ASR_BACKEND="${OMNIVOICE_ASR_BACKEND:-faster-whisper}"
export ASR_MODEL_FASTER="${ASR_MODEL_FASTER:-turbo}"

LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/.logs}"
mkdir -p "$LOG_DIR"
BACKEND_LOG="$LOG_DIR/backend.log"
FRONTEND_LOG="$LOG_DIR/frontend.log"

if ! have uv; then
  echo "uv not found. Install uv first." >&2
  exit 1
fi

if ! have bun; then
  echo "bun not found. Install Bun first." >&2
  exit 1
fi

if [ ! -d ".venv" ]; then
  echo ".venv not found. Run: uv sync --python 3.11" >&2
  exit 1
fi

stop_port() {
  local port="$1"
  if have powershell.exe; then
    powershell.exe -NoProfile -Command \
      "Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { if (\$_ -ne 0) { Stop-Process -Id \$_ -Force -ErrorAction SilentlyContinue } }" \
      >/dev/null 2>&1 || true
  elif have lsof; then
    lsof -tiTCP:"$port" -sTCP:LISTEN | xargs -r kill -9 2>/dev/null || true
  fi
}

wait_url() {
  local url="$1"
  local label="$2"
  local deadline="${3:-120}"
  local elapsed=0

  while [ "$elapsed" -lt "$deadline" ]; do
    if have curl && curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  echo "$label did not become ready after ${deadline}s: $url" >&2
  return 1
}

BACKEND_PID=""
FRONTEND_PID=""

cleanup() {
  echo ""
  echo "Stopping OmniVoice Studio..."
  if [ -n "$FRONTEND_PID" ]; then
    kill "$FRONTEND_PID" >/dev/null 2>&1 || true
    wait "$FRONTEND_PID" 2>/dev/null || true
  fi
  if [ -n "$BACKEND_PID" ]; then
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
    wait "$BACKEND_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Stopping old servers on ports $BACKEND_PORT and $FRONTEND_PORT..."
stop_port "$BACKEND_PORT"
stop_port "$FRONTEND_PORT"

echo "Starting backend on http://$BACKEND_HOST:$BACKEND_PORT"
echo "  OMNIVOICE_MODEL=$OMNIVOICE_MODEL"
echo "  OMNIVOICE_ASR_BACKEND=$OMNIVOICE_ASR_BACKEND"
echo "  ASR_MODEL_FASTER=$ASR_MODEL_FASTER"
echo "  log: $BACKEND_LOG"
uv run uvicorn main:app --app-dir backend --host "$BACKEND_HOST" --port "$BACKEND_PORT" \
  >"$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!

if ! wait_url "http://$BACKEND_HOST:$BACKEND_PORT/health" "Backend" 180; then
  echo "Last backend log lines:" >&2
  tail -n 80 "$BACKEND_LOG" >&2 || true
  exit 1
fi

echo "Starting frontend on http://$FRONTEND_HOST:$FRONTEND_PORT"
echo "  log: $FRONTEND_LOG"
bun run --cwd frontend dev --host "$FRONTEND_HOST" --port "$FRONTEND_PORT" \
  >"$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!

if ! wait_url "http://$FRONTEND_HOST:$FRONTEND_PORT" "Frontend" 90; then
  echo "Last frontend log lines:" >&2
  tail -n 80 "$FRONTEND_LOG" >&2 || true
  exit 1
fi

APP_URL="http://$FRONTEND_HOST:$FRONTEND_PORT"
echo ""
echo "OmniVoice Studio is running."
echo "  Frontend: $APP_URL"
echo "  Backend:  http://$BACKEND_HOST:$BACKEND_PORT"
echo "  Backend log:  $BACKEND_LOG"
echo "  Frontend log: $FRONTEND_LOG"
echo "Press Ctrl+C to stop."

if [ "$NO_OPEN" != true ]; then
  if have powershell.exe; then
    powershell.exe -NoProfile -Command "Start-Process '$APP_URL'" >/dev/null 2>&1 || true
  elif have xdg-open; then
    xdg-open "$APP_URL" >/dev/null 2>&1 || true
  elif have open; then
    open "$APP_URL" >/dev/null 2>&1 || true
  fi
fi

while kill -0 "$BACKEND_PID" >/dev/null 2>&1 && kill -0 "$FRONTEND_PID" >/dev/null 2>&1; do
  sleep 2
done

echo "A server process exited."
exit 1
