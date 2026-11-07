import httpx
import pytest
import websockets


async def test_same_device_gets_the_same_player(start_server):
    url = await start_server()
    async with httpx.AsyncClient() as http:
        a = (
            await http.post(
                f"{url}/auth/guest", json={"device_id": "device-123456", "name": "سامي"}
            )
        ).json()
        b = (await http.post(f"{url}/auth/guest", json={"device_id": "device-123456"})).json()
        c = (await http.post(f"{url}/auth/guest", json={"device_id": "device-999999"})).json()
        bad = await http.post(f"{url}/auth/guest", json={"device_id": "x"})
    assert a["player_id"] == b["player_id"] != c["player_id"]
    assert a["name"] == "سامي" and b["name"].startswith("ضيف")
    assert bad.status_code == 422


async def test_websocket_rejects_a_bad_token(start_server):
    url = await start_server()
    ws_url = url.replace("http", "ws", 1) + "/ws?token=forged"
    with pytest.raises(websockets.InvalidStatus):
        async with websockets.connect(ws_url):
            pass


async def test_websocket_accepts_bearer_header(start_server):
    from scripts.fake_clients import FakeClient

    url = await start_server()
    c = FakeClient(url, "hdr")
    await c.connect()  # uses the Authorization header
    welcome = await c.wait_for("welcome")
    assert welcome["player_id"] == c.pid
    await c.close()
