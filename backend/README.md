# حرب العقول — server

Authoritative game server: FastAPI + WebSockets. Two ways to run it:

| | home server (your computer) | full stack (Docker) |
|---|---|---|
| database | one SQLite file `backend/data/harb.db` | PostgreSQL |
| rooms / pub-sub | in-process (`HARB_REDIS_URL=memory://`) | Redis, several workers |
| start | `./home-server.sh start` | `docker compose up --build` |

## Home server + Tailscale Funnel

Needs Python 3.12+, `curl`, and (to be reachable from the internet) Tailscale with Funnel enabled
for this machine (admin console → Access controls → `funnel` node attribute; HTTPS certificates on).

```bash
./home-server.sh start     # first time: venv + install, then migrate, seed, start, open the funnel
./home-server.sh status    # server + funnel state (shows https://<machine>.<tailnet>.ts.net)
./home-server.sh logs
./home-server.sh stop      # closes the funnel and stops the server
```

What `start` does, step by step (if you want to run it by hand):

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -e ".[home]"
export HARB_DATABASE_URL=sqlite+aiosqlite:///$PWD/data/harb.db HARB_REDIS_URL=memory:// \
       HARB_JWT_SECRET=<long random> HARB_ADMIN_KEY=<random>
.venv/bin/alembic upgrade head
.venv/bin/python -m app.questions.seed            # idempotent
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8080 --workers 1 --no-access-log
tailscale funnel --bg --https=443 http://localhost:8080
# stop:  tailscale funnel --https=443 off   and stop uvicorn
```

- The server only listens on `127.0.0.1`; Funnel is the only way in from outside. Funnel serves
  HTTPS and WebSockets (`wss://<machine>.<tailnet>.ts.net/ws`).
- **One worker only** in home mode: rooms live in that process. (For more, use Docker + Redis.)
- `backend/data/home.env` is created on first start with a random JWT secret and admin key. Keep it:
  a new secret logs every device out (they get a new token automatically from `POST /auth/guest`).
- Back up `backend/data/harb.db` to keep players, stats and results.
- `HARB_PORT=9000 ./home-server.sh start` changes the local port; `HARB_FUNNEL_PORT=8443` the public one
  (Funnel allows 443, 8443 and 10000).

Check from anywhere: `curl https://<machine>.<tailnet>.ts.net/health`.

## Endpoints

- WebSocket `/ws` (rooms, live matches) and REST — every message: [`docs/PROTOCOL.md`](../docs/PROTOCOL.md).
- Offline-first: `POST /sync`, `GET /questions?since=`, `GET /leaderboard`, `GET /me/stats`,
  `POST /auth/account`, `POST /auth/restore`, `GET /health`.
- Question admin (`X-Admin-Key`): `/admin/questions…` (import CSV/JSON, review, edit, delete).

## Layout

```
app/engine/     pure game rules (no I/O)
app/rooms/      room actors, WebSocket hub, matchmaker, Redis bus
app/questions/  question bank, seed (304 Arabic questions), packs
app/sync/       offline sync (actions, grading, anti-cheat), accounts, results → leaderboard
app/api/        REST routers
app/models/     SQLAlchemy models;  alembic/ migrations (PostgreSQL and SQLite)
maps/           map templates;  scripts/fake_clients.py  fake players for load tests
```

## Development

```bash
cd backend && pip install -e ".[dev]" && pytest -W error   # needs redis-server and PostgreSQL binaries
ruff check .
python -m scripts.fake_clients --url http://localhost:8080 --players 8   # a full match with fake players
```
