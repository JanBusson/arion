"""Application services for recoverable audio import and reconciliation."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import BinaryIO

from sqlalchemy.exc import IntegrityError

from arion_api.db import SessionFactory
from arion_api.errors import DuplicateTrackError, ImportTooLargeError
from arion_api.metadata import MediaInspector
from arion_api.models import Track
from arion_api.repository import TrackRepository
from arion_api.storage import LocalMediaStorage, StorageKey

UPLOAD_CHUNK_BYTES = 1024 * 1024


def safe_original_filename(value: str) -> str:
    normalized = value.replace("\\", "/").rsplit("/", 1)[-1].strip()
    return (normalized or "upload")[:1024]


def stage_upload(
    source: BinaryIO,
    storage: LocalMediaStorage,
    max_upload_bytes: int,
) -> tuple[StorageKey, str]:
    key = storage.create_staging(".upload")
    digest = hashlib.sha256()
    received = 0
    try:
        with storage.open_for_write(key) as destination:
            while True:
                chunk = source.read(UPLOAD_CHUNK_BYTES)
                if not chunk:
                    break
                received += len(chunk)
                if received > max_upload_bytes:
                    raise ImportTooLargeError()
                digest.update(chunk)
                destination.write(chunk)
        return key, digest.hexdigest()
    except BaseException:
        storage.remove(key)
        raise


class ImportService:
    def __init__(
        self,
        session_factory: SessionFactory,
        storage: LocalMediaStorage,
        inspector: MediaInspector,
        max_upload_bytes: int,
    ) -> None:
        self.session_factory = session_factory
        self.storage = storage
        self.inspector = inspector
        self.max_upload_bytes = max_upload_bytes

    def import_file(self, source: BinaryIO, original_filename: str) -> Track:
        filename = safe_original_filename(original_filename)
        stage_key, digest = stage_upload(
            source, self.storage, self.max_upload_bytes
        )
        return self._finalize_staged(stage_key, digest, filename)

    def import_path(self, path: Path, original_filename: str | None = None) -> Track:
        """Import a worker-produced file through the exact upload finalizer."""

        filename = safe_original_filename(original_filename or path.name)
        with path.open("rb") as source:
            stage_key, digest = stage_upload(
                source, self.storage, self.max_upload_bytes
            )
        return self._finalize_staged(stage_key, digest, filename)

    def _finalize_staged(
        self,
        stage_key: StorageKey,
        digest: str,
        filename: str,
    ) -> Track:
        audio_key: StorageKey | None = None
        cover_stage_key: StorageKey | None = None
        cover_key: StorageKey | None = None
        try:
            inspected = self.inspector.inspect(
                self.storage.staged_path(stage_key), filename
            )
            with self.session_factory() as session:
                repository = TrackRepository(session)
                with session.begin():
                    repository.lock_digest(digest)
                    existing = repository.find_by_digest(digest)
                    if existing is not None:
                        raise DuplicateTrackError(existing.id)

                    if inspected.cover is not None:
                        cover_stage_key = self.storage.create_staging(".cover")
                        with self.storage.open_for_write(cover_stage_key) as cover_file:
                            cover_file.write(inspected.cover.data)

                    audio_key = self.storage.promote(
                        stage_key, "audio", inspected.technical.suffix
                    )
                    stage_key = None  # type: ignore[assignment]
                    if cover_stage_key is not None:
                        cover_suffix = (
                            ".png"
                            if inspected.cover
                            and inspected.cover.media_type == "image/png"
                            else ".jpg"
                        )
                        cover_key = self.storage.promote(
                            cover_stage_key, "covers", cover_suffix
                        )
                        cover_stage_key = None

                    track = Track(
                        sha256=digest,
                        audio_storage_key=audio_key.value,
                        cover_storage_key=cover_key.value if cover_key else None,
                        cover_media_type=(
                            inspected.cover.media_type if inspected.cover else None
                        ),
                        title=inspected.title,
                        artist=inspected.artist,
                        album=inspected.album,
                        duration_ms=inspected.technical.duration_ms,
                        codec=inspected.technical.codec,
                        bitrate_kbps=inspected.technical.bitrate_kbps,
                        sample_rate_hz=inspected.technical.sample_rate_hz,
                        original_filename=filename,
                    )
                    repository.add(track)
                return track
        except IntegrityError as error:
            self._remove_uncommitted(audio_key, cover_key)
            with self.session_factory() as lookup_session:
                existing = TrackRepository(lookup_session).find_by_digest(digest)
                if existing is not None:
                    raise DuplicateTrackError(existing.id) from error
            raise
        except BaseException:
            self._remove_uncommitted(audio_key, cover_key)
            raise
        finally:
            if stage_key is not None:
                self.storage.remove(stage_key)
            if cover_stage_key is not None:
                self.storage.remove(cover_stage_key)

    def _remove_uncommitted(
        self, audio_key: StorageKey | None, cover_key: StorageKey | None
    ) -> None:
        for key in (audio_key, cover_key):
            if key is not None:
                self.storage.remove(key)


def reconcile_storage(
    session_factory: SessionFactory,
    storage: LocalMediaStorage,
    grace_seconds: int,
) -> list[StorageKey]:
    """Reconcile only after a successful database reference query."""

    with session_factory() as session:
        references = TrackRepository(session).referenced_storage_keys()
    return storage.reconcile(references, grace_seconds, database_available=True)
