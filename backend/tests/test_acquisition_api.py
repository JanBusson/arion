from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from types import TracebackType
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from arion_api.acquisition_types import DiscoveryMode
from arion_api.config import Settings
from arion_api.errors import YouTubeProviderUnavailableError
from arion_api.main import create_app
from arion_api.schemas import (
    AcquisitionCandidateSummary,
    AcquisitionJobResponse,
    YouTubeCandidateResponse,
)
from arion_api.storage import LocalMediaStorage


class FakeSession:
    def __enter__(self) -> "FakeSession":
        return self

    def __exit__(
        self,
        _kind: type[BaseException] | None,
        _error: BaseException | None,
        _traceback: TracebackType | None,
    ) -> None:
        return None


class FakeFactory:
    def __call__(self) -> FakeSession:
        return FakeSession()


class StubAcquisitionService:
    def __init__(self) -> None:
        self.discovery_calls: list[tuple[str, DiscoveryMode]] = []
        self.created_tokens: list[str] = []
        self.job_id = uuid4()

    def discover(
        self, query: str, mode: DiscoveryMode
    ) -> list[YouTubeCandidateResponse]:
        self.discovery_calls.append((query, mode))
        if query == "unavailable":
            raise YouTubeProviderUnavailableError()
        if query == "empty":
            return []
        return [
            YouTubeCandidateResponse(
                candidate_id="token." + "x" * 32,
                discovery_mode=mode,
                video_id="abcdefghijk",
                title="Song",
                channel="Artist",
                duration_seconds=120,
                thumbnail_url=None,
                page_url="https://www.youtube.com/watch?v=abcdefghijk",
            )
        ]

    def create_job(self, token: str) -> AcquisitionJobResponse:
        self.created_tokens.append(token)
        return self.response()

    def get_job(self, job_id: UUID) -> AcquisitionJobResponse:
        assert job_id == self.job_id
        return self.response()

    def response(self) -> AcquisitionJobResponse:
        now = datetime.now(UTC)
        return AcquisitionJobResponse(
            id=self.job_id,
            state="queued",
            phase="queued",
            progress_percent=0,
            attempts=0,
            candidate=AcquisitionCandidateSummary(
                video_id="abcdefghijk",
                title="Song",
                channel="Artist",
                duration_seconds=120,
                thumbnail_url=None,
                page_url="https://www.youtube.com/watch?v=abcdefghijk",
            ),
            track_id=None,
            failure_code=None,
            failure_message=None,
            created_at=now,
            updated_at=now,
        )


def application(tmp_path: Path, enabled: bool) -> object:
    settings = Settings(
        _env_file=None,
        media_root=tmp_path,
        youtube_acquisition_enabled=enabled,
        youtube_candidate_secret="x" * 32 if enabled else "replace-me",
    )
    return create_app(
        settings,
        session_factory=FakeFactory(),  # type: ignore[arg-type]
        storage=LocalMediaStorage(tmp_path),
    )


def test_disabled_acquisition_is_503_without_affecting_health(tmp_path: Path) -> None:
    with TestClient(application(tmp_path, False)) as client:  # type: ignore[arg-type]
        disabled = client.get(
            "/api/v1/acquisition/youtube/candidates", params={"q": "song"}
        )
        health = client.get("/health")

    assert disabled.status_code == 503
    assert disabled.json()["detail"]["code"] == "youtube_acquisition_disabled"
    assert health.status_code == 200


def test_acquisition_endpoints_use_allow_list_and_stable_contract(tmp_path: Path) -> None:
    app = application(tmp_path, True)
    stub = StubAcquisitionService()
    app.state.acquisition_service = stub  # type: ignore[attr-defined]
    with TestClient(app) as client:  # type: ignore[arg-type]
        candidates = client.get(
            "/api/v1/acquisition/youtube/candidates", params={"q": "  Song  "}
        )
        broad = client.get(
            "/api/v1/acquisition/youtube/candidates",
            params={"q": "Remix", "mode": "all"},
        )
        explicit_music = client.get(
            "/api/v1/acquisition/youtube/candidates",
            params={"q": "Music", "mode": "music"},
        )
        unsupported = client.get(
            "/api/v1/acquisition/youtube/candidates",
            params={"q": "Song", "mode": "videos"},
        )
        oversized = client.get(
            "/api/v1/acquisition/youtube/candidates",
            params={"q": "Song", "mode": "m" * 1024},
        )
        empty = client.get(
            "/api/v1/acquisition/youtube/candidates",
            params={"q": "empty", "mode": "music"},
        )
        unavailable = client.get(
            "/api/v1/acquisition/youtube/candidates",
            params={"q": "unavailable", "mode": "music"},
        )
        invalid = client.get(
            "/api/v1/acquisition/youtube/candidates", params={"q": "   "}
        )
        created = client.post(
            "/api/v1/acquisition/jobs",
            json={
                "candidate_id": "token." + "x" * 32,
                "authorization_acknowledged": True,
            },
        )
        fetched = client.get(f"/api/v1/acquisition/jobs/{stub.job_id}")

    assert candidates.status_code == 200
    assert candidates.json()["items"][0]["video_id"] == "abcdefghijk"
    assert candidates.json()["items"][0]["discovery_mode"] == "music"
    assert broad.status_code == 200
    assert explicit_music.status_code == 200
    assert stub.discovery_calls == [
        ("Song", DiscoveryMode.MUSIC),
        ("Remix", DiscoveryMode.ALL),
        ("Music", DiscoveryMode.MUSIC),
        ("empty", DiscoveryMode.MUSIC),
        ("unavailable", DiscoveryMode.MUSIC),
    ]
    assert unsupported.status_code == 422
    assert oversized.status_code == 422
    assert empty.status_code == 200
    assert empty.json() == {"items": []}
    assert unavailable.status_code == 502
    assert unavailable.json()["detail"]["code"] == "youtube_provider_unavailable"
    assert invalid.status_code == 422
    assert created.status_code == 202
    assert fetched.status_code == 200
    assert "lease_expires_at" not in fetched.text
    assert "candidate_secret" not in fetched.text
