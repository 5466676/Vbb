"""Offline sync, question downloads, account restore and the leaderboard (home mode).

Every HTTP test runs twice: SQLite + in-process Redis (the home server) and PostgreSQL.
"""

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

import httpx
import pytest

from app.sync import accounts
from scripts.fake_clients import FakeClient, play_room

ADMIN = {"X-Admin-Key": "k"}


def new_id() -> str:
    return str(uuid.uuid4())


async def guest(http: httpx.AsyncClient, device: str | None = None, name: str = "") -> dict:
    r = await http.post("/auth/guest", json={"device_id": device or new_id(), "name": name})
    r.raise_for_status()
    body = r.json()
    body["h"] = {"Authorization": f"Bearer {body['token']}"}
    return body


async def solo_questions(http: httpx.AsyncClient) -> list[dict]:
    items, since = [], 0
    while True:
        page = (await http.get("/questions", params={"since": since, "limit": 40})).json()
        items += page["items"]
        since = page["version"]
        if not page["more"]:
            return [q for q in items if not q["deleted"]]


def answer(q: dict, *, right: bool, ts: datetime, session: str, elapsed: int = 4000) -> dict:
    a = {
        "id": new_id(),
        "type": "answer",
        "ts": ts.isoformat(),
        "session_id": session,
        "question_id": q["id"],
        "elapsed_ms": elapsed,
        # the server must ignore numbers like these
        "correct": True,
        "points": 9999,
    }
    if q["kind"] == "mcq":
        a["choice"] = q["correct_index"] if right else (q["correct_index"] + 1) % 4
    else:
        a["value"] = q["answer"] if right else q["answer"] * 3 + 100
    return a


@pytest.fixture
async def api(home_server):
    url = await home_server(admin_key="k")
    async with httpx.AsyncClient(base_url=url) as http:
        yield http


async def test_health_and_question_download(api):
    h = (await api.get("/health")).json()
    assert h["status"] == "ok" and h["server_time_ms"] > 0
    qs = await solo_questions(api)
    assert 140 <= len(qs) <= 160  # a third of the built-in bank is the offline pack
    assert {q["kind"] for q in qs} == {"mcq", "numeric"}
    assert all("text" in q and q["version"] > 0 for q in qs)
    general = (await api.get("/admin/questions?pack=general&limit=1", headers=ADMIN)).json()
    general_id = f"q{general['items'][0]['id']}"
    assert general_id not in {q["id"] for q in qs}, "online questions never go to devices"


async def test_question_changes_and_deletions_reach_devices(api):
    page = (await api.get("/questions", params={"limit": 1000})).json()
    v = page["version"]
    assert (await api.get("/questions", params={"since": v})).json()["items"] == []
    target = int(page["items"][0]["id"][1:])
    other = int(page["items"][1]["id"][1:])
    r = await api.patch(f"/admin/questions/{target}", json={"difficulty": 3}, headers=ADMIN)
    assert r.status_code == 200
    assert (await api.delete(f"/admin/questions/{other}", headers=ADMIN)).status_code == 204
    r = await api.post(
        "/admin/questions/import?pack=solo",
        json=[
            {
                "type": "numeric",
                "category": "علوم",
                "text_ar": "سؤال جديد للأوفلاين؟",
                "numeric_answer": 7,
            }
        ],
        headers=ADMIN,
    )
    assert r.json()["inserted"] == 1
    changes = (await api.get("/questions", params={"since": v})).json()
    by_id = {q["id"]: q for q in changes["items"]}
    assert by_id[f"q{target}"]["difficulty"] == 3
    assert by_id[f"q{other}"] == {
        "id": f"q{other}",
        "version": by_id[f"q{other}"]["version"],
        "deleted": True,
    }
    assert any(q.get("text") == "سؤال جديد للأوفلاين؟" for q in changes["items"])
    assert changes["version"] > v and len(changes["items"]) == 3


