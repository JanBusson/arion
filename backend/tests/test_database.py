from __future__ import annotations

import threading
import time
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from arion_api.db import session_scope
from arion_api.models import Track
from arion_api.repository import TrackRepository
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
