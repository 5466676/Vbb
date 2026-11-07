# PROTOCOL — WebSocket messages

Every message the client or the server sends is listed here. Update this file with every
protocol change. Payload fields are JSON; `seat` is the 0-based seat index of a player in the match.

## Connecting

1. `POST /auth/guest` `{"device_id": "<8–128 chars>", "name": "<optional, ≤24>"}`
   → `{"token", "player_id", "name"}`. The same device always gets the same `player_id` (stored in
   PostgreSQL); a login without `name` keeps the stored name.
2. Open `ws://<host>/ws` with the header `Authorization: Bearer <token>`
   (`?token=<token>` also works but ends up in access logs; avoid it).
   - Close code **4401**: bad or expired token. Close code **4001**: the same player opened a newer connection.
3. The server sends `welcome`. If the player is already in a room (reconnect), the server also
   sends `full_state` right away.

## Envelope

```json
{ "type": "answer", "seq": 17, "payload": { } }
```

- `seq` from the **client** must increase; an old or repeated `seq` is rejected (`duplicate`).
- `seq` from the **server** increases by 1 per message on this connection.
- `payload` is an object (may be empty).

## Timing and fairness

- The server never sends the correct answer before the question is resolved (`question_result`).
- Answer time is measured **by the server** from the moment it wrote `question` to this socket
  until the `answer` arrives (plus ≤150 ms grace). Clients do not report times.
- MCQ options are shuffled **per player**. Indices in `question`, `answer`, `question_result`
  and `powerup_result.removed` are always in **the receiving player's own order**.
- `phase_changed.opens_in_ms` is a pause for animations (reveal, claim, battle scene) before the
  window really opens; `deadline_ms` is the window length after that. Phases end early when everyone
  involved has acted.
- Rate limit: about 15 messages/second with bursts of 40 per connection (`rate_limited`).

## Client → server

| type | payload | notes |
|---|---|---|
| `ping` | `{"t"?: any}` | → `pong` |
| `resync` | `{}` | in a room: → `full_state` (the client lost track, e.g. after the app was paused) |
| `create_room` | `{"army"?: Army}` | creates a private room; you are the host → `room_state` |
| `join_room` | `{"code": "K7Q2MX", "army"?: Army}` | → `room_state` or `error` (`no_room`, `full`, `started`, `already_in_room`) |
| `leave_room` | `{}` | lobby: frees the seat. Match: a bot keeps your seat, no penalty → `left_room` |
| `quick_match` | `{"mode": "ffa"\|"teams", "size": 2–8 (teams: 4/6/8), "army"?: Army}` | → `queued`, later `match_found` |
| `cancel_quick_match` | `{}` | → `quick_match_cancelled` |
| `set_ready` | `{"ready": bool}` | lobby |
| `choose_army` | `{"army": Army}` | lobby |
| `vote_map` | `{"kind": "fantasy"\|"world"}` | lobby; majority wins, ties at random |
| `update_settings` | `{"mode"?, "max_players"?, "battle_rounds"?, "bots_allowed"?, "categories"?: [str], "packs"?: [str]}` | host, lobby. `categories` ⊂ the 23 categories (`CATEGORIES` in `app/models/question.py`; empty = all); `packs` 1–5 question packs (default `["general"]`, never `solo`) |
| `add_bot` | `{"difficulty": "easy"\|"medium"\|"hard"}` | host, lobby |
| `remove_bot` | `{"seat": int}` | host, lobby |
| `start_match` | `{}` | host; needs ≥2 seats, every human ready; teams need 4/6/8 |
| `answer` | `{"question_id": str, "choice": 0–3}` or `{"question_id": str, "value": number}` | only while the question is open; one answer per question |
| `pick_territory` | `{"territories": [id, …]}` | expansion picks; illegal or taken picks are replaced by auto-picks |
| `choose_target` | `{"territory": id}` | your battle turn; must be one of `phase_changed.targets` |
| `use_powerup` | `{"powerup": "remove_two"\|"hint"\|"shield"\|"double", "territory"?: id}` | `shield` needs one of your territories |
| `use_ability` | `{"territory"?: id}` | your army's once-per-match ability (`pharaoh` needs a territory) |

`Army` = `islamic | ayyubid | crusader | roman | pharaoh | mongol | ottoman | ww2`.

## Server → client

### Connection and lobby

| type | payload |
|---|---|
| `welcome` | `{"player_id", "name", "server_time_ms"}` |
| `pong` | `{"t", "server_time_ms"}` |
| `error` | `{"code", "message", "ref"?: client seq}` — see error codes below |
| `queued` | `{"mode", "size"}` |
| `quick_match_cancelled` | `{}` |
| `match_found` | `{"code"}` — you are already seated; the room starts by itself |
| `room_state` | `{"code", "host", "status": lobby\|playing\|ended, "settings", "seats": [{"seat", "player_id"\|null, "name", "army", "ready", "bot"\|null, "connected"}], "votes": {player_id: kind}, "quick"}` |
| `left_room` | `{"code"}` |

