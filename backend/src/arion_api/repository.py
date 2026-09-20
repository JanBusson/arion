"""PostgreSQL repository for tracks."""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import Select, delete, func, or_, select, text, update
from sqlalchemy.orm import Session

from arion_api.models import AcquisitionJob, Track, TrackSource


def _escape_like(value: str) -> str:
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


class TrackRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get(self, track_id: UUID) -> Track | None:
        return self.session.get(Track, track_id)

    def find_by_digest(self, digest: str) -> Track | None:
        return self.session.scalar(select(Track).where(Track.sha256 == digest))

    def add(self, track: Track) -> Track:
        self.session.add(track)
        self.session.flush()
        return track

    def list(
        self,
        *,
        query: str | None,
        limit: int,
        offset: int,
    ) -> tuple[list[Track], int]:
        statement: Select[tuple[Track]] = select(Track)
        count_statement = select(func.count()).select_from(Track)
        normalized = query.strip() if query else ""
        if normalized:
            pattern = f"%{_escape_like(normalized)}%"
            predicate = or_(
                Track.title.ilike(pattern, escape="\\"),
                Track.artist.ilike(pattern, escape="\\"),
                Track.album.ilike(pattern, escape="\\"),
            )
            statement = statement.where(predicate)
            count_statement = count_statement.where(predicate)
        total = int(self.session.scalar(count_statement) or 0)
        statement = statement.order_by(Track.created_at.desc(), Track.id.desc())
        items = list(self.session.scalars(statement.limit(limit).offset(offset)))
        return items, total

    def update_text(
        self,
        track: Track,
        *,
        title: str | None,
        artist: str | None,
        album: str | None,
    ) -> Track:
        if title is not None:
            track.title = title
        if artist is not None:
            track.artist = artist
        if album is not None:
            track.album = album
        track.updated_at = datetime.now(UTC)
        self.session.flush()
        return track

    def lock_digest(self, digest: str) -> None:
        lock_id = int(digest[:16], 16)
        if lock_id >= 2**63:
            lock_id -= 2**64
        self.session.execute(
            text("SELECT pg_advisory_xact_lock(:lock_id)"),
            {"lock_id": lock_id},
        )

    def referenced_storage_keys(self) -> set[str]:
        rows = self.session.execute(
            select(Track.audio_storage_key, Track.cover_storage_key)
        )
        references: set[str] = set()
        for audio_key, cover_key in rows:
            references.add(audio_key)
            if cover_key:
                references.add(cover_key)
        return references


