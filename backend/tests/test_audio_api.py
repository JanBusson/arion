from __future__ import annotations

from pathlib import Path
from types import TracebackType
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from pytest import MonkeyPatch

import arion_api.main as main_module
from arion_api.config import Settings
from arion_api.models import Track
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


class FakeSessionFactory:
    def __call__(self) -> FakeSession:
        return FakeSession()


class FakeTrackRepository:
    track: Track

    def __init__(self, _session: FakeSession) -> None:
        pass

    def get(self, track_id: UUID) -> Track | None:
        return self.track if track_id == self.track.id else None


def test_audio_route_executes_complete_partial_and_invalid_responses(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    content = b"0123456789"
    storage = LocalMediaStorage(tmp_path)
    staged = storage.create_staging()
    with storage.open_for_write(staged) as stream:
        stream.write(content)
    audio_key = storage.promote(staged, "audio", ".flac")
    FakeTrackRepository.track = Track(
        id=uuid4(),
        sha256="a" * 64,
        audio_storage_key=audio_key.value,
        title="Streamable",
        artist="Artist",
        album="Album",
        duration_ms=100,
        codec="flac",
        bitrate_kbps=700,
        sample_rate_hz=44100,
        original_filename="streamable.flac",
    )
    monkeypatch.setattr(main_module, "TrackRepository", FakeTrackRepository)
    monkeypatch.setattr(main_module, "reconcile_storage", lambda *_args: [])
    application = main_module.create_app(
        Settings(_env_file=None, media_root=tmp_path),
        session_factory=FakeSessionFactory(),  # type: ignore[arg-type]
        storage=storage,
    )

    with TestClient(application) as client:
        complete = client.get(
            f"/api/v1/tracks/{FakeTrackRepository.track.id}/audio"
        )
        partial = client.get(
            f"/api/v1/tracks/{FakeTrackRepository.track.id}/audio",
            headers={"Range": "bytes=2-5"},
        )
        invalid = client.get(
            f"/api/v1/tracks/{FakeTrackRepository.track.id}/audio",
            headers={"Range": "bytes=20-"},
        )

    assert complete.status_code == 200
    assert complete.content == content
    assert complete.headers["content-type"] == "audio/flac"
    assert complete.headers["content-length"] == "10"
    assert complete.headers["accept-ranges"] == "bytes"
    assert partial.status_code == 206
    assert partial.content == b"2345"
    assert partial.headers["content-range"] == "bytes 2-5/10"
    assert invalid.status_code == 416
    assert invalid.content == b""
    assert invalid.headers["content-range"] == "bytes */10"
