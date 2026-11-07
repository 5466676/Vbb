# DECISIONS

Append-only log. Newest entry at the bottom. Each phase adds one entry.

---

## Phase 0 — Planning (2026-11-06)

Answers to the open questions in the brief, agreed with the owner:

1. **Platform: Android only.** The Flutter project is created with the Android platform only.
   iOS can be added later from the same code base (needs a Mac and an Apple developer account).
2. **Stay on Flutter** (not native Kotlin, not Unity). Reasons: Flutter compiles to native ARM and
   renders with Impeller, which is plenty for a 2D map; Arabic text shaping and RTL work out of the box
   (Unity needs plugins); half the app is regular UI (lobby, profile, leaderboards); and everything is
   code, so it can be built and tested without an editor. If the match screen needs more game feel,
   consider the Flame package in phase 6/7.
3. **Expansion picks are simultaneous,** not sequential. Conflicts go to the better-ranked player;
   the loser gets an auto-pick. Keeps rounds short and matches the "nobody waits" goal.
4. **Top half = ceil(players / 2).**
5. **Base fall order:** normal captures resolve first; then the base taker receives the base plus
   everything the eliminated player still owns.
6. **Score = territory values + bonus points** (e.g. +50 for a correct defender).
7. **Teams are supported in the engine from phase 2** (cheap there, and the 500-match simulation
   covers every mode). Team UI, leaderboards and progression stay in phase 8.
8. **Battle rounds for small matches:** default R = 6 / 5 / 4 / 3 for 2 / 3 / 4 / 5–8 players
   (brief: 4 for 2–4, 3 for 5–8). With the brief's values a 2-player match lasts roughly 4–5 minutes,
   below the 8–12 minute goal. R stays a host setting. The phase-2 simulation will measure real
   durations and these defaults may be tuned.

## Phase 1 — Scaffold (2026-11-06)

- **Layout** as in the brief: `backend/`, `app/`, `docs/`, `CLAUDE.md`, `docker-compose.yml`.
- **Backend:** FastAPI app factory (`app/main.py`), `/health` endpoint, settings via
  pydantic-settings with the `HARB_` prefix. Empty packages `engine/ rooms/ api/ models/ questions/ bots/`
  carry docstrings that state their rules (engine is pure).
- **Python packaging:** `pyproject.toml` with extras `dev` (tests, ruff) and `maps` (numpy, scipy,
  used only by the offline map generator, not installed in the API image).
- **Tests** use `httpx.AsyncClient` + `ASGITransport` instead of Starlette's `TestClient`
  (deprecated with plain httpx in current Starlette). `pytest -W error` is clean.
- **Docker Compose:** api + redis 7 + postgres 16 with health checks; the api waits for both.
  Verified locally: all three containers healthy and `/health` returns ok.
- **Flutter:** latest stable (3.47.9 / Dart 3.13.7), Android only, package `com.harbaloqool`.
  Riverpod 3, go_router, web_socket_channel. Arabic locale and RTL forced at the app root.
  **Cairo variable font bundled** in `app/assets/fonts` (OFL licence included) instead of the
  `google_fonts` package, so the app works offline and does not download fonts on low-end phones.
- **Theme:** dark, teal accent `#2DD4BF`, glass tokens. `GlassPanel` widget has an optional
  blur and is documented as "never on the map".
- **Not yet verified on a device**: no Android SDK/emulator in the dev container. Build an APK
  locally with `flutter build apk --split-per-abi`.

## Phase 1b — Direction change after design review (2026-11-06)

The owner rejected the first UI mockup (flat dark "app" look) and reshaped the game.
`GAME_RULES.md` was rewritten accordingly. Changes against the original brief:

1. **Look:** illustrated old-map style (parchment land, thick brown borders, teal sea, shields on
   territories, framed commander portraits, flags in seat colours). **Landscape** orientation.
   We follow the style only; no art or layout is copied from any existing game.
   The dark-teal theme from phase 1 is superseded and will be replaced in phase 6.
2. **Armies:** every player picks an army from a different era. Launch set of 8 (Islamic conquests,
   Ayyubids, Crusaders, Romans, Pharaohs, Mongols, Ottomans, WW2 with generic uniforms).
   Each army has its own commander, base art and soldiers, plus a small passive perk and a
   once-per-match active ability (draft values in GAME_RULES §2.1, tuned in phase 2).
   Some armies are free, the rest unlock with earned gold. No present-day armies, no Nazi symbols.
