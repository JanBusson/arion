from __future__ import annotations

import threading
import time
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from arion_api.db import session_scope
from arion_api.models import AcquisitionJob, Track, TrackSource
from arion_api.repository import AcquisitionJobRepository, TrackRepository
from arion_api.schemas import TrackResponse


def make_track(
    *, digest: str, title: str = "Title", artist: str = "Artist", album: str = "Album"
) -> Track:
    return Track(
        sha256=digest,
        audio_storage_key=f"audio/{uuid4().hex}.flac",
        title=title,
        artist=artist,
        album=album,
        duration_ms=1000,
        codec="flac",
        bitrate_kbps=700,
        sample_rate_hz=44100,
        original_filename="track.flac",
    )


def test_session_scope_closes_on_success_and_failure() -> None:
    class FakeSession:
        closed = False

        def close(self) -> None:
            self.closed = True

    successful = FakeSession()
    scope = session_scope(lambda: successful)  # type: ignore[arg-type]
    assert next(scope) is successful
    with pytest.raises(StopIteration):
        next(scope)
    assert successful.closed

    failing = FakeSession()
    scope = session_scope(lambda: failing)  # type: ignore[arg-type]
    next(scope)
    with pytest.raises(RuntimeError):
        scope.throw(RuntimeError("failure"))
    assert failing.closed


def test_repository_crud_search_pagination_and_unique_digest(
    postgres_session_factory: sessionmaker[Session],
) -> None:
    with postgres_session_factory() as session, session.begin():
        repository = TrackRepository(session)
        first = repository.add(
            make_track(digest="1" * 64, title="100% Real", artist="Alpha_Beta")
        )
        second = repository.add(
            make_track(digest="2" * 64, title="Other", artist="Case Artist")
        )
        first.created_at = datetime.now(UTC) - timedelta(seconds=1)
        second.created_at = datetime.now(UTC)

    with postgres_session_factory() as session:
        repository = TrackRepository(session)
        items, total = repository.list(query=None, limit=1, offset=0)
        assert total == 2
        assert [item.id for item in items] == [second.id]
        assert repository.list(query="case", limit=50, offset=0)[1] == 1
        assert repository.list(query="%", limit=50, offset=0)[1] == 1
        assert repository.list(query="_", limit=50, offset=0)[1] == 1

    with postgres_session_factory() as session, session.begin():
        repository = TrackRepository(session)
        current = repository.get(first.id)
        assert current is not None
        previous = current.updated_at
        repository.update_text(
            current, title="Corrected", artist=None, album=None
        )
        assert current.title == "Corrected"
        assert current.updated_at >= previous
        payload = TrackResponse.model_validate(current).model_dump()
        assert "sha256" not in payload
        assert "audio_storage_key" not in payload

    with pytest.raises(IntegrityError):
        with postgres_session_factory() as session, session.begin():
            TrackRepository(session).add(make_track(digest="1" * 64))


def test_digest_advisory_lock_serializes_contenders(
    postgres_session_factory: sessionmaker[Session],
) -> None:
    digest = "f" * 64
    first_locked = threading.Event()
    allow_first_release = threading.Event()
    second_locked = threading.Event()

    def first() -> None:
        with postgres_session_factory() as session, session.begin():
            TrackRepository(session).lock_digest(digest)
            first_locked.set()
            allow_first_release.wait(timeout=5)

    def second() -> None:
        first_locked.wait(timeout=5)
        with postgres_session_factory() as session, session.begin():
            TrackRepository(session).lock_digest(digest)
            second_locked.set()

    first_thread = threading.Thread(target=first)
    second_thread = threading.Thread(target=second)
    first_thread.start()
    second_thread.start()
    assert first_locked.wait(timeout=5)
    time.sleep(0.2)
    assert not second_locked.is_set()
    allow_first_release.set()
    first_thread.join(timeout=5)
    second_thread.join(timeout=5)
    assert second_locked.is_set()


