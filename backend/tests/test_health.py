from fastapi.testclient import TestClient

from arion_api.config import Settings
from arion_api.main import create_app


def test_health_endpoint_contract() -> None:
    application = create_app(Settings(_env_file=None))

    with TestClient(application) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.json() == {"status": "ok"}
