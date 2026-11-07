# CLAUDE.md — حرب العقول

Real-time multiplayer Arabic trivia + territory-conquest game for **Android**.
2–8 players, FFA and team modes, landscape. Each player picks an army from a different era
(look + small perks). Expansion is simultaneous (everyone answers the same question);
battle is turn-based duels (attacker vs defender). Illustrated old-map style.
Target match length 8–12 minutes.

## Source of truth
- `docs/GAME_RULES.md` — authoritative rules. Do not change rules without asking the owner.
- `docs/PROTOCOL.md` — every WebSocket message. Update it with every protocol change.
- `docs/DECISIONS.md` — append an entry after every phase.

## Stack (fixed — ask before changing)
- `backend/`: Python 3.12, FastAPI, native WebSockets, Pydantic v2, Redis, PostgreSQL
  (SQLAlchemy 2 async + Alembic).
- `app/`: Flutter (Android only), Riverpod, go_router, web_socket_channel, CustomPainter map.

## Layout
- `backend/app/engine/` — **pure** game logic: `apply(state, action) -> (new_state, events)`.
  No I/O, no clocks, no global random. Seeded RNG lives in `MatchState`.
- `backend/app/rooms/` — room lifecycle, timers, Redis, WebSocket hub. Timers send `Timeout` actions.
  One room = one actor on the worker holding the room lease; any worker can host sockets.
- `backend/app/api/` — REST. `backend/app/models/` — DB models.
- `backend/app/questions/` — question bank. `backend/app/bots/` — bot players.
- `backend/maps/` — map templates (JSON) + generator.

## Commands
```bash
# backend
cd backend && pip install -e ".[dev]" && pytest -W error
ruff check backend
# map templates (offline; needs the maps extra)
cd backend && pip install -e ".[maps]" && python -m maps.generate --preview /tmp/maps
# full stack
docker compose up --build        # then: curl localhost:8000/health
cd backend && python -m scripts.fake_clients --url http://localhost:8000 --players 8   # 8 fake players, full match
# app
cd app && flutter pub get && flutter analyze && flutter test
flutter build apk --split-per-abi
```

## Conventions
- Server is authoritative. The client never decides results; UI state comes from server events.
- Never send the correct answer before the deadline.
- No gambling: gold is earned by playing and buys cosmetics only. No wagering, ever.
- Arabic-first, RTL everywhere. User-facing strings are Arabic; code, comments and docs are English.
- Low-end Android: no blur on the map, cache map paths, repaint only what changes.
- After each phase: tests pass → commit → `DECISIONS.md` entry.