class AcquisitionJobRepository:
    ACTIVE_STATES = ("queued", "downloading", "processing")

    def __init__(self, session: Session) -> None:
        self.session = session

    def get(self, job_id: UUID) -> AcquisitionJob | None:
        return self.session.get(AcquisitionJob, job_id)

    def add(self, job: AcquisitionJob) -> AcquisitionJob:
        self.session.add(job)
        self.session.flush()
        return job

    def lock_origin(self, provider: str, external_id: str) -> None:
        identity = f"{provider}:{external_id}"
        self.session.execute(
            text("SELECT pg_advisory_xact_lock(hashtextextended(:identity, 0))"),
            {"identity": identity},
        )

    def find_active(self, provider: str, external_id: str) -> AcquisitionJob | None:
        return self.session.scalar(
            select(AcquisitionJob)
            .where(
                AcquisitionJob.provider == provider,
                AcquisitionJob.external_id == external_id,
                AcquisitionJob.state.in_(self.ACTIVE_STATES),
            )
            .order_by(AcquisitionJob.created_at.desc())
            .limit(1)
        )

    def find_source(self, provider: str, external_id: str) -> TrackSource | None:
        return self.session.scalar(
            select(TrackSource).where(
                TrackSource.provider == provider,
                TrackSource.external_id == external_id,
            )
        )

    def add_source(self, source: TrackSource) -> TrackSource:
        self.session.add(source)
        self.session.flush()
        return source

    def claim(
        self,
        *,
        now: datetime,
        lease_until: datetime,
        max_attempts: int,
    ) -> AcquisitionJob | None:
        self.session.execute(
            update(AcquisitionJob)
            .where(
                AcquisitionJob.state.in_(("downloading", "processing")),
                AcquisitionJob.lease_expires_at < now,
                AcquisitionJob.attempts >= max_attempts,
            )
            .values(
                state="failed",
                phase="failed",
                lease_expires_at=None,
                failure_code="retry_exhausted",
                failure_message="The acquisition could not be completed after retrying.",
                updated_at=now,
            )
        )
        claimable = or_(
            AcquisitionJob.state == "queued",
            (
                AcquisitionJob.state.in_(("downloading", "processing"))
                & (AcquisitionJob.lease_expires_at < now)
            ),
        )
        job = self.session.scalar(
            select(AcquisitionJob)
            .where(claimable, AcquisitionJob.attempts < max_attempts)
            .order_by(AcquisitionJob.created_at, AcquisitionJob.id)
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        if job is None:
            return None
        job.state = "downloading"
        job.phase = "claimed"
        job.progress_percent = max(job.progress_percent, 1)
        job.attempts += 1
        job.lease_expires_at = lease_until
        job.failure_code = None
        job.failure_message = None
        job.updated_at = now
        self.session.flush()
        return job

    def renew(self, job: AcquisitionJob, *, now: datetime, lease_until: datetime) -> None:
        if job.state not in ("downloading", "processing"):
            raise ValueError("only active jobs can renew a lease")
        job.lease_expires_at = lease_until
        job.updated_at = now
        self.session.flush()

    def set_phase(
        self,
        job: AcquisitionJob,
        *,
        state: str,
        phase: str,
        progress_percent: int,
        now: datetime,
    ) -> None:
        if job.state not in ("downloading", "processing"):
            raise ValueError("only active jobs can change phase")
        if state not in ("downloading", "processing"):
            raise ValueError("phase state must remain active")
        job.state = state
        job.phase = phase[:64]
        job.progress_percent = max(0, min(progress_percent, 99))
        job.updated_at = now
        self.session.flush()

    def complete(self, job: AcquisitionJob, track_id: UUID, *, now: datetime) -> None:
        if job.state not in self.ACTIVE_STATES:
            raise ValueError("only active jobs can complete")
        job.state = "completed"
        job.phase = "completed"
        job.progress_percent = 100
        job.track_id = track_id
        job.lease_expires_at = None
        job.failure_code = None
        job.failure_message = None
        job.updated_at = now
        self.session.flush()

    def fail(
        self,
        job: AcquisitionJob,
        *,
        code: str,
        message: str,
        now: datetime,
    ) -> None:
        if job.state not in self.ACTIVE_STATES:
            raise ValueError("only active jobs can fail")
        job.state = "failed"
        job.phase = "failed"
        job.lease_expires_at = None
        job.failure_code = code[:64]
        job.failure_message = message[:512]
        job.updated_at = now
        self.session.flush()

    def retry(self, job: AcquisitionJob, *, now: datetime) -> None:
        if job.state not in ("downloading", "processing"):
            raise ValueError("only active jobs can retry")
        job.state = "queued"
        job.phase = "queued"
        job.progress_percent = 0
        job.lease_expires_at = None
        job.failure_code = None
        job.failure_message = None
        job.updated_at = now
        self.session.flush()

    def cancel(self, job: AcquisitionJob, *, now: datetime) -> None:
        if job.state not in self.ACTIVE_STATES:
            raise ValueError("only active jobs can be cancelled")
        job.state = "cancelled"
        job.phase = "cancelled"
        job.lease_expires_at = None
        job.updated_at = now
        self.session.flush()

    def delete_terminal_before(self, cutoff: datetime) -> int:
        result = self.session.execute(
            delete(AcquisitionJob).where(
                AcquisitionJob.state.in_(("completed", "failed", "cancelled")),
                AcquisitionJob.updated_at < cutoff,
            )
        )
        return int(result.rowcount or 0)