3. **Battle is turn-based** (hybrid): expansion stays simultaneous for everyone; in battle each player
   gets one turn per round and attacks one territory, and only attacker and defender answer.
   Battle rounds per player count changed to 7/5/4/3/3/2/2 for 2…8 players so matches stay near 8–12 min.
   The brief's "+50 for defending" rule is dropped (there is no defend choice in turn-based battle).
4. **Power-ups:** remove two answers, numeric hint, shield, double gain. One of each per match for
   every player; never bought (keeps the "gold buys cosmetics only" rule).
5. **Maps:** fantasy + real (World, Arab world, Levant) + historical. Chosen by player vote in the lobby.
   Real maps group real regions into `players × 5` territories.
6. **Interactive map:** pinch-zoom/pan/tap, armies marching on attack, a short battle scene, and
   ambient animation (waves, ships, flags, smoke). This makes the Flame engine (on top of Flutter)
   the likely choice for the match screen; to be decided at the start of phase 6.
7. **Art:** the map itself is drawn in code (cheap on low-end phones). Commander portraits, castles and
   soldiers come from AI-generated images, with simple placeholders until they are ready.

### Update — all armies free (2026-11-06)
The owner decided that **every army is free** from the start. Gold still buys other cosmetics only
(frames, map themes, victory effects). Replaces "some armies unlock with gold" in item 2 above.

## Phase 1c — Art pipeline (2026-11-06)

- **Army art:** commanders generated in Canva (style-matched to one reference portrait);
  forts generated in Gemini by the owner. Backgrounds removed locally; stored as 512px PNG in
  `app/assets/armies/`. Preferred style going forward: ink line + soft watercolour (matches the map).
  No present-day national symbols: the Ottoman image's crescent flag was removed; the game draws
  the seat-colour flag on each fort.
- **Maps = fixed coastline + painted base + generated territories.** Every template has a land mask
  (`backend/maps/shapes/`). The owner paints it in Gemini from a guide image; Gemini kept the
  coastline within a few pixels on the first test, and the client clips the painting to the mask.
  Territory borders, owner colours, shields and castles are always drawn in code on top.
- **Decorations:** a Gemini sprite sheet (16 items) cut into `app/assets/decor/painted/`;
  Kenney Cartography (CC0) kept as a fallback.

### Update — art set closed (2026-11-06)
- Maps: fantasy 2p–8p and the real World map are painted and checked against their coastlines.
  The 5-player coastline was updated to follow the bay Gemini painted.
- **Dropped by the owner:** Arab world, Levant and historical maps (removed from GAME_RULES §3);
  the extra art requests (Crusader/Roman forts in ink style, new Islamic soldiers, full-size commanders).
  We ship the Canva versions of the Crusader and Roman forts and the eight commanders (200 px previews,
  enough for the small UI slots; replace if larger art is wanted later).

## Phase 2 — Engine (2026-11-06)

**Built:** `backend/app/engine/` — `create_match`, `apply(state, action) -> (state, events)` and
`apply_inplace`; Pydantic `MatchState`; SplitMix64 RNG stored in the state; ranking; all of
GAME_RULES §2–§8 (expansion, turn-based battle, towers, elimination, teams, the 8 armies' perks and
abilities, the 4 power-ups). `backend/app/bots/simple.py`: bots (easy/medium/hard + seat keeper for
disconnects) with their own RNG.

**Engine contract for the room layer (phase 4):**
- The engine asks for questions with a `question_needed` event; the room replies with `ProvideQuestion`.
  The `question` event never contains the answer; answers come out only in `question_result`.
- Every phase change increments `phase_id`. The room schedules a `Timeout(phase_id)` for the deadline;
  a stale timeout is ignored. Phases end early when everyone involved has acted.
- Illegal actions raise `RuleError` and leave the state unchanged.
- Answer times (`elapsed_ms`) are measured by the room and validated against per-seat limits + 150 ms.

**Rule clarifications made while implementing (GAME_RULES updated):**
1. The attacker must answer correctly to win a duel. The brief's "rank above the defender" would let a
   fast wrong answer beat a slower wrong one or silence, which rewards guessing.
2. Tiebreak draws and double silence favour the defender; opposing tie abilities cancel.
3. A shield block asks no question and changes no value.