async def test_sync_scores_on_the_server_and_never_counts_twice(api):
    me = await guest(api)
    qs = await solo_questions(api)
    session = new_id()
    t0 = datetime.now(UTC) - timedelta(minutes=10)
    batch = [
        answer(q, right=i < 3, ts=t0 + timedelta(seconds=5 * i), session=session)
        for i, q in enumerate(qs[:5])
    ]
    batch.append(
        {
            "id": new_id(),
            "type": "session_end",
            "ts": (t0 + timedelta(seconds=30)).isoformat(),
            "session_id": session,
            "score": 1_000_000,
        }
    )
    r = (await api.post("/sync", json={"actions": batch}, headers=me["h"])).json()
    assert [x["status"] for x in r["results"]] == ["ok"] * 6
    assert [x.get("correct") for x in r["results"][:5]] == [True, True, True, False, False]
    solo = r["stats"]["solo"]
    assert solo["answered"] == 5 and solo["correct"] == 3 and solo["sessions"] == 1
    assert solo["points"] in range(30, 41)  # 10 per right answer (+5 for close numeric misses)

    # the same sync again (lost response, app restarted...) changes nothing
    again = (await api.post("/sync", json={"actions": batch}, headers=me["h"])).json()
    assert [x["status"] for x in again["results"]] == ["duplicate"] * 6
    assert again["stats"] == r["stats"]

    # two devices racing with the same batch, and a batch with the same id twice
    batch2 = [
        answer(q, right=True, ts=t0 + timedelta(minutes=2, seconds=5 * i), session=new_id())
        for i, q in enumerate(qs[5:8])
    ]
    res = await asyncio.gather(
        *(
            api.post("/sync", json={"actions": batch2 + batch2[:1]}, headers=me["h"])
            for _ in range(3)
        )
    )
    statuses = [x["status"] for resp in res for x in resp.json()["results"]]
    assert statuses.count("ok") == 3
    final = (await api.get("/me/stats", headers=me["h"])).json()
    assert final["solo"]["answered"] == 8 and final["solo"]["correct"] == 6


async def test_impossible_actions_are_rejected_without_blocking_the_queue(api):
    me = await guest(api)
    qs = await solo_questions(api)
    general = (await api.get("/admin/questions?pack=general&limit=1", headers=ADMIN)).json()
    now = datetime.now(UTC)
    s1 = new_id()
    ok = answer(qs[0], right=True, ts=now - timedelta(minutes=5), session=s1)
    cases = {
        "future_ts": answer(qs[1], right=True, ts=now + timedelta(hours=1), session=s1),
        "too_old": answer(qs[2], right=True, ts=now - timedelta(days=90), session=s1),
        "too_fast": answer(
            qs[3], right=True, ts=now - timedelta(minutes=4), session=s1, elapsed=50
        ),
        "too_frequent": answer(
            qs[4], right=True, ts=now - timedelta(minutes=5, milliseconds=-100), session=s1
        ),
        "repeat_in_session": answer(qs[0], right=True, ts=now - timedelta(minutes=3), session=s1),
        "unknown_question": answer(
            {"id": f"q{general['items'][0]['id']}", "kind": "mcq", "correct_index": 0},
            right=True,
            ts=now - timedelta(minutes=2),
            session=s1,
        ),
    }
    bad_uuid = {"id": "not-a-uuid", "type": "answer", "ts": now.isoformat(), "session_id": s1}
    body = {"actions": [ok, *cases.values(), bad_uuid]}
    r = (await api.post("/sync", json=body, headers=me["h"])).json()
    got = {x["id"]: x for x in r["results"]}
    assert got[ok["id"]]["status"] == "ok"
    for reason, action in cases.items():
        assert got[action["id"]] == {"id": action["id"], "status": "rejected", "reason": reason}
    assert got["not-a-uuid"]["reason"] == "invalid"
    assert r["stats"]["solo"]["answered"] == 1
    # rejected actions are stored: sending them again is a duplicate, not a second check
    again = (await api.post("/sync", json={"actions": [cases["too_fast"]]}, headers=me["h"])).json()
    assert again["results"][0]["status"] == "duplicate"

    # another player cannot reuse (or overwrite) someone else's action id
    other = await guest(api)
    r = (await api.post("/sync", json={"actions": [ok]}, headers=other["h"])).json()
    assert r["results"][0] == {"id": ok["id"], "status": "rejected", "reason": "id_conflict"}
    assert r["stats"]["solo"]["answered"] == 0


