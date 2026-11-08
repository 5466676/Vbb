"""Rooms, protocol and multi-worker behaviour over real WebSockets (phase 4).

Each test starts real uvicorn workers on a shared redis-server with ``time_scale`` so a
whole match takes seconds.
"""

import asyncio

from scripts.fake_clients import ARMIES, FakeClient, play_room


async def close_all(clients):
    for c in clients:
        await c.close()


async def lobby(url, n, **settings):
    clients = [FakeClient(url, f"p{i}", seed=i) for i in range(n)]
    for c in clients:
        await c.connect()
    host = clients[0]
    await host.send("create_room", {"army": "ottoman"})
    code = (await host.wait_for("room_state"))["code"]
    if settings:
        await host.send("update_settings", settings)
    for i, c in enumerate(clients[1:], 1):
        await c.send("join_room", {"code": code, "army": ARMIES[i % 8]})
        await c.wait_for(
            "room_state", pred=lambda p, c=c: any(s["player_id"] == c.pid for s in p["seats"])
        )
    return clients, code


async def test_eight_players_full_match_through_a_room_code(start_server):
    url = await start_server()
    clients = await play_room(url, 8, timeout=120)
    standings = [c.ended["standings"] for c in clients]
    assert all(s == standings[0] for s in standings), "everyone sees the same result"
    assert len(standings[0]) == 8
    for c in clients:
        assert [e for e in c.errors if e["code"] != "rule"] == []
        for msg in c.log:
            if msg["type"] == "question":
                assert "answer" not in msg["payload"] and "correct_index" not in msg["payload"]
    await close_all(clients)


async def test_options_are_shuffled_per_player_and_results_map_back(start_server):
    url = await start_server()
    clients = await play_room(url, 4, timeout=60)
    seen_different_order = False
    checked = 0
    for qid in {m["payload"]["id"] for c in clients for m in c.log if m["type"] == "question"}:
        views = []
        for c in clients:
            q = next(
                (
                    m["payload"]
                    for m in c.log
                    if m["type"] == "question" and m["payload"]["id"] == qid
                ),
                None,
            )
            r = next(
                (
                    m["payload"]
                    for m in c.log
                    if m["type"] == "question_result" and m["payload"]["id"] == qid
                ),
                None,
            )
            if q and r and q["kind"] == "mcq" and q["participant"]:
                views.append((q["options"], q["options"][r["correct_index"]]))
        if len(views) >= 2:
            checked += 1
            assert len({correct for _, correct in views}) == 1, (
                "the correct option is the same text for all"
            )
            if len({tuple(opts) for opts, _ in views}) > 1:
                seen_different_order = True
    assert checked > 0 and seen_different_order
    await close_all(clients)


async def test_team_match(start_server):
    url = await start_server()
    clients = await play_room(url, 4, timeout=60, mode="teams")
    end = clients[0].ended
    teams = {row["team"] for row in end["standings"]}
    assert teams == {0, 1}
    await close_all(clients)


async def test_reconnect_gets_full_state_and_finishes(start_server):
    url = await start_server()
    clients, code = await lobby(url, 2)
    a, b = clients
    for c in clients:
        c.auto = True
        await c.send("set_ready", {"ready": True})
    await a.wait_for("room_state", pred=lambda p: all(s["ready"] for s in p["seats"]))
    await a.send("start_match")
    await b.wait_for("phase_changed", timeout=10, pred=lambda p: p["phase"] == "battle_target")
    await b.close()
    await asyncio.sleep(0.2)
    b2 = FakeClient(url, "p1-again")
    b2.token, b2.pid, b2.auto = b.token, b.pid, True
    await b2.connect()
    full = await b2.wait_for("full_state", timeout=10)
    assert full["room"]["code"] == code
    assert full["match"]["your_seat"] == b.seat
    assert full["match"]["phase"] in ("battle_target", "battle_duel", "battle_tiebreak")
    assert all(t["owner"] is not None for t in full["match"]["territories"])
    await asyncio.gather(
        a.wait_for("match_ended", timeout=60), b2.wait_for("match_ended", timeout=60)
    )
    await close_all([a, b2])