**Simulation (`tests/test_simulation.py`):** 500 bot matches for each of FFA 2–8 and teams 2v2/3v3/4v4
(5,000 matches, ~100 s), invariants checked after every action, every 7th action through the copying
`apply`. The wall-clock model uses the real timers plus 2.5 s reveal, 1.5 s claim and 3.5 s duel
animations; bots answer in 1.5–9.5 s.

Battle rounds were re-tuned from 7/5/4/3/3/2/2 to **12/12/9/8/6/5/4** (2…8 players):

| Mode | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 2v2 | 3v3 | 4v4 |
|---|---|---|---|---|---|---|---|---|---|---|
| Mean length (min) | 4.9 | 7.8 | 9.0 | 10.0 | 9.7 | 9.7 | 9.5 | 8.5 | 9.6 | 9.4 |
| Matches in 8–12 min | 0% | 41% | 80% | 95% | 98% | 99% | 99% | 61% | 94% | 98% |

**Open question for the owner:** 2–3 player matches end early because a base (3 towers) falls quickly
on small maps. Simulation of alternatives: 5 towers for 3–4 players brings them to 88–98% inside 8–12 min;
a 1v1 cannot reliably reach 8 min without making bases much harder to take.

**Army balance (3,000 four-player bot matches, fair = 25%):** ayyubid 26, crusader 29, islamic 23,
mongol 25, ottoman 25, pharaoh 24, roman 25, ww2 23 (%). Within the test bound (15–37.5%); crusader is
slightly strong and is the first candidate for tuning once real players exist.

### Update — owner decisions after phase 2 (2026-11-07)
1. **Confirmed:** the attacker must answer correctly to win a duel.
2. **Bases have 5 towers in 2–4 player matches** (3 towers with 5–8). Battle rounds re-tuned to
   **19/13/9/8/6/5/4**. Simulation (200 matches each): 1v1 mean 7.7 min (50% in 8–12 — a 1v1 often
   ends by elimination, accepted), 3 players 9.6 (90%), 4 players 9.9 (99%), 2v2 9.7 (90%);
   5–8 players unchanged (95–99%). `MatchSettings.base_towers` overrides the default.

## Phase 3 — Maps (2026-11-07)

**Built:** `backend/maps/generate.py` (offline) turns each painted map into a template
`backend/maps/templates/<id>.json`: `fantasy-2p … fantasy-8p` and `world-2p … world-8p` (14 templates, 264 KB).
`backend/app/maps.py` loads templates, converts them to the engine's `MapDef` and validates them.

**How a template is made:**
1. Land mask from `backend/maps/shapes/` (the 4-player continent is rebuilt from the mockup coastline).
2. Land masses smaller than 35% of an average territory are scenery; the rest share `players × 5`
   territories in proportion to their area.
3. Each land mass is split by a geodesic k-means (regions grow along the land, so they are always
   connected and follow bays and lakes), then balanced by adjusting each region's growth speed.
   Size spread (largest / smallest): fantasy 1.2–2.0×, world 1.3–3.2× (real continents differ).
4. Neighbours = shared border; separate land masses are joined by sea routes (minimum spanning tree
   plus any very close pairs). Each route stores its two nearest coastal points for drawing.
5. Bases: maximise the minimum hop distance, then balance how much land is closest to each base;
   listed west → east so in team modes team 0 starts in the west.
6. Validation (also in tests): N territories, symmetric links, connected graph, bases not adjacent,
   size spread ≤ 4× (fantasy) / 8× (world), polygons inside [0,1], label point inside its polygon.

**Coordinates** are normalised to the painting (x, y ∈ [0, 1]); each template stores the painting's
`aspect`. The client will draw the painting over the map rectangle and the polygons on top.
The client gets the same template files in phase 6 (the server only sends the template id).

**World map** territories are a geometric split of the continents, not country borders.

**Bot matches on the real templates** (150 each, mean minutes, share in 8–12 min):

| | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|
| fantasy | 7.5 (48%) | 9.9 (93%) | 10.0 (100%) | 10.0 (97%) | 9.7 (99%) | 9.7 (99%) | 9.5 (100%) |
| world | 8.3 (57%) | 10.2 (97%) | 10.1 (100%) | 10.4 (95%) | 9.9 (100%) | 9.9 (100%) | 9.6 (99%) |

## Phase 4 — Rooms & protocol (2026-11-07)

