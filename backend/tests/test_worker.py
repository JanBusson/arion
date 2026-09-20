from __future__ import annotations

import logging
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from arion_api.acquisition import AcquisitionService
from arion_api.acquisition_provider import AcquisitionCandidate, CandidateTokenSigner
from arion_api.acquisition_types import DiscoveryMode
from arion_api.config import Settings
from arion_api.errors import AcquisitionFailure
from arion_api.metadata import InspectedMetadata, TechnicalMetadata, apply_fallbacks
from arion_api.models import AcquisitionJob, Track, TrackSource
from arion_api.repository import AcquisitionJobRepository
from arion_api.services import ImportService
from arion_api.storage import LocalMediaStorage
from arion_api.worker import AcquisitionWorker


class FixedInspector:
    def inspect(self, _path: Path, filename: str) -> InspectedMetadata:
        title, artist, album = apply_fallbacks(
            title=None,
            artist=None,
            album=None,
            filename=filename,
        )
        return InspectedMetadata(
            title=title,
            artist=artist,
            album=album,
            technical=TechnicalMetadata(
                duration_ms=1000,
                codec="aac",
                bitrate_kbps=128,
                sample_rate_hz=44100,
                suffix=".m4a",
            ),
            cover=None,
        )


class IdentityNormalizer:
    def normalize(self, source: Path, **_: object) -> Path:
        return source


class FakeProvider:
    def __init__(self, *, failure: AcquisitionFailure | None = None) -> None:
        self.failure = failure

    def discover(self, _query: str) -> list[AcquisitionCandidate]:
        return []

    def revalidate(self, video_id: str) -> AcquisitionCandidate:
        if self.failure is not None:
            raise self.failure
        return candidate(video_id)

    def download(self, _video_id: str, workspace: Path, **_: object) -> Path:
        output = workspace / "source.m4a"
        output.write_bytes(b"same acquired audio")
        return output


def candidate(
    video_id: str = "abcdefghijk",
    mode: DiscoveryMode = DiscoveryMode.ALL,
) -> AcquisitionCandidate:
    return AcquisitionCandidate(
        discovery_mode=mode,
        provider="youtube",
        external_id=video_id,
        title="Song",
        channel="Artist",
        duration_seconds=120,
        thumbnail_url=None,
        page_url=f"https://www.youtube.com/watch?v={video_id}",
    )


def settings(tmp_path: Path) -> Settings:
    return Settings(
        _env_file=None,
        media_root=tmp_path,
        youtube_acquisition_enabled=True,
        youtube_candidate_secret="x" * 32,
        youtube_min_free_bytes=0,
        youtube_job_lease_seconds=30,
        youtube_download_timeout_seconds=60,
    )


def enqueue(
    selected: Settings,
    factory: sessionmaker[Session],
    provider: FakeProvider,
    video_id: str = "abcdefghijk",
    mode: DiscoveryMode = DiscoveryMode.ALL,
) -> AcquisitionJob:
    signer = CandidateTokenSigner("x" * 32)
    token = signer.sign(
        candidate(video_id, mode), now=1, ttl_seconds=4_000_000_000
    )
    response = AcquisitionService(
        selected,
        factory,
        provider,  # type: ignore[arg-type]
        signer,
    ).create_job(token)
    with factory() as session:
        job = AcquisitionJobRepository(session).get(response.id)
        assert job is not None
        session.expunge(job)
        return job


def worker(
    selected: Settings,
    factory: sessionmaker[Session],
    storage: LocalMediaStorage,
    provider: FakeProvider,
) -> AcquisitionWorker:
    return AcquisitionWorker(
        selected,
        factory,
        storage,
        provider,  # type: ignore[arg-type]
        IdentityNormalizer(),  # type: ignore[arg-type]
        ImportService(
            factory,
            storage,
            FixedInspector(),  # type: ignore[arg-type]
            selected.max_upload_bytes,
        ),
    )


