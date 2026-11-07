"""WebSocket envelope and message names (see docs/PROTOCOL.md).

Every frame is JSON: ``{"type": str, "seq": int, "payload": {...}}``.
"""

from __future__ import annotations

import json
from typing import Any

from pydantic import BaseModel, Field

# client -> server
CLIENT_TYPES = {
    "ping",
    "create_room",
    "join_room",
    "leave_room",
    "quick_match",
    "cancel_quick_match",
    "set_ready",
    "choose_army",
    "vote_map",
    "update_settings",
    "add_bot",
    "remove_bot",
    "start_match",
    "answer",
    "pick_territory",
    "choose_target",
    "use_powerup",
    "use_ability",
}

# messages the room owner handles (the rest are handled by the connection hub)
ROOM_TYPES = CLIENT_TYPES - {
    "ping",
    "create_room",
    "join_room",
    "quick_match",
    "cancel_quick_match",
}


class Envelope(BaseModel):
    type: str
    seq: int = 0
    payload: dict[str, Any] = Field(default_factory=dict)


def encode(type_: str, seq: int, payload: dict[str, Any] | None = None) -> str:
    return json.dumps({"type": type_, "seq": seq, "payload": payload or {}}, ensure_ascii=False)


def error_payload(code: str, message: str, ref: int | None = None) -> dict[str, Any]:
    out: dict[str, Any] = {"code": code, "message": message}
    if ref is not None:
        out["ref"] = ref
    return out