**Built:** guest JWT (`POST /auth/guest`, device → player id in Redis until phase 5), `/ws` endpoint,
room actor, connection hub, Redis pub/sub bus, quick-match matchmaker, a sample question provider
(25 MCQ + 15 numeric, replaced by the database bank in phase 5), `scripts/fake_clients.py`,
and `docs/PROTOCOL.md` (every message).

**Architecture (several workers share rooms through Redis):**
- A room is one JSON record (`room:{code}`) written only by its **actor**, which runs on the worker
  holding the lease `room:{code}:owner` (renewed every 2 s, expires after 6 s).
- Any worker can hold a player's socket. Input goes to the room inbox (a Redis list) plus a
  pub/sub wake-up; output is published on `room:{code}:out` and every worker forwards it to its sockets.
- If a worker dies, its lease expires and a worker that still has players in the room takes the room
  over, reloads the record and re-arms the timers from their stored deadlines (tested).
- Answer time is measured by the hub that holds the socket (monotonic clock, from writing `question`
  to receiving `answer`).
- Disconnect during a match → a seat-keeper bot plays (random answers, auto picks, no extras) until the
  player reconnects and gets `full_state`. In the lobby a disconnected player is removed after 30 s.
- Leaving a match is allowed without penalty; a bot keeps the seat.
- Quick match: queues per mode and size; a full queue starts a room, otherwise medium bots fill the
  seats after 20 s.
- `time_scale` setting multiplies every room-side wait (tests run a full match in seconds).
- Animation pauses before the next window: start 3 s, answer reveal 2.5 s, claims 1.5 s, battle 3.5 s.

**Bugs found by the integration tests and fixed:** login tokens were signed with the global settings
instead of the app's; the engine's own `match_started` was forwarded next to the room's; one bad message
could crash a room (now isolated per message); a refused join left the socket attached to the room.

**Token in logs:** the access log showed `?token=…`. The socket now takes `Authorization: Bearer`
(query string still accepted for simple clients) and the container runs uvicorn with `--no-access-log`.

**Tests:** 14 integration tests over real uvicorn workers and a real redis-server: 8-player match via
room code, per-player shuffle maps back correctly, teams, reconnect with `full_state`, disconnected seat
played by a bot, duplicate/wrong/late answers, rate limit and bad frames, lobby rules, host + bots,
quick match with bot fill, two workers sharing a room, owner worker dying mid-match, guest login,
bad token. 116 tests in total.

**Real-speed check (brief §9.4):** `scripts/fake_clients.py` with 8 fake players against the Docker stack
(api + redis + postgres, time scale 1): full FFA match through a room code in 425 s (7.1 min), 0 errors
on the clients, no exceptions in the server log. The fake players answer at random and early, so real
matches will run longer.

## Phase 5 — Question bank (2026-11-07)

**Built:** PostgreSQL models + Alembic migration (`players`, `questions`, `seen_questions`), guest
login moved from Redis to `players` (same device → same id, stored name kept), the question bank
(`app/questions/bank.py`), the admin API (`/admin/questions…`, `X-Admin-Key`), CSV/JSON import, and
a seed of 304 Arabic questions (38 per category, 8 categories, MCQ + numeric, correct option spread
over all four positions). The Docker image runs `alembic upgrade head` and the seed (idempotent)
before uvicorn.

**Selection per question:** never a question already used in the match; skip questions any human in
the room saw in the last 30 days (`seen_window_days`); rotate difficulty 1/2/3 (least used so far);
if everything was seen, the one these players saw longest ago. Rooms filter by `categories` and
`packs` (`update_settings`). If the bank has nothing for the filters the room falls back to the
built-in sample set, so a match never stalls.

**Review:** imported and seed questions are `reviewed=false`. `HARB_ONLY_REVIEWED_QUESTIONS=true`
serves only reviewed ones (turn it on for production once the bank is reviewed). The seed was written
by us; the owner should review it in the admin API before launch.

**Packs:** each question has a `pack` (`general` by default) plus `source` and `license`. Curriculum
packs (e.g. a school grade) plug in through `app/questions/packs.py` (`PackSource` + `sync_pack`).

**Open question sources checked:**
- EXAMS (Arabic part, ~560 school-exam MCQs) — CC BY-SA 4.0: usable with attribution and the same
  licence; has OCR errors and religious quotations, so it needs review. Candidate for a separate pack.