async def test_sync_needs_a_token_and_returns_question_updates(api):
    assert (await api.post("/sync", json={"actions": []})).status_code == 401
    me = await guest(api)
    r = (
        await api.post("/sync", json={"actions": [], "questions_since": 0}, headers=me["h"])
    ).json()
    assert r["questions"]["items"] and r["stats"]["solo"]["answered"] == 0


async def test_account_restore_on_a_new_device(api):
    old_device = new_id()
    me = await guest(api, old_device, name="سامي")
    assert (
        await api.post("/auth/account", json={"username": "Sami_7", "pin": "4821"}, headers=me["h"])
    ).json() == {"username": "sami_7"}
    other = await guest(api)
    r = await api.post(
        "/auth/account", json={"username": "sami_7", "pin": "1111"}, headers=other["h"]
    )
    assert r.status_code == 409
    assert (
        await api.post("/auth/account", json={"username": "x", "pin": "1"}, headers=me["h"])
    ).status_code == 422

    new_device = new_id()
    await guest(api, new_device)  # the new phone already made its own guest player
    r = (
        await api.post(
            "/auth/restore", json={"username": "SAMI_7", "pin": "4821", "device_id": new_device}
        )
    ).json()
    assert r["player_id"] == me["player_id"] and r["name"] == "سامي"
    again = await guest(api, new_device)
    assert again["player_id"] == me["player_id"], "the new device now logs into the old account"

    for _ in range(accounts.FAILS_PER_LOCK):
        r = await api.post(
            "/auth/restore", json={"username": "sami_7", "pin": "0000", "device_id": new_device}
        )
        assert r.status_code == 401
    r = await api.post(
        "/auth/restore", json={"username": "sami_7", "pin": "4821", "device_id": new_device}
    )
    assert r.status_code == 429, "locked even with the right PIN"


def test_pin_hashing_and_lock_growth():
    h = accounts.hash_pin("1234")
    assert "1234" not in h and accounts.check_pin("1234", h) and not accounts.check_pin("1235", h)
    assert accounts.hash_pin("1234") != h  # salted
    assert [accounts.lock_for(n) for n in (4, 5, 6, 10)] == [
        None,
        timedelta(minutes=15),
        None,
        timedelta(minutes=30),
    ]
    assert accounts.lock_for(500) == accounts.MAX_LOCK


async def test_online_matches_feed_the_leaderboard(home_server):
    url = await home_server()
    clients = await play_room(url, 2, timeout=60)
    async with httpx.AsyncClient(base_url=url) as http:
        board = (await http.get("/leaderboard")).json()
        assert len(board["rows"]) == 2
        top = board["rows"][0]
        assert top["rank"] == 1 and top["matches"] == 1 and top["wins"] == 1
        winner = next(c for c in clients if c.ended["standings"][0]["seat"] == c.seat)
        me = (
            await http.get("/leaderboard", headers={"Authorization": f"Bearer {winner.token}"})
        ).json()
        assert me["me"]["rank"] == 1
        stats = (
            await http.get("/me/stats", headers={"Authorization": f"Bearer {winner.token}"})
        ).json()
        assert stats["online"] == {"matches": 1, "wins": 1, "score": top["score"]}
    for c in clients:
        await c.close()

    # one human against bots: saved, but not on the leaderboard
    host = FakeClient(url, "solo-host", seed=5)
    await host.connect()
    await host.send("create_room")
    await host.wait_for("room_state")
    await host.send("add_bot", {"difficulty": "easy"})
    await host.wait_for("room_state", pred=lambda p: len(p["seats"]) == 2)
    await host.send("update_settings", {"packs": ["solo"]})
    err = await host.wait_for("error")
    assert err["code"] == "bad_settings", "rooms cannot use the offline pack"
    host.auto = True
    await host.send("start_match")
    await host.wait_for("match_ended", timeout=60)
    async with httpx.AsyncClient(base_url=url) as http:
        assert len((await http.get("/leaderboard")).json()["rows"]) == 2
        stats = (
            await http.get("/me/stats", headers={"Authorization": f"Bearer {host.token}"})
        ).json()
        assert stats["online"]["matches"] == 1
    await host.close()
