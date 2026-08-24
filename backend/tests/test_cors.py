from __future__ import annotations

from pathlib import Path
from types import TracebackType

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from arion_api.config import Settings
from arion_api.main import create_app
from arion_api.storage import LocalMediaStorage


class FakeSession:
    def __enter__(self) -> FakeSession:
        return self

    def __exit__(
        self,
        _exception_type: type[BaseException] | None,
        _exception: BaseException | None,
        _traceback: TracebackType | None,
    ) -> None:
        return None

    def scalar(self, _statement: object) -> None:
        return None


class FakeSessionFactory:
    def __call__(self) -> Session:
        return FakeSession()  # type: ignore[return-value]


def make_client(tmp_path: Path, origins: list[str]) -> TestClient:
    settings = Settings(_env_file=None, media_root=tmp_path, cors_origins=origins)
    return TestClient(
        create_app(
            settings,
            session_factory=FakeSessionFactory(),  # type: ignore[arg-type]
            storage=LocalMediaStorage(tmp_path),
        )
    )


def test_allowed_origin_receives_read_and_exposed_headers(tmp_path: Path) -> None:
    origin = "http://localhost:8080"
    with make_client(tmp_path, [origin]) as client:
        response = client.get("/health", headers={"Origin": origin})

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin
    assert response.headers["access-control-expose-headers"] == (
        "Accept-Ranges, Content-Length, Content-Range"
    )


def test_allowed_preflight_accepts_range_header(tmp_path: Path) -> None:
    origin = "http://localhost:8080"
    with make_client(tmp_path, [origin]) as client:
        response = client.options(
            "/api/v1/tracks",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "Range",
            },
        )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin
    assert "range" in response.headers["access-control-allow-headers"].lower()


def test_unconfigured_origin_is_not_allowed(tmp_path: Path) -> None:
    with make_client(tmp_path, ["http://localhost:8080"]) as client:
        response = client.get(
            "/health", headers={"Origin": "http://unconfigured.test"}
        )

    assert "access-control-allow-origin" not in response.headers


def test_default_configuration_denies_cross_origin_access(tmp_path: Path) -> None:
    with make_client(tmp_path, []) as client:
        response = client.get(
            "/health", headers={"Origin": "http://localhost:8080"}
        )

    assert "access-control-allow-origin" not in response.headers
