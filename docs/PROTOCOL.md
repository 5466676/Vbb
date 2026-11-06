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
| `choose_target` | choose attack target or defend during battle |
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
| `targets_open` | battle targeting window opened |
| `battle_results` | all changes of a battle round |
| `player_eliminated` | a player was eliminated |
| `match_ended` | final scores and winner |
| `full_state` | full match state (on reconnect) |
| `error` | error with code and message |