- ArabicMMLU — CC BY-NC-SA: non-commercial, **not usable**.
- Open Trivia DB — English, CC BY-SA 4.0: would need translation; later maybe.
- Other Arabic sets found were not trivia or had no clear licence.
Decision: our own questions first; any CC BY-SA pack gets a credits screen in the app (phase 7).

**Tests:** seed balance, import validation, duplicates, CSV, anti-repeat window, old views expire,
no repeats in a match, difficulty rotation, category/pack/review filters, admin flow (auth, JSON and
CSV import, list, review, invalid edit, delete), room setting validation. The rooms tests now run on a
real temporary PostgreSQL (template DB migrated once, copied per test). 128 tests in total.

## Home server and offline-first (2026-11-07)

**Owner request:** run the server on the owner's own computer for free, exposed with Tailscale Funnel
(fixed `https://<machine>.<tailnet>.ts.net`, public ports 443/8443/10000), switched on only to play;
offline-first app with a solo mode, sync, leaderboard, account restore.

**Kept Python, not a Dart rewrite (owner agreed):** a rewrite would redo the engine, bots and rooms
(phases 1–5). Instead a *home mode*: `HARB_DATABASE_URL=sqlite+aiosqlite:///…` and
`HARB_REDIS_URL=memory://` (fakeredis inside the process), one uvicorn worker, `./home-server.sh
start|stop|status|logs` (venv + install on first start, migrate, seed, uvicorn on 127.0.0.1:8080,
`tailscale funnel --bg --https=443 http://localhost:8080`). Docker/PostgreSQL/Redis still work the same.
All SQL is portable (`app.db.upsert` picks the dialect; migrations use batch mode on SQLite).
Tests run the new features on both databases.

**Offline questions are a separate pack (`solo`).** A device needs the answers to play offline, so
anything downloaded can be read. Every third seed question per category went to `solo` (≈100);
rooms refuse it, so cached answers never help online. Questions carry a `version` (global counter,
bumped on insert/edit/delete); deletions are tombstones, so `GET /questions?since=` is a clean
incremental download.

