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