def make_job(external_id: str = "abcdefghijk") -> AcquisitionJob:
    now = datetime.now(UTC)
    return AcquisitionJob(
        provider="youtube",
        external_id=external_id,
        candidate_title="Song",
        candidate_channel="Artist",
        candidate_duration_seconds=120,
        candidate_thumbnail_url=None,
        candidate_page_url=f"https://www.youtube.com/watch?v={external_id}",
        authorization_acknowledged_at=now,
        state="queued",
        phase="queued",
        progress_percent=0,
        attempts=0,
        updated_at=now,
    )


def test_acquisition_repository_lifecycle_and_provenance(
    postgres_session_factory: sessionmaker[Session],
) -> None:
    with postgres_session_factory() as session, session.begin():
        repository = AcquisitionJobRepository(session)
        job = repository.add(make_job())
        track = TrackRepository(session).add(make_track(digest="3" * 64))

    now = datetime.now(UTC)
    with postgres_session_factory() as session, session.begin():
        repository = AcquisitionJobRepository(session)
        claimed = repository.claim(
            now=now, lease_until=now + timedelta(minutes=1), max_attempts=2
        )
        assert claimed is not None
        assert claimed.id == job.id
        assert claimed.state == "downloading"
        assert claimed.attempts == 1
        repository.set_phase(
            claimed,
            state="processing",
            phase="importing",
            progress_percent=85,
            now=now,
        )
        repository.add_source(
            TrackSource(
                track_id=track.id,
                provider="youtube",
                external_id="abcdefghijk",
                source_page_url="https://www.youtube.com/watch?v=abcdefghijk",
                source_title="Song",
                source_channel="Artist",
            )
        )
        repository.complete(claimed, track.id, now=now)

    with postgres_session_factory() as session:
        stored = AcquisitionJobRepository(session).get(job.id)
        assert stored is not None
        assert stored.state == "completed"
        assert stored.track_id == track.id
        source = AcquisitionJobRepository(session).find_source(
            "youtube", "abcdefghijk"
        )
        assert source is not None and source.track_id == track.id


def test_concurrent_job_claim_has_single_owner(
    postgres_session_factory: sessionmaker[Session],
) -> None:
    with postgres_session_factory() as session, session.begin():
        AcquisitionJobRepository(session).add(make_job("concurrent1"))

    first_claimed = threading.Event()
    release_first = threading.Event()
    results: list[bool] = []

    def first() -> None:
        now = datetime.now(UTC)
        with postgres_session_factory() as session, session.begin():
            job = AcquisitionJobRepository(session).claim(
                now=now, lease_until=now + timedelta(minutes=1), max_attempts=2
            )
            results.append(job is not None)
            first_claimed.set()
            release_first.wait(timeout=5)

    def second() -> None:
        first_claimed.wait(timeout=5)
        now = datetime.now(UTC)
        with postgres_session_factory() as session, session.begin():
            job = AcquisitionJobRepository(session).claim(
                now=now, lease_until=now + timedelta(minutes=1), max_attempts=2
            )
            results.append(job is not None)

    threads = [threading.Thread(target=first), threading.Thread(target=second)]
    for thread in threads:
        thread.start()
    first_claimed.wait(timeout=5)
    threads[1].join(timeout=5)
    release_first.set()
    threads[0].join(timeout=5)

    assert sorted(results) == [False, True]


def test_expired_lease_at_retry_limit_becomes_terminal_failure(
    postgres_session_factory: sessionmaker[Session],
) -> None:
    now = datetime.now(UTC)
    exhausted = make_job("exhausted01")
    exhausted.state = "downloading"
    exhausted.phase = "claimed"
    exhausted.attempts = 2
    exhausted.lease_expires_at = now - timedelta(seconds=1)
    with postgres_session_factory() as session, session.begin():
        session.add(exhausted)

    with postgres_session_factory() as session, session.begin():
        assert (
            AcquisitionJobRepository(session).claim(
                now=now,
                lease_until=now + timedelta(minutes=1),
                max_attempts=2,
            )
            is None
        )

    with postgres_session_factory() as session:
        stored = AcquisitionJobRepository(session).get(exhausted.id)
        assert stored is not None
        assert stored.state == "failed"
        assert stored.failure_code == "retry_exhausted"