### Match

| type | payload |
|---|---|
| `match_started` | `{"map_id", "map_kind", "mode", "rounds", "base_towers", "players": [{"seat", "name", "army", "team", "bot"}], "bases": [territory per seat]}` — the client loads the map template `map_id` |
| `phase_changed` | `{"phase", "phase_id", "opens_in_ms", "deadline_ms"?, …}` — see phases below |
| `question` | `{"id", "kind": mcq\|numeric, "text", "unit", "category", "options" (your order, MCQ only), "participant", "participants": [seat], "time_ms", "phase_id"}` — **no answer**. Non-participants get it as spectators. |
| `answer_locked` | `{"seat"}` — someone answered (no content) |
| `question_result` | `{"id", "correct_index" (your order) or "answer", "ranking": [seat], "answers": {seat: {"choice" (your order) \| "value", "elapsed_ms"}}}` |
| `pick_locked` | `{"seat"}` |
| `territory_claimed` | `{"seat", "territory", "auto", "value"}` |
| `battle_started` | `{"rounds"}` |
| `round_started` | `{"round", "order"}` — `order`: this round's attackers (seats) in turn order; eliminated players and extra turns are not listed |
| `turn_skipped` | `{"seat"}` — the attacker had no legal target |
| `target_chosen` | `{"attacker", "defender", "territory", "auto"}` |
| `shield_blocked` | `{"territory", "defender"}` — no question; the turn ends |
| `tie_won_by_ability` | `{"seat"}` |
| `territory_captured` | `{"territory", "attacker", "defender", "value"}` |
| `territory_held` | `{"territory", "defender", "value"}` |
| `tower_hit` | `{"territory", "towers", "attacker"}` |
| `base_guarded` | `{"territory", "defender"}` |
| `player_eliminated` | `{"seat", "by", "territories": [id]}` — all of them now belong to `by` |
| `battle_result` | `{"attacker_won", "tiebreak", "territory"}` — one per duel |
| `extra_turn` | `{"seat"}` |
| `powerup_used` | `{"seat", "powerup"}` (public) |
| `powerup_result` | private: `{"powerup": "remove_two", "removed": [i, j]}` · `{"powerup": "hint", "low", "high"}` · `{"powerup": "shield", "territory"}` |
| `ability_used` | `{"seat", "army", "territory"?}` |
| `player_connection` | `{"seat", "connected"}` — while disconnected a bot plays the seat |
| `match_ended` | `{"winner_team", "standings": [{"seat", "team", "score", "correct", "avg_answer_ms", "eliminated"}], "team_scores": {team: score}}` |
| `full_state` | on (re)connect — see below |

### Phases (`phase_changed.phase`)

| phase | extra fields |
|---|---|
| `expansion_question` | `expansion_round` (a `question` follows) |
| `expansion_picks` | `quota: {seat: picks}`, `ranking`, `deadline_ms` (≈5 s) |
| `battle_target` | `attacker`, `round`, `targets: [id]`, `deadline_ms` (≈8 s) |
| `battle_duel` | `attacker`, `defender`, `territory` (an MCQ follows, only these two answer) |
| `battle_tiebreak` | `attacker`, `defender`, `territory` (a numeric question follows) |
| `results` | — (`match_ended` follows) |

### `full_state`

```json
{
  "room": { "...same as room_state..." },
  "match": null | {
    "map_id", "map_kind", "phase", "phase_id", "deadline_in_ms",
    "expansion_round", "battle_round", "rounds", "base_towers",
    "attacker", "round_order": [seats], "duel": {"attacker", "defender", "territory"} | null,
    "pick_quota": {seat: n}, "your_seat",
    "territories": [{"id", "owner", "value", "is_base", "towers", "shielded" (own team only)}],
    "players": [{"seat", "name", "army", "team", "score", "eliminated", "connected",
                 "ability_used", "powerups": [names] for you | count for others}],
    "question": null | {"id", "kind", "text", "unit", "options", "participant", "participants",
                        "answered", "time_ms", "elapsed_ms"},
    "winner_team", "standings" (after the end)
  }
}
```

## Error codes

`bad_frame`, `bad_type`, `duplicate` (seq), `rate_limited`, `not_in_room`, `already_in_room`,
`no_room`, `full`, `started`, `not_host`, `not_ready`, `too_few`, `teams_size`, `bad_army`,
`bad_map`, `bad_settings`, `no_bots`, `bad_bot`, `bad_seat`, `bad_queue`, `not_playing`, `left`,
`no_question`, `bad_answer`, `bad_powerup`, `rule` (the game rules refused the action; `message` says why),
`internal`.

