"""Durable single-concurrency acquisition worker."""

from __future__ import annotations

import logging
import threading
import time
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy.exc import IntegrityError

from arion_api.acquisition_provider import BoundedProcessRunner, YouTubeProvider
from arion_api.config import Settings, get_settings
from arion_api.db import SessionFactory, create_database_engine, create_session_factory
from arion_api.errors import AcquisitionFailure, DuplicateTrackError
from arion_api.logging_config import configure_structured_logging
from arion_api.media_normalization import AudioNormalizer
from arion_api.metadata import MediaInspector
from arion_api.models import AcquisitionJob, TrackSource
from arion_api.repository import AcquisitionJobRepository
from arion_api.services import ImportService
from arion_api.storage import LocalMediaStorage, StagingWorkspace

logger = logging.getLogger(__name__)


def acquisition_filename(job: AcquisitionJob, suffix: str) -> str:
    """Build a safe metadata-fallback filename from the approved candidate."""

    channel = " ".join(
        job.candidate_channel.replace("/", " ").replace("\\", " ").split()
    )
    title = " ".join(
        job.candidate_title.replace("/", " ").replace("\\", " ").split()
    )
    stem = f"{channel or 'Unknown Artist'} - {title or 'Untitled video'}"
    bounded = stem[: 1024 - len(suffix)].rstrip()
    return f"{bounded}{suffix}"


class AcquisitionWorker:
    TRANSIENT_FAILURES = {
        "provider_failed",
        "candidate_unavailable",
        "acquisition_timeout",
    }

    def __init__(
        self,
        settings: Settings,
        session_factory: SessionFactory,
        storage: LocalMediaStorage,
        provider: YouTubeProvider,
        normalizer: AudioNormalizer,
        import_service: ImportService,
    ) -> None:
        self.settings = settings
        self.session_factory = session_factory
        self.storage = storage
        self.provider = provider
        self.normalizer = normalizer
        self.import_service = import_service

    def process_one(self) -> bool:
        now = datetime.now(UTC)
        with self.session_factory() as session, session.begin():
            job = AcquisitionJobRepository(session).claim(
                now=now,
                lease_until=now
                + timedelta(seconds=self.settings.youtube_job_lease_seconds),
                max_attempts=self.settings.youtube_job_max_attempts,
            )
            if job is None:
                return False
            job_id = job.id

        heartbeat_stop = threading.Event()
        heartbeat = threading.Thread(
            target=self._heartbeat,
            args=(job_id, heartbeat_stop),
            daemon=True,
        )
        heartbeat.start()
        workspace: StagingWorkspace | None = None
        try:
            existing_track_id = self._existing_source_track(job_id)
            if existing_track_id is not None:
                self._complete(job_id, existing_track_id, add_source=False)
                return True

            job = self._get(job_id)
            fresh = self.provider.revalidate(job.external_id)
            workspace = self.storage.create_workspace()
            logger.info(
                "acquisition_job_downloading",
                extra={"event": "acquisition_job_downloading", "job_id": str(job_id)},
            )
            downloaded = self.provider.download(
                fresh.external_id,
                self.storage.workspace_path(workspace),
                job_id=job_id,
            )
            self._phase(job_id, "processing", "normalizing", 70)
            normalized = self.normalizer.normalize(downloaded, job_id=job_id)
            self.storage.workspace_files(
                workspace,
                max_total_bytes=self.settings.youtube_max_output_bytes,
            )
            self._phase(job_id, "processing", "importing", 85)
            try:
                track = self.import_service.import_path(
                    normalized,
                    acquisition_filename(job, normalized.suffix),
                )
                track_id = track.id
            except DuplicateTrackError as duplicate:
                track_id = duplicate.existing_track_id
            self._complete(job_id, track_id, add_source=True)
            logger.info(
                "acquisition_job_completed",
                extra={"event": "acquisition_job_completed", "job_id": str(job_id)},
            )
        except AcquisitionFailure as error:
            self._handle_failure(job_id, error)
        except Exception:
            logger.exception(
                "acquisition_job_unexpected_failure",
                extra={"event": "acquisition_job_unexpected_failure", "job_id": str(job_id)},
            )
            self._handle_failure(
                job_id,
                AcquisitionFailure(
                    "internal_acquisition_error",
                    "The acquisition could not be completed.",
                ),
            )
        finally:
            heartbeat_stop.set()
            heartbeat.join(timeout=2)
            if workspace is not None:
                self.storage.remove_workspace(workspace)
        return True

    def _heartbeat(self, job_id: UUID, stop: threading.Event) -> None:
        interval = max(5.0, self.settings.youtube_job_lease_seconds / 3)
        while not stop.wait(interval):
            now = datetime.now(UTC)
            try:
                with self.session_factory() as session, session.begin():
                    job = AcquisitionJobRepository(session).get(job_id)
                    if job is None or job.state not in ("downloading", "processing"):
                        return
                    AcquisitionJobRepository(session).renew(
                        job,
                        now=now,
                        lease_until=now
                        + timedelta(seconds=self.settings.youtube_job_lease_seconds),
                    )
            except Exception:
                logger.warning(
                    "acquisition_job_heartbeat_failed",
                    extra={"event": "acquisition_job_heartbeat_failed", "job_id": str(job_id)},
                )

    def _get(self, job_id: UUID) -> AcquisitionJob:
        with self.session_factory() as session:
            job = AcquisitionJobRepository(session).get(job_id)
            if job is None:
                raise RuntimeError("claimed acquisition job disappeared")
            session.expunge(job)
            return job

    def _existing_source_track(self, job_id: UUID) -> UUID | None:
        with self.session_factory() as session:
            job = AcquisitionJobRepository(session).get(job_id)
            if job is None:
                return None
            source = AcquisitionJobRepository(session).find_source(
                job.provider, job.external_id
            )
            return source.track_id if source else None

    def _phase(self, job_id: UUID, state: str, phase: str, progress: int) -> None:
        now = datetime.now(UTC)
        with self.session_factory() as session, session.begin():
            job = AcquisitionJobRepository(session).get(job_id)
            if job is None:
                raise RuntimeError("acquisition job disappeared")
            AcquisitionJobRepository(session).set_phase(
                job,
                state=state,
                phase=phase,
                progress_percent=progress,
                now=now,
            )
        logger.info(
            "acquisition_job_phase_changed",
            extra={
                "event": "acquisition_job_phase_changed",
                "job_id": str(job_id),
                "state": state,
                "phase": phase,
                "progress_percent": progress,
            },
        )

    def _complete(self, job_id: UUID, track_id: UUID, *, add_source: bool) -> None:
        now = datetime.now(UTC)
        try:
            with self.session_factory() as session, session.begin():
                repository = AcquisitionJobRepository(session)
                job = repository.get(job_id)
                if job is None:
                    raise RuntimeError("acquisition job disappeared")
                repository.lock_origin(job.provider, job.external_id)
                source = repository.find_source(job.provider, job.external_id)
                resolved_track_id = source.track_id if source else track_id
                if source is None and add_source:
                    repository.add_source(
                        TrackSource(
                            track_id=track_id,
                            provider=job.provider,
                            external_id=job.external_id,
                            source_page_url=job.candidate_page_url,
                            source_title=job.candidate_title,
                            source_channel=job.candidate_channel,
                            acquired_at=now,
                        )
                    )
                repository.complete(job, resolved_track_id, now=now)
        except IntegrityError:
            with self.session_factory() as session, session.begin():
                repository = AcquisitionJobRepository(session)
                job = repository.get(job_id)
                if job is None:
                    raise
                source = repository.find_source(job.provider, job.external_id)
                if source is None:
                    raise
                repository.complete(job, source.track_id, now=now)

    def _handle_failure(self, job_id: UUID, error: AcquisitionFailure) -> None:
        now = datetime.now(UTC)
        retried = False
        attempt = 0
        with self.session_factory() as session, session.begin():
            repository = AcquisitionJobRepository(session)
            job = repository.get(job_id)
            if job is None or job.state not in ("downloading", "processing"):
                return
            attempt = job.attempts
            if (
                error.code in self.TRANSIENT_FAILURES
                and job.attempts < self.settings.youtube_job_max_attempts
            ):
                repository.retry(job, now=now)
                retried = True
            else:
                repository.fail(
                    job,
                    code=error.code,
                    message=error.public_message,
                    now=now,
                )
        logger.warning(
            "acquisition_job_retrying" if retried else "acquisition_job_failed",
            extra={
                "event": (
                    "acquisition_job_retrying" if retried else "acquisition_job_failed"
                ),
                "job_id": str(job_id),
                "failure_code": error.code,
                "attempt": attempt,
                "will_retry": retried,
            },
        )

    def purge_retained_jobs(self) -> int:
        cutoff = datetime.now(UTC) - timedelta(
            seconds=self.settings.youtube_job_retention_seconds
        )
        removed_workspaces = self.storage.purge_workspaces_older_than(cutoff)
        with self.session_factory() as session, session.begin():
            removed_jobs = AcquisitionJobRepository(session).delete_terminal_before(cutoff)
        logger.info(
            "acquisition_retention_completed",
            extra={
                "event": "acquisition_retention_completed",
                "removed_jobs": removed_jobs,
                "removed_workspaces": removed_workspaces,
            },
        )
        return removed_jobs


