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