## Offline-first REST (home server and Docker)

Auth: `Authorization: Bearer <token>` from `POST /auth/guest` (the device sends its own UUID v4 as
`device_id`). The player is **always** taken from the token, never from the body.

| call | auth | body / query → response |
|---|---|---|
| `GET /health` | – | `{"status": "ok", "version", "server_time_ms"}` — cheap "is the server on?" check |
| `GET /questions?since=<version>&limit=≤1000` | – | `{"version", "more", "items": [question]}` — offline (solo-pack) questions changed after `since`, in version order. Keep the returned `version`; repeat while `more`. |
| `POST /sync` | token | `{"actions": [action, ≤500], "questions_since"?: int}` → `{"results": [{"id", "status", "reason"?, "correct"?, "points"?}], "stats", "server_time", "questions"? }` |
| `GET /me/stats` | token | `stats` |
| `GET /leaderboard?period=all\|week&limit=≤200` | optional token | `{"period", "rows": [{"rank", "player", "name", "matches", "wins", "score"}], "me"?}` |
| `POST /auth/account` | token | `{"username": 3–20 letters/digits/_, "pin": 4–8 digits}` → `{"username"}` (lower-cased). 409 `username_taken` |
| `POST /auth/restore` | – | `{"username", "pin", "device_id"}` → `{"token", "player_id", "name"}`; this device now owns the account. 401 `bad_login`, 429 `locked` |

**question** = `{"id": "q12", "version", "deleted": false, "kind": "mcq"|"numeric", "category",
"difficulty", "text", "options" (MCQ, stored order), "correct_index" (MCQ), "answer" (numeric), "unit"}`,
or a tombstone `{"id", "version", "deleted": true}` — remove it from the device.
These questions are offline-only: rooms never use the solo pack, so knowing them does not help online.

**action** (stored on the device first, in `pending_actions`):

```json
{"id": "<uuid v4>", "type": "answer", "ts": "2026-11-07T18:03:12.512+03:00",
 "session_id": "<uuid v4 of the solo round>", "question_id": "q12",
 "choice": 2,            // MCQ, index in the stored option order
 "value": 1453,          // numeric
 "elapsed_ms": 5230}
{"id": "<uuid>", "type": "session_end", "ts": "…", "session_id": "<uuid>"}
```

Any other field (a score, "correct"…) is ignored: the server grades answers itself
(10 points for a right answer; numeric within 10 % gives 5).

**result status:** `ok` (stored now), `duplicate` (this id was already stored — a repeated sync),
`rejected` with `reason`: `invalid` (does not parse), `future_ts` (> 5 min ahead), `too_old` (> 60 days),
`unknown_question` (not an offline question), `too_fast` (< 400 ms), `bad_elapsed` (> 120 s),
`too_frequent` (< 400 ms after another answer), `repeat_in_session`, `daily_cap` (2,000 answers/day),
`bad_choice`, `bad_value`, `id_conflict` (another player owns this id).
**The device deletes every action that comes back with any status**; only a failed request is retried.

**stats** = `{"solo": {"answered", "correct", "points", "sessions", "accuracy"},
"online": {"matches", "wins", "score"}}`. The leaderboard counts online matches with ≥ 2 humans only
(offline answers can be faked on a device; bots can be farmed).

## Admin REST (question bank)

Not used by the game client. Every call needs the header `X-Admin-Key` (setting `HARB_ADMIN_KEY`).

| call | notes |
|---|---|
| `POST /admin/questions/import?pack=&source=&license=&reviewed=` | body: JSON list of questions → `{"inserted", "duplicates", "errors": [{"row", "error"}]}` |
| `POST /admin/questions/import-file?…` | multipart `file`: `.json` or `.csv` (header `type,category,difficulty,text_ar,option_1..option_4,correct_index,numeric_answer,unit_ar,source`), ≤ 5 MB |
| `GET /admin/questions?pack=&category=&type=&reviewed=&offset=&limit=` | `{"total", "items"}` |
| `GET /admin/questions/stats` | counts per pack / category / type / reviewed |
| `PATCH /admin/questions/{id}` | any question field, or `reviewed`; invalid result → 422 |
| `DELETE /admin/questions/{id}` | 204 — kept as a tombstone so devices drop it on their next download |

## Names compared with the brief

The brief's `picks_open` and `targets_open` are `phase_changed` with phase `expansion_picks` /
`battle_target`; `battle_results` is one `battle_result` per duel (battles are turn-based now).
