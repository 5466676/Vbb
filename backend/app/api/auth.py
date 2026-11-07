"""POST /auth/guest — playable within seconds, no sign-up."""

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from app.auth import create_token, guest_player_id

router = APIRouter(prefix="/auth", tags=["auth"])


class GuestIn(BaseModel):
    device_id: str = Field(min_length=8, max_length=128)
    name: str = Field(default="", max_length=24)


class GuestOut(BaseModel):
    token: str
    player_id: str
    name: str


@router.post("/guest", response_model=GuestOut)
async def guest(body: GuestIn, request: Request) -> GuestOut:
    state = request.app.state
    async with state.sessionmaker() as session:
        pid, stored = await guest_player_id(session, body.device_id, body.name.strip())
    name = stored or f"ضيف {pid[:4]}"
    return GuestOut(token=create_token(state.settings, pid, name), player_id=pid, name=name)