async def test_disconnected_seat_is_played_by_a_bot(start_server):
    url = await start_server()
    clients, _ = await lobby(url, 3)
    for c in clients:
        await c.send("set_ready", {"ready": True})
    await clients[0].wait_for("room_state", pred=lambda p: all(s["ready"] for s in p["seats"]))
    clients[0].auto = clients[1].auto = True
    await clients[0].send("start_match")
    await clients[2].wait_for("match_started")
    await clients[2].close()  # never comes back
    await clients[0].wait_for("match_ended", timeout=90)
    conn = [m["payload"] for m in clients[0].log if m["type"] == "player_connection"]
    assert {"seat": clients[2].seat, "connected": False} in conn
    await close_all(clients[:2])


async def test_duplicate_wrong_id_and_late_answers_are_rejected(start_server):
    url = await start_server(time_scale=0.05)
    clients, _ = await lobby(url, 2)
    a, b = clients
    for c in clients:
        await c.send("set_ready", {"ready": True})
    await a.wait_for("room_state", pred=lambda p: all(s["ready"] for s in p["seats"]))
    await a.send("start_match")
    q = await a.wait_for("question", timeout=10)
    await a.send("answer", {"question_id": "nope", "value": 1})
    await a.wait_for("error", pred=lambda e: e["code"] == "no_question")
    await a.send("answer", {"question_id": q["id"], "value": 1})
    await a.send("answer", {"question_id": q["id"], "value": 2})
    err = await a.wait_for("error", pred=lambda e: e["code"] == "rule")
    assert "duplicate" in err["message"]
    await a.wait_for("question_result", timeout=10)  # b never answered: timeout resolved it
    # a late answer to a question that has just closed is a normal race: ignored, no error
    errors_before = len(b.errors)
    await b.send("answer", {"question_id": q["id"], "value": 5})
    await asyncio.sleep(0.3)
    assert len(b.errors) == errors_before
    await close_all(clients)


async def test_rate_limit_and_bad_frames(start_server):
    url = await start_server(rate_per_s=5, rate_burst=10)
    c = FakeClient(url, "spam")
    await c.connect()
    await c.ws.send("not json")
    await c.wait_for("error", pred=lambda e: e["code"] == "bad_frame")
    await c.send("teleport")
    await c.wait_for("error", pred=lambda e: e["code"] == "bad_type")
    for _ in range(40):
        await c.send("ping", {"t": 1})
    await c.wait_for("error", pred=lambda e: e["code"] == "rate_limited")
    await c.close()


async def test_lobby_rules(start_server):
    url = await start_server()
    clients, code = await lobby(url, 2, max_players=2)
    host, guest = clients
    await guest.send("start_match")
    await guest.wait_for("error", pred=lambda e: e["code"] == "not_host")
    late = FakeClient(url, "late")
    await late.connect()
    await late.send("join_room", {"code": code})
    await late.wait_for("error", pred=lambda e: e["code"] == "full")
    await late.send("join_room", {"code": "ZZZZZZ"})
    await late.wait_for("error", pred=lambda e: e["code"] == "no_room")
    await host.send("start_match")  # guest is not ready
    await host.wait_for("error", pred=lambda e: e["code"] == "not_ready")
    await host.send("update_settings", {"max_players": 4})
    await host.send("add_bot", {"difficulty": "hard"})
    state = await host.wait_for("room_state", pred=lambda p: any(s["bot"] for s in p["seats"]))
    assert state["seats"][2]["bot"] == "hard"
    await guest.send("leave_room")
    await guest.wait_for("left_room")
    await host.wait_for("room_state", pred=lambda p: len(p["seats"]) == 2)
    await close_all([host, guest, late])


