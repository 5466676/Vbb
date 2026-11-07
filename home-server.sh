#!/usr/bin/env bash
# Home server for حرب العقول: one process, one SQLite file, exposed with Tailscale Funnel.
#
#   ./home-server.sh start    # install (first time), migrate, seed, start, open the funnel
#   ./home-server.sh stop     # close the funnel and stop the server
#   ./home-server.sh status
#   ./home-server.sh logs
#
# Settings live in backend/data/home.env (created on first start, never committed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$ROOT/backend"
DATA="$BACKEND/data"
VENV="$BACKEND/.venv"
PORT="${HARB_PORT:-8080}"
FUNNEL_PORT="${HARB_FUNNEL_PORT:-443}"   # Funnel allows 443, 8443 or 10000
PIDFILE="$DATA/server.pid"
LOG="$DATA/server.log"
PY="${PYTHON:-python3}"

say() { printf '\033[1m%s\033[0m\n' "$*"; }

running() { [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

healthy() { curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; }

setup() {
  mkdir -p "$DATA"
  if [[ ! -x "$VENV/bin/python" ]]; then
    say "Creating the Python environment (first start only)…"
    "$PY" -m venv "$VENV"
  fi
  # reinstall when pyproject.toml changed
  local stamp="$VENV/.installed" sum
  sum="$(cksum < "$BACKEND/pyproject.toml")"
  if [[ ! -f "$stamp" || "$(cat "$stamp")" != "$sum" ]]; then
    say "Installing the server…"
    "$VENV/bin/pip" install -q --upgrade pip
    "$VENV/bin/pip" install -q -e "$BACKEND[home]"
    echo "$sum" > "$stamp"
  fi
  if [[ ! -f "$DATA/home.env" ]]; then
    umask 077
    cat > "$DATA/home.env" <<ENV
HARB_ENV=home
HARB_DATABASE_URL=sqlite+aiosqlite:///$DATA/harb.db
HARB_REDIS_URL=memory://
HARB_JWT_SECRET=$("$VENV/bin/python" -c 'import secrets;print(secrets.token_urlsafe(48))')
HARB_ADMIN_KEY=$("$VENV/bin/python" -c 'import secrets;print(secrets.token_urlsafe(24))')
ENV
    say "Created $DATA/home.env (keep it private: it holds the admin key)."
  fi
}

start() {
  if running; then say "Already running (pid $(cat "$PIDFILE"))."; else
    setup
    set -a; source "$DATA/home.env"; set +a
    cd "$BACKEND"
    "$VENV/bin/alembic" upgrade head >/dev/null
    "$VENV/bin/python" -m app.questions.seed
    # one worker only: rooms live in this process (in-memory Redis)
    nohup "$VENV/bin/uvicorn" app.main:app --host 127.0.0.1 --port "$PORT" \
      --workers 1 --no-access-log >>"$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    for _ in $(seq 50); do healthy && break; sleep 0.2; done
    healthy || { say "The server did not start. Last log lines:"; tail -20 "$LOG"; exit 1; }
    say "Server up on http://127.0.0.1:$PORT"
  fi
  if command -v tailscale >/dev/null; then
    tailscale funnel --bg --https="$FUNNEL_PORT" "http://localhost:$PORT" >/dev/null
    say "Funnel open:"
    tailscale funnel status
  else
    say "tailscale not found: the server is local only (install Tailscale and enable Funnel)."
  fi
}

stop() {
  if command -v tailscale >/dev/null; then
    tailscale funnel --https="$FUNNEL_PORT" off >/dev/null 2>&1 || true
    say "Funnel closed."
  fi
  if running; then
    kill "$(cat "$PIDFILE")"
    for _ in $(seq 50); do running || break; sleep 0.2; done
    running && kill -9 "$(cat "$PIDFILE")"
    say "Server stopped."
  else
    say "Server was not running."
  fi
  rm -f "$PIDFILE"
}

status() {
  if running && healthy; then say "Server: running (pid $(cat "$PIDFILE")) on port $PORT"; else say "Server: stopped"; fi
  command -v tailscale >/dev/null && tailscale funnel status || true
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  logs) tail -f "$LOG" ;;
  *) echo "usage: $0 start|stop|restart|status|logs"; exit 2 ;;
esac
