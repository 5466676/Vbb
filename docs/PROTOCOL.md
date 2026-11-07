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
| `create_room` | `{"army"?: Army}` | creates a private room; you are the host → `room_state` |
| `join_room` | `{"code": "K7Q2MX", "army"?: Army}` | → `room_state` or `error` (`no_room`, `full`, `started`, `already_in_room`) |
| `leave_room` | `{}` | lobby: frees the seat. Match: a bot keeps your seat, no penalty → `left_room` |
| `quick_match` | `{"mode": "ffa"\|"teams", "size": 2–8 (teams: 4/6/8), "army"?: Army}` | → `queued`, later `match_found` |
| `cancel_quick_match` | `{}` | → `quick_match_cancelled` |
| `set_ready` | `{"ready": bool}` | lobby |
| `choose_army` | `{"army": Army}` | lobby |
| `vote_map` | `{"kind": "fantasy"\|"world"}` | lobby; majority wins, ties at random |
| `update_settings` | `{"mode"?, "max_players"?, "battle_rounds"?, "bots_allowed"?, "categories"?: [str], "packs"?: [str]}` | host, lobby. `categories` ⊂ the 8 categories (empty = all); `packs` 1–5 question packs (default `["general"]`) |
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
| `question` | `{"id", "kind": mcq\|numeric, "text", "unit", "options" (your order, MCQ only), "participant", "participants": [seat], "time_ms", "phase_id"}` — **no answer**. Non-participants get it as spectators. |
| `answer_locked` | `{"seat"}` — someone answered (no content) |
| `question_result` | `{"id", "correct_index" (your order) or "answer", "ranking": [seat], "answers": {seat: {"choice" (your order) \| "value", "elapsed_ms"}}}` |
| `pick_locked` | `{"seat"}` |
| `territory_claimed` | `{"seat", "territory", "auto"}` |
| `battle_started` | `{"rounds"}` |
| `round_started` | `{"round"}` |
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
    "attacker", "duel": {"attacker", "defender", "territory"} | null,
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

## Admin REST (question bank)

Not used by the game client. Every call needs the header `X-Admin-Key` (setting `HARB_ADMIN_KEY`).

| call | notes |
|---|---|
| `POST /admin/questions/import?pack=&source=&license=&reviewed=` | body: JSON list of questions → `{"inserted", "duplicates", "errors": [{"row", "error"}]}` |
| `POST /admin/questions/import-file?…` | multipart `file`: `.json` or `.csv` (header `type,category,difficulty,text_ar,option_1..option_4,correct_index,numeric_answer,unit_ar,source`), ≤ 5 MB |
| `GET /admin/questions?pack=&category=&type=&reviewed=&offset=&limit=` | `{"total", "items"}` |
| `GET /admin/questions/stats` | counts per pack / category / type / reviewed |
| `PATCH /admin/questions/{id}` | any question field, or `reviewed`; invalid result → 422 |
| `DELETE /admin/questions/{id}` | 204 |

## Names compared with the brief

The brief's `picks_open` and `targets_open` are `phase_changed` with phase `expansion_picks` /
`battle_target`; `battle_results` is one `battle_result` per duel (battles are turn-based now).
