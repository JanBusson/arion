from __future__ import annotations

import os
import threading
import wave
from io import BytesIO
from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from arion_api.config import Settings
from arion_api.errors import DuplicateTrackError
from arion_api.main import create_app
from arion_api.metadata import InspectedMetadata, TechnicalMetadata
from arion_api.models import Track
from arion_api.services import ImportService
from arion_api.storage import LocalMediaStorage


def wav_bytes() -> bytes:
    output = BytesIO()
    with wave.open(output, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(8000)
        audio.writeframes(b"\x00\x00" * 800)
    return output.getvalue()


@pytest.fixture
def api_context(
    postgres_session_factory: sessionmaker[Session], tmp_path: Path
) -> Any:
    settings = Settings(
        _env_file=None,
        media_root=tmp_path,
        reconciliation_grace_seconds=3600,
    )
    storage = LocalMediaStorage(tmp_path)
    application = create_app(
        settings,
        session_factory=postgres_session_factory,
        storage=storage,
    )
    with TestClient(application) as client:
        yield client, storage, postgres_session_factory


def test_import_duplicate_catalog_search_and_patch(api_context: Any) -> None:
    client, storage, _factory = api_context
    content = wav_bytes()

    created = client.post(
        "/api/v1/tracks/import",
        files={"file": ("Example Artist - Example Title.wav", content, "audio/wav")},
    )

    assert created.status_code == 201, created.text
    track = created.json()
    assert track["title"] == "Example Title"
    assert track["artist"] == "Example Artist"
    assert track["album"] == "Unknown Album"
    assert track["duration_ms"] > 0
    assert track["codec"].startswith("pcm_")
    assert track["sample_rate_hz"] == 8000
    assert track["has_cover"] is False
    assert "sha256" not in track
    assert "storage" not in created.text

    duplicate = client.post(
        "/api/v1/tracks/import",
        files={"file": ("renamed.wav", content, "application/octet-stream")},
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["detail"]["existing_track_id"] == track["id"]
    assert len(list((storage.root / "audio").iterdir())) == 1

    detail = client.get(f"/api/v1/tracks/{track['id']}")
    assert detail.status_code == 200
    listing = client.get("/api/v1/tracks", params={"q": "example ART", "limit": 1})
    assert listing.status_code == 200
    assert listing.json()["total"] == 1
    assert listing.json()["limit"] == 1
    assert client.get("/api/v1/tracks", params={"q": "   "}).json()["total"] == 1

    patched = client.patch(
        f"/api/v1/tracks/{track['id']}", json={"title": "  Corrected   Title "}
    )
    assert patched.status_code == 200
    assert patched.json()["title"] == "Corrected Title"
    assert patched.json()["artist"] == track["artist"]
    assert patched.json()["updated_at"] >= track["updated_at"]

    assert client.patch(
        f"/api/v1/tracks/{track['id']}", json={"title": " "}
    ).status_code == 422
    assert client.patch(
        f"/api/v1/tracks/{track['id']}", json={"duration_ms": 1}
    ).status_code == 422
    assert client.get(f"/api/v1/tracks/{uuid4()}").status_code == 404
    assert client.patch(
        f"/api/v1/tracks/{uuid4()}", json={"album": "Missing"}
    ).status_code == 404


def test_import_validates_multipart_size_and_media(api_context: Any) -> None:
    client, _storage, factory = api_context
    assert client.post("/api/v1/tracks/import", data={"other": "value"}).status_code == 422
    assert (
        client.post(
            "/api/v1/tracks/import",
            files=[
                ("file", ("one.wav", wav_bytes(), "audio/wav")),
                ("extra", ("two.wav", wav_bytes(), "audio/wav")),
            ],
        ).status_code
        == 422
    )
    unsupported = client.post(
        "/api/v1/tracks/import",
        files={"file": ("notes.txt", b"plain text", "audio/wav")},
    )
    assert unsupported.status_code == 415
    corrupt = client.post(
        "/api/v1/tracks/import",
        files={"file": ("broken.wav", b"RIFF1234WAVEbroken", "audio/wav")},
    )
    assert corrupt.status_code == 422

    tiny_settings = Settings(
        _env_file=None,
        media_root=Path(client.app.state.storage.root),
        max_upload_bytes=3,
    )
    tiny_app = create_app(
        tiny_settings,
        session_factory=factory,
        storage=client.app.state.storage,
    )
    with TestClient(tiny_app) as tiny_client:
        too_large = tiny_client.post(
            "/api/v1/tracks/import",
            files={"file": ("sample.wav", wav_bytes(), "audio/wav")},
        )
    assert too_large.status_code == 413
    assert list((client.app.state.storage.root / "staging").iterdir()) == []


def test_cover_retrieval_and_missing_cases(api_context: Any) -> None:
    client, storage, factory = api_context
    cover_bytes = b"\x89PNG\r\n\x1a\nsynthetic-cover"
    cover_stage = storage.create_staging(".cover")
    with storage.open_for_write(cover_stage) as stream:
        stream.write(cover_bytes)
    cover_key = storage.promote(cover_stage, "covers", ".png")

    audio_stage = storage.create_staging()
    audio_key = storage.promote(audio_stage, "audio", ".flac")
    with factory() as session, session.begin():
        with_cover = Track(
            sha256="a" * 64,
            audio_storage_key=audio_key.value,
            cover_storage_key=cover_key.value,
            cover_media_type="image/png",
            title="Covered",
            artist="Artist",
            album="Album",
            duration_ms=100,
            codec="flac",
            bitrate_kbps=None,
            sample_rate_hz=44100,
            original_filename="covered.flac",
        )
        no_cover = Track(
            sha256="b" * 64,
            audio_storage_key=f"audio/{uuid4().hex}.flac",
            title="Bare",
            artist="Artist",
            album="Album",
            duration_ms=100,
            codec="flac",
            bitrate_kbps=None,
            sample_rate_hz=44100,
            original_filename="bare.flac",
        )
        session.add_all([with_cover, no_cover])

    response = client.get(f"/api/v1/tracks/{with_cover.id}/cover")
    assert response.status_code == 200
    assert response.content == cover_bytes
    assert response.headers["content-type"] == "image/png"
    assert client.get(f"/api/v1/tracks/{no_cover.id}/cover").status_code == 404
    assert client.get(f"/api/v1/tracks/{uuid4()}/cover").status_code == 404
    storage.remove(cover_key)
    missing_object = client.get(f"/api/v1/tracks/{with_cover.id}/cover")
    assert missing_object.status_code == 404
    assert cover_key.value not in missing_object.text


def create_streamable_track(
    storage: LocalMediaStorage,
    factory: sessionmaker[Session],
    content: bytes = b"0123456789",
) -> Track:
    audio_stage = storage.create_staging()
    with storage.open_for_write(audio_stage) as stream:
        stream.write(content)
    audio_key = storage.promote(audio_stage, "audio", ".flac")
    with factory() as session, session.begin():
        track = Track(
            sha256=uuid4().hex + uuid4().hex,
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
        session.add(track)
    return track


def test_audio_retrieval_and_missing_cases(api_context: Any) -> None:
    client, storage, factory = api_context
    content = b"complete audio bytes"
    track = create_streamable_track(storage, factory, content)
    missing_key = f"audio/{uuid4().hex}.flac"
    with factory() as session, session.begin():
        missing_object = Track(
            sha256=uuid4().hex + uuid4().hex,
            audio_storage_key=missing_key,
            title="Missing object",
            artist="Artist",
            album="Album",
            duration_ms=100,
            codec="flac",
            bitrate_kbps=None,
            sample_rate_hz=44100,
            original_filename="missing.flac",
        )
        session.add(missing_object)

    response = client.get(f"/api/v1/tracks/{track.id}/audio")

    assert response.status_code == 200
    assert response.content == content
    assert response.headers["content-type"] == "audio/flac"
    assert response.headers["content-length"] == str(len(content))
    assert response.headers["accept-ranges"] == "bytes"
    assert client.get(f"/api/v1/tracks/{uuid4()}/audio").status_code == 404
    unavailable = client.get(f"/api/v1/tracks/{missing_object.id}/audio")
    assert unavailable.status_code == 404
    assert missing_key not in unavailable.text
    assert str(storage.root) not in unavailable.text


def test_audio_single_range_forms(api_context: Any) -> None:
    client, storage, factory = api_context
    track = create_streamable_track(storage, factory)
    cases = [
        ("bytes=2-5", b"2345", "bytes 2-5/10"),
        ("bytes=4-", b"456789", "bytes 4-9/10"),
        ("bytes=-3", b"789", "bytes 7-9/10"),
        ("bytes=6-99", b"6789", "bytes 6-9/10"),
    ]

    for header, expected, content_range in cases:
        response = client.get(
            f"/api/v1/tracks/{track.id}/audio", headers={"Range": header}
        )

        assert response.status_code == 206
        assert response.content == expected
        assert response.headers["content-type"] == "audio/flac"
        assert response.headers["content-length"] == str(len(expected))
        assert response.headers["content-range"] == content_range
        assert response.headers["accept-ranges"] == "bytes"


@pytest.mark.parametrize(
    "header",
    [
        "bytes=",
        "items=0-1",
        "bytes=0-1,4-5",
        "bytes=9-2",
        "bytes=-0",
        "bytes=10-",
    ],
)
def test_audio_rejects_invalid_ranges(api_context: Any, header: str) -> None:
    client, storage, factory = api_context
    track = create_streamable_track(storage, factory)

    response = client.get(
        f"/api/v1/tracks/{track.id}/audio", headers={"Range": header}
    )

    assert response.status_code == 416
    assert response.content == b""
    assert response.headers["content-range"] == "bytes */10"
    assert response.headers["content-length"] == "0"
    assert response.headers["accept-ranges"] == "bytes"


class FixedInspector:
    def inspect(self, _path: Path, _filename: str) -> InspectedMetadata:
        return InspectedMetadata(
            title="Title",
            artist="Artist",
            album="Album",
            technical=TechnicalMetadata(
                duration_ms=100,
                codec="flac",
                bitrate_kbps=700,
                sample_rate_hz=44100,
                suffix=".flac",
            ),
            cover=None,
        )


def test_concurrent_imports_create_one_track_and_one_audio_object(
    postgres_session_factory: sessionmaker[Session], tmp_path: Path
) -> None:
    storage = LocalMediaStorage(tmp_path)
    service = ImportService(
        postgres_session_factory,
        storage,
        FixedInspector(),  # type: ignore[arg-type]
        1024,
    )
    barrier = threading.Barrier(2)
    results: list[Track | Exception] = []

    def import_same_content() -> None:
        barrier.wait(timeout=5)
        try:
            results.append(service.import_file(BytesIO(b"same bytes"), "same.flac"))
        except Exception as error:
            results.append(error)

    threads = [threading.Thread(target=import_same_content) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=10)

    assert sum(isinstance(result, Track) for result in results) == 1
    assert sum(isinstance(result, DuplicateTrackError) for result in results) == 1
    with postgres_session_factory() as session:
        assert session.scalar(select(func.count()).select_from(Track)) == 1
    assert len(list((tmp_path / "audio").iterdir())) == 1
    assert list((tmp_path / "staging").iterdir()) == []


def test_restart_reconciliation_removes_orphan_and_keeps_committed_media(
    postgres_session_factory: sessionmaker[Session], tmp_path: Path
) -> None:
    storage = LocalMediaStorage(tmp_path)
    service = ImportService(
        postgres_session_factory,
        storage,
        FixedInspector(),  # type: ignore[arg-type]
        1024,
    )
    committed = service.import_file(BytesIO(b"committed"), "track.flac")
    orphan_stage = storage.create_staging()
    orphan = storage.promote(orphan_stage, "audio", ".flac")
    old = 1
    os.utime(tmp_path / orphan.value, (old, old))

    settings = Settings(
        _env_file=None, media_root=tmp_path, reconciliation_grace_seconds=0
    )
    application = create_app(
        settings,
        session_factory=postgres_session_factory,
        storage=storage,
        inspector=FixedInspector(),  # type: ignore[arg-type]
    )
    with TestClient(application) as client:
        assert client.get(f"/api/v1/tracks/{committed.id}").status_code == 200

    assert not (tmp_path / orphan.value).exists()
    assert len(list((tmp_path / "audio").iterdir())) == 1


def test_import_compensates_when_database_flush_fails(
    postgres_engine: Engine, tmp_path: Path
) -> None:
    class FailingSession(Session):
        def flush(self, objects: object = None) -> None:
            if any(isinstance(item, Track) for item in self.new):
                raise RuntimeError("forced database write failure")
            super().flush(objects)  # type: ignore[arg-type]

    failing_factory = sessionmaker(
        bind=postgres_engine, class_=FailingSession, expire_on_commit=False
    )
    storage = LocalMediaStorage(tmp_path)
    service = ImportService(
        failing_factory,
        storage,
        FixedInspector(),  # type: ignore[arg-type]
        1024,
    )

    with pytest.raises(RuntimeError, match="forced database write failure"):
        service.import_file(BytesIO(b"uncommitted"), "track.flac")

    assert list((tmp_path / "staging").iterdir()) == []
    assert list((tmp_path / "audio").iterdir()) == []
    assert list((tmp_path / "covers").iterdir()) == []


def test_import_cleans_promoted_audio_when_cover_promotion_fails(
    postgres_session_factory: sessionmaker[Session], tmp_path: Path
) -> None:
    class CoverInspector(FixedInspector):
        def inspect(self, path: Path, filename: str) -> InspectedMetadata:
            inspected = super().inspect(path, filename)
            from arion_api.metadata import Cover

            return InspectedMetadata(
                title=inspected.title,
                artist=inspected.artist,
                album=inspected.album,
                technical=inspected.technical,
                cover=Cover(b"\x89PNG\r\n\x1a\ncover", "image/png"),
            )

    class FailingCoverStorage(LocalMediaStorage):
        def promote(self, key: object, namespace: object, suffix: str) -> object:
            if namespace == "covers":
                raise OSError("forced cover promotion failure")
            return super().promote(key, namespace, suffix)  # type: ignore[arg-type,return-value]

    storage = FailingCoverStorage(tmp_path)
    service = ImportService(
        postgres_session_factory,
        storage,
        CoverInspector(),  # type: ignore[arg-type]
        1024,
    )

    with pytest.raises(OSError, match="forced cover promotion failure"):
        service.import_file(BytesIO(b"uncommitted cover"), "track.flac")

    assert list((tmp_path / "staging").iterdir()) == []
    assert list((tmp_path / "audio").iterdir()) == []
    assert list((tmp_path / "covers").iterdir()) == []


def test_liveness_is_independent_and_readiness_is_safe(tmp_path: Path) -> None:
    class BrokenFactory:
        def __call__(self) -> Any:
            raise RuntimeError("postgresql://secret-user:secret-password@private-host")

    class UnreadyStorage(LocalMediaStorage):
        def probe_ready(self) -> bool:
            return False

    application = create_app(
        Settings(_env_file=None, media_root=tmp_path),
        session_factory=BrokenFactory(),  # type: ignore[arg-type]
        storage=UnreadyStorage(tmp_path),
        inspector=FixedInspector(),  # type: ignore[arg-type]
    )
    with TestClient(application) as client:
        health = client.get("/health")
        readiness = client.get("/ready")

    assert health.status_code == 200
    assert health.json() == {"status": "ok"}
    assert readiness.status_code == 503
    assert readiness.json() == {
        "status": "not_ready",
        "dependencies": {"database": "unavailable", "storage": "unavailable"},
    }
    assert "secret" not in readiness.text
    assert "private-host" not in readiness.text