**Sync (`POST /sync`):** actions carry a device UUID (primary key → a repeated or parallel sync
counts nothing twice; another player's id is `id_conflict`). The player comes from the token, not
from the body. The server grades answers itself and ignores any score from the client. It rejects
future/old timestamps, answers under 400 ms or over 120 s, two answers under 400 ms apart, a question
repeated in a session, non-solo questions, and more than 2,000 answers a day. Rejected actions are
stored too and every action gets a status, so the device can always empty its queue; one malformed
action never blocks the others. Honest limit: timing on a device can be faked, which is why…

**Leaderboard = online only** (owner agreed): finished matches are saved per human
(`match_results`, unique per match + player, written by the room actor); only matches with ≥ 2
humans count, so wins against bots cannot be farmed. Offline gives personal stats.

**Account restore:** optional username (3–20, case-insensitive) + 4–8 digit PIN, stored as salted
scrypt. 5 wrong PINs lock the name for 15 min, each further 5 double the lock (max a day): guessing
a 4-digit PIN takes years. Restoring moves the account to the new device; the guest player that the
new device had made is detached.

**Still Android only** (owner agreed). **Bug found by the tests:** the lock doubling overflowed
after hundreds of failures; capped.

## Owner's question bank, two new categories (2026-11-07)

The owner writes questions with his own `build_questions.py` (JSON: `categories` + `questions`,
`choice`/`number`). The checker and importer read that format directly
(`app/questions/owner_format.py`), so he keeps his workflow. His categories added two of ours:
**تكنولوجيا** and **حيوانات وطبيعة** (10 categories now); the other eight map onto the existing ones.
First file: 200 questions, all valid; 49 were already in the seed (matched ignoring diacritics and
hamza forms) and were dropped; two were held back because the "right" answer is disputed
(longest river: Nile vs Amazon; number of continents: 6 or 7 depending on the school system).
The other 149 are a second built-in seed file (`seed/owner_v1.json`), split like the first:
every third per category goes to the offline `solo` pack. Bank: 453 questions (305 online, 148 offline).

### Update: the owner's bank becomes the main source (23 categories)

Second file: 1105 questions in 23 categories (a superset of the first). We adopted **his category
names** everywhere; the three old names that differed were renamed in `seed_ar.json` and by
migration 0003 (دين → دين إسلامي, لغة عربية → لغة وأدب, ثقافة عامة → ثقافة وفن).
`scripts/import_owner_bank.py` turns his `questions.json` into `seed/owner_bank.json` (replaces
`owner_v1.json`): 1025 new, 77 already in the first seed, 3 held back (longest river, number of
continents, and a Syria question whose answer is the lake's politically loaded former name).
Bank: 1329 questions, 894 online and 435 offline. Difficulty in his file: 47 % / 41 % / 12 %.

## Phase 6 — Flutter app, first playable version (2026-11-07)

**Built (app/lib):**
- `core/` — settings (shared_preferences: device UUID, server link, name, token), REST client, game
  socket (auto-reconnect with backoff; `full_state` on reconnect), map templates (normalised
  polygons, cached paths, point-in-polygon), sound service (pooled players; the takbir for the three
  Islamic armies, a war cry per other army), local store (sqflite on the phone, memory on web/tests),
  sync service.
- `features/` — home (menu over the 4 painted backgrounds, server check), settings (server link,
  name, volume, account create/restore), lobby (room code, seats, 8 armies with perks and abilities,
  map vote, bots, teams, ready/start), match (map with zoom/pan, territory colours and values, base
  forts and towers, question scroll with timer, picks and targets, power-ups and the army ability,
  side panel with live land totals and an event log, results with victory/defeat art), offline
  training, leaderboard.
- The game state is built only from server events (`features/game/game_controller.dart`).

**Server changes for the client:** `resync` → `full_state` (the app asks after `match_started`,
`battle_started` and `ability_used`, when values change without a per-territory event);
`territory_claimed` now carries `value`; optional `HARB_WEB_DIR` serves the web build at `/play`.

**Server link:** no default yet (the owner's Funnel URL is unknown): first launch asks for it in
Settings, or a `harb://server?url=…` link sets it. Cleartext HTTP is allowed (home network tests).

**Checked:** `flutter analyze` clean; 8 tests (link normalisation, device UUID, sync keeps
unanswered actions and applies tombstones, server-off sync loses nothing, map hit-testing, the
controller builds a match from events, home screen RTL). End to end: the web build on the home-mode
server, driven by Playwright — create room, add 3 bots, ready, start, full match to the results
screen, no console errors. Found and fixed: the menu overflowed a 900×420 landscape phone; the
portrait frame hid the commander's face at small sizes. Release APKs built (arm64 35 MB).
Building needed Google's Maven Central mirror locally (Maven Central rate-limits the shared IP).

**Not yet:** music and the commentator (lines arrive with the Gemini quota), the battle scene
animation, marching armies, team chat, progression and gold (phase 8).

## Offline play against bots (2026-11-07)

Free hosts now ask for a card (Hugging Face Docker Spaces need PRO, Render asks for a card), so the
app can also play with **no server**: `app/lib/local/` ports the engine (`engine.dart`, rule for rule
from `core.py`) and the bots (`bots.dart`), and `LocalGame` runs a room inside the app with the same
timers and pauses as the server's room actor. It implements the same `GameTransport` as the online
socket and speaks the same messages, so every screen works unchanged. Questions come from the
offline pack bundled in the app (`assets/questions/solo.json`, 435 questions); offline training uses
it too when no server was ever reached. Tests: full bot matches for 2–8 players and teams on the
Dart engine, a duel rule test, and a whole `LocalGame` match on a fake clock to `match_ended`.
Checked in the browser build with no server running. Online play (with family) still needs a server:
the home PC (`home-server.sh`) or Render.

## Game look: UI kit, map, battle effects (2026-11-07)

A screen-by-screen review after a full offline match found the game looked like a plain app:
outlined Material buttons, white number pills on the map, no movement when land changed hands, a
question scroll covering a third of the map, tools with no names. Changes, all painted in code
(gradients and paths, no blur, no new bitmaps) so low-end phones keep up:

- **UI kit** (`app/lib/app/ui_kit.dart`): `WarButton` (red wax seal for the main action, walnut
  with a brass rim otherwise, presses in), `WoodPanel`, `ParchmentPanel`, `BannerChoice`, and
  `RuqaaTitle` in **Aref Ruqaa** (OFL, from Google Fonts) for headings only; body text stays Cairo.
  Home menu and the offline setup ("مجلس الحرب": bot portraits with +/−, banner choices) use it.
  The home screen no longer shows "server off" as an error: offline play needs no server.
- **Map** (`map_view.dart`): three layers that repaint separately — ownership (seat wash that is
  strong at the edge, ink borders; repaints only when an owner changes), highlight (choices get
  gold marching-ants borders and everything else dims; ticks only while something is selectable)
  and effects. Values sit on small cloth banners in the owner's colour; bases show one tower and
  ×N. The painting fills the space around the map, darkened, instead of black bars.
- **Battle effects**: the controller records short `Fx` items from server events (the server
  stays authoritative; effects are decoration only): march arrow from the attacker's nearest land
  plus crossed swords on `target_chosen`, a flag planted with the colour spreading out and
  "+value" on `territory_captured`, a shield glint on `territory_held`, a tower falling in dust on
  `tower_hit`, a small flag on `territory_claimed`. A face-to-face splash with both commanders
  opens every duel (1.7 s, does not block input).
- **Question**: the map moves up instead of being covered; participants' portraits with a check
  when each locks in; a brass clock that reddens and beats in the last five seconds; options
  carry أ ب ج د seals.
- **Players and tools**: player cards with land value, territory count, a share bar, attacker /
  defender badges; the log has icons and a heading; tools are named medallions with a count and
  a lock when not usable now.
- **Results**: "نصر!" / "هزيمة", a three-step podium, counting scores, and «مباراة ثانية» for
  offline matches (same bots and map).

## Turn order on screen (2026-11-07)

Players could not tell when their attack turn would come. `round_started` now carries `order`
(this round's attackers in turn order; the rule itself is unchanged, GAME_RULES §6.2) and
`full_state` carries `round_order`, so a reconnecting player sees it too. The match screen shows
a strip under the phase ribbon: portraits in order, the current attacker large and glowing,
finished turns greyed with a check, and for me «دورك بعد N أدوار» / «إنت الجاي!» (with a short
sound when I am next). The offline engine sends the same field.

## Question arena, target reveal, stage signs (2026-11-07)

The owner compared the game with a commercial Arabic trivia-conquest game they enjoyed and found
ours dull. What that genre does better, in short: the question owns the whole screen, number
questions end in a show (arrows on a target), stage changes are announced big, the map is bright and
clear. We keep our own theme, armies and art (nothing copied) and switch to a **bright cartoon**
look, starting with pace:

- **Question arena** (`question_arena.dart`, replaces the parchment panel): fills the battlefield;
  players' swallow-tail flags on both sides (attacker right, defender left in duels) with answered
  checks and rank after the reveal; category chip with an icon; chunky outlined answer buttons that
  show who picked what after the reveal; a phone-style number pad (keyboard works too).
- **Target reveal** for numeric questions: the correct answer sits on the bullseye and each player's
  arrow flies in, landing at a distance from the centre on a square-root scale of the relative error,
  with their value and time.
- **The reveal is now actually seen**: the next stage arrived in the same batch and cleared the
  question at once; the client now keeps a resolved question until `opens_in_ms` (the server's
  existing reveal pause) has passed.
- **Stage signs**: a wooden sign on chains drops for «تقاسم الأرض», «الحرب!», «الجولة N»,
  «تعادل!» and eliminations.
- Protocol: `question` carries `category` (not secret).

## Owner's map and setup requests (2026-11-07)

- **Picks grow outward (rule change, asked by the owner):** GAME_RULES §6.1.5 — with no free
  territory next to your land, only the free territories the fewest steps away are legal (BFS over
  the map), instead of any free territory. Python engine, Dart engine and the client highlight agree.
- **Fixed full-screen map:** no zoom or pan. The painting is scaled so the whole land fits and the
  sea covers as much of the screen as possible; its edges fade into a matching sea colour, so there
  is no visible rectangle. The painting is colour-mapped to the cartoon look (bright blue sea, cream
  land), owners' colours are stronger, borders thicker, and each territory shows its owner's troops.
- **Players on a top strip** (the map gets the full width); the war log is a short toast plus a
  button that opens the whole log.
- **Power-ups only when usable now:** a small row at the bottom appears on your attack turn or in a
  question you are answering (shield and army abilities on your turn; فتح during expansion).
- **Question categories before the match:** a picker with the 23 categories (or all) in the
  offline setup and before creating an online room (sent as the room's `categories` setting).
  Offline, a category set without questions of the needed kind falls back to all categories.