def build_worker(settings: Settings | None = None) -> AcquisitionWorker:
    selected = settings or get_settings()
    factory = create_session_factory(create_database_engine(selected))
    storage = LocalMediaStorage(selected.media_root)
    provider = YouTubeProvider(
        selected.ytdlp_executable,
        BoundedProcessRunner(),
        candidate_limit=selected.youtube_candidate_limit,
        discovery_timeout_seconds=selected.youtube_discovery_timeout_seconds,
        download_timeout_seconds=selected.youtube_download_timeout_seconds,
        max_duration_seconds=selected.youtube_max_duration_seconds,
        max_output_bytes=selected.youtube_max_output_bytes,
        min_free_bytes=selected.youtube_min_free_bytes,
    )
    inspector = MediaInspector(
        selected.ffprobe_executable, selected.ffprobe_timeout_seconds
    )
    return AcquisitionWorker(
        selected,
        factory,
        storage,
        provider,
        AudioNormalizer(
            selected.ffmpeg_executable,
            selected.youtube_processing_timeout_seconds,
        ),
        ImportService(factory, storage, inspector, selected.max_upload_bytes),
    )


def main() -> None:
    settings = get_settings()
    configure_structured_logging(settings.log_level)
    if not settings.youtube_acquisition_enabled:
        logger.info("youtube acquisition disabled; worker idle")
        while True:
            time.sleep(3600)
    worker = build_worker(settings)
    idle_cycles = 0
    while True:
        if worker.process_one():
            idle_cycles = 0
            continue
        idle_cycles += 1
        if idle_cycles % 300 == 0:
            worker.purge_retained_jobs()
        time.sleep(settings.youtube_worker_poll_seconds)


if __name__ == "__main__":
    main()