def test_worker_completes_job_records_provenance_and_cleans_workspace(
    postgres_session_factory: sessionmaker[Session],
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    selected = settings(tmp_path)
    storage = LocalMediaStorage(tmp_path)
    provider = FakeProvider()
    job = enqueue(selected, postgres_session_factory, provider)

    worker_logger = logging.getLogger("arion_api.worker")
    previously_disabled = worker_logger.disabled
    worker_logger.disabled = False
    try:
        with caplog.at_level("INFO", logger="arion_api.worker"):
            assert worker(
                selected, postgres_session_factory, storage, provider
            ).process_one()
    finally:
        worker_logger.disabled = previously_disabled

    with postgres_session_factory() as session:
        stored = AcquisitionJobRepository(session).get(job.id)
        assert stored is not None and stored.state == "completed"
        assert stored.track_id is not None
        track = session.get(Track, stored.track_id)
        assert track is not None
        assert track.title == "Song"
        assert track.artist == "Artist"
        assert track.original_filename == "Artist - Song.m4a"
        assert session.scalar(select(func.count()).select_from(Track)) == 1
        assert session.scalar(select(func.count()).select_from(TrackSource)) == 1
    phase_records = [
        record
        for record in caplog.records
        if getattr(record, "event", None) == "acquisition_job_phase_changed"
    ]
    assert [
        (record.state, record.phase, record.progress_percent)
        for record in phase_records
    ] == [
        ("processing", "normalizing", 70),
        ("processing", "importing", 85),
    ]
    jobs_root = tmp_path / "staging" / "jobs"
    assert not jobs_root.exists() or list(jobs_root.iterdir()) == []


def test_job_creation_is_idempotent_and_content_duplicate_adds_provenance(
    postgres_session_factory: sessionmaker[Session], tmp_path: Path
) -> None:
    selected = settings(tmp_path)
    storage = LocalMediaStorage(tmp_path)
    provider = FakeProvider()
    first = enqueue(
        selected,
        postgres_session_factory,
        provider,
        "abcdefghijk",
        DiscoveryMode.MUSIC,
    )
    repeated = enqueue(
        selected,
        postgres_session_factory,
        provider,
        "abcdefghijk",
        DiscoveryMode.ALL,
    )
    assert repeated.id == first.id

    active_worker = worker(selected, postgres_session_factory, storage, provider)
    active_worker.process_one()
    second = enqueue(selected, postgres_session_factory, provider, "lmnopqrstuv")
    active_worker.process_one()

    with postgres_session_factory() as session:
        stored_second = AcquisitionJobRepository(session).get(second.id)
        assert stored_second is not None and stored_second.state == "completed"
        assert session.scalar(select(func.count()).select_from(Track)) == 1
        assert session.scalar(select(func.count()).select_from(TrackSource)) == 2



def test_worker_retries_transient_failure_then_fails_safely(
    postgres_session_factory: sessionmaker[Session], tmp_path: Path
) -> None:
    selected = settings(tmp_path)
    storage = LocalMediaStorage(tmp_path)
    provider = FakeProvider(
        failure=AcquisitionFailure("provider_failed", "Provider failed safely.")
    )
    job = enqueue(selected, postgres_session_factory, provider)

    first_worker = worker(selected, postgres_session_factory, storage, provider)
    assert first_worker.process_one()
    with postgres_session_factory() as session:
        stored = AcquisitionJobRepository(session).get(job.id)
        assert stored is not None and stored.state == "queued"

    restarted_worker = worker(selected, postgres_session_factory, storage, provider)
    assert restarted_worker.process_one()
    with postgres_session_factory() as session:
        stored = AcquisitionJobRepository(session).get(job.id)
        assert stored is not None and stored.state == "failed"
        assert stored.failure_code == "provider_failed"
        assert "private" not in (stored.failure_message or "")


def test_retention_deletes_only_old_terminal_jobs_and_keeps_tracks(
    postgres_session_factory: sessionmaker[Session], tmp_path: Path
) -> None:
    selected = settings(tmp_path)
    storage = LocalMediaStorage(tmp_path)
    provider = FakeProvider()
    job = enqueue(selected, postgres_session_factory, provider)
    active_worker = worker(selected, postgres_session_factory, storage, provider)
    active_worker.process_one()
    abandoned = storage.create_workspace()
    old = datetime.now(UTC) - timedelta(days=8)
    abandoned_path = storage.workspace_path(abandoned)
    os.utime(abandoned_path, (old.timestamp(), old.timestamp()))
    with postgres_session_factory() as session, session.begin():
        stored = AcquisitionJobRepository(session).get(job.id)
        assert stored is not None
        stored.updated_at = old

    assert active_worker.purge_retained_jobs() == 1
    with postgres_session_factory() as session:
        assert AcquisitionJobRepository(session).get(job.id) is None
        assert session.scalar(select(func.count()).select_from(Track)) == 1
    assert not abandoned_path.exists()
