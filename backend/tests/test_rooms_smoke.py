from scripts.fake_clients import play_room


async def test_two_players_play_a_full_match(start_server):
    url = await start_server()
    clients = await play_room(url, 2, timeout=60)
    assert all(c.ended for c in clients)
    for c in clients:
        await c.close()
