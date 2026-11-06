# PROTOCOL — WebSocket messages

> Status: **skeleton.** Payloads are filled in during phase 4 (rooms & protocol).
> Every message the server or client sends must be documented here.

## Envelope

```json
{ "type": "question", "seq": 42, "payload": { } }
```

- `type` — message name (snake_case).
- `seq` — per-connection sequence number, increasing by 1 per message from the sender.
- `payload` — message-specific object.

## Client → server

| type | purpose |
|---|---|
| `join_room` | join a room by code or via quick match |
| `leave_room` | leave the current room |
| `set_ready` | toggle ready in the lobby |
| `start_match` | host only: start the match |
| `answer` | answer the current question |
| `pick_territory` | claim territory during expansion |
| `choose_target` | attacker picks the target territory on their battle turn |
| `choose_army` | pick an army in the lobby |
| `vote_map` | vote for a map type in the lobby |
| `use_powerup` | use a power-up (remove two, hint, shield, double) |
| `use_ability` | use the army's once-per-match ability |
| `ping` | keep-alive / latency measurement |

## Server → client

| type | purpose |
|---|---|
| `room_state` | lobby state (players, settings, ready flags) |
| `match_started` | match begins: map, seats, colours |
| `phase_changed` | phase transition |
| `question` | a question **without** the answer, with deadline |
| `answer_locked` | a player has answered (no content revealed) |
| `question_result` | correct answer + rankings |
| `picks_open` | expansion pick window opened |
| `territory_claimed` | territory claimed in expansion |
| `turn_started` | a battle turn begins: attacker, deadline |
| `target_chosen` | attacker chose a target; defender is known |
| `powerup_used` | a player used a power-up (public effects only) |
| `ability_used` | a player used their army ability |
| `battle_result` | result of one duel: winner, territory change, tower hit |
| `player_eliminated` | a player was eliminated |
| `match_ended` | final scores and winner |
| `full_state` | full match state (on reconnect) |
| `error` | error with code and message |
