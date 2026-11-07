from httpx import ASGITransport, AsyncClient

from app import __version__
from app.main import app


async def test_health_returns_ok() -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok" and body["version"] == __version__
    assert body["server_time_ms"] > 0