async def test_host_with_bots_plays_a_full_match(start_server):
    url = await start_server()
    clients, _ = await lobby(url, 1)
    host = clients[0]
    for level in ("easy", "medium", "hard"):
        await host.send("add_bot", {"difficulty": level})
    await host.wait_for("room_state", pred=lambda p: len(p["seats"]) == 4)
    host.auto = True
    await host.send("start_match")
    end = await host.wait_for("match_ended", timeout=90)
    assert len(end["standings"]) == 4
    await host.close()


async def test_quick_match_fills_with_bots_after_waiting(start_server):
    url = await start_server(quick_match_wait_s=20)  # 20 s * 0.02 = 0.4 s real
    a, b = FakeClient(url, "qa", seed=1), FakeClient(url, "qb", seed=2)
    for c in (a, b):
        await c.connect()
        c.auto = True
        await c.send("quick_match", {"mode": "ffa", "size": 4, "army": "mongol"})
        await c.wait_for("queued")
    found = await asyncio.gather(
        a.wait_for("match_found", timeout=10), b.wait_for("match_found", timeout=10)
    )
    assert found[0]["code"] == found[1]["code"]
    started = await a.wait_for("match_started", timeout=10)
    assert sum(p["bot"] for p in started["players"]) == 2
    await asyncio.gather(
        a.wait_for("match_ended", timeout=90), b.wait_for("match_ended", timeout=90)
    )
    await close_all([a, b])


async def test_two_workers_share_one_room(start_server):
    url_a = await start_server()
    url_b = await start_server()
    clients = [FakeClient(url_a if i % 2 == 0 else url_b, f"w{i}", seed=i) for i in range(4)]
    for c in clients:
        await c.connect()
    await clients[0].send("create_room")
    code = (await clients[0].wait_for("room_state"))["code"]
    for c in clients[1:]:
        await c.send("join_room", {"code": code})
    await clients[0].wait_for("room_state", pred=lambda p: len(p["seats"]) == 4)
    for c in clients:
        c.auto = True
        await c.send("set_ready", {"ready": True})
    await clients[0].wait_for("room_state", pred=lambda p: all(s["ready"] for s in p["seats"]))
    await clients[0].send("start_match")
    ends = await asyncio.gather(*(c.wait_for("match_ended", timeout=90) for c in clients))
    assert all(e["standings"] == ends[0]["standings"] for e in ends)
    await close_all(clients)


async def test_room_survives_its_worker_dying(start_server):
    lease = {"room_lease_s": 1.0}
    url_a = await start_server(time_scale=0.03, **lease)
    url_b = await start_server(time_scale=0.03, **lease)
    host = FakeClient(url_a, "host", seed=1)
    others = [FakeClient(url_b, f"b{i}", seed=10 + i) for i in range(2)]
    for c in [host, *others]:
        await c.connect()
    await host.send("create_room")  # worker A runs the room
    code = (await host.wait_for("room_state"))["code"]
    for c in others:
        await c.send("join_room", {"code": code})
    await host.wait_for("room_state", pred=lambda p: len(p["seats"]) == 3)
    for c in [host, *others]:
        c.auto = True
        await c.send("set_ready", {"ready": True})
    await host.wait_for("room_state", pred=lambda p: all(s["ready"] for s in p["seats"]))
    await host.send("start_match")
    await others[0].wait_for(
        "phase_changed", timeout=20, pred=lambda p: p["phase"] == "battle_target"
    )
    await start_server.stop(url_a)  # the owner dies mid-match
    host2 = FakeClient(url_b, "host-again", seed=2)
    host2.token, host2.pid, host2.auto = host.token, host.pid, True
    await host2.connect()
    full = await host2.wait_for("full_state", timeout=20)
    assert full["match"] is not None
    ends = await asyncio.gather(*(c.wait_for("match_ended", timeout=120) for c in [host2, *others]))
    assert all(e["standings"] == ends[0]["standings"] for e in ends)
    await close_all([host2, *others])
