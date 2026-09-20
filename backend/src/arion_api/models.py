"""Database models for the private track catalog."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Track(Base):
    __tablename__ = "tracks"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    sha256: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    audio_storage_key: Mapped[str] = mapped_column(
        String(255), unique=True, nullable=False
    )
    cover_storage_key: Mapped[str | None] = mapped_column(
        String(255), unique=True, nullable=True
    )
    cover_media_type: Mapped[str | None] = mapped_column(String(32), nullable=True)

    title: Mapped[str] = mapped_column(String(512), nullable=False)
    artist: Mapped[str] = mapped_column(String(512), nullable=False)
    album: Mapped[str] = mapped_column(String(512), nullable=False)
    duration_ms: Mapped[int] = mapped_column(BigInteger, nullable=False)
    codec: Mapped[str] = mapped_column(String(64), nullable=False)
    bitrate_kbps: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sample_rate_hz: Mapped[int] = mapped_column(Integer, nullable=False)
    original_filename: Mapped[str] = mapped_column(String(1024), nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    @property
    def has_cover(self) -> bool:
        return self.cover_storage_key is not None


ACQUISITION_JOB_STATES = (
    "queued",
    "downloading",
    "processing",
    "completed",
    "failed",
    "cancelled",
)


class AcquisitionJob(Base):
    __tablename__ = "acquisition_jobs"
    __table_args__ = (
        CheckConstraint(
            "state IN ('queued', 'downloading', 'processing', "
            "'completed', 'failed', 'cancelled')",
            name="ck_acquisition_jobs_state",
        ),
        CheckConstraint(
            "progress_percent >= 0 AND progress_percent <= 100",
            name="ck_acquisition_jobs_progress_percent",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    external_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    candidate_title: Mapped[str] = mapped_column(String(512), nullable=False)
    candidate_channel: Mapped[str] = mapped_column(String(512), nullable=False)
    candidate_duration_seconds: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )
    candidate_thumbnail_url: Mapped[str | None] = mapped_column(
        String(2048), nullable=True
    )
    candidate_page_url: Mapped[str] = mapped_column(String(2048), nullable=False)
    authorization_acknowledged_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    state: Mapped[str] = mapped_column(
        String(32), nullable=False, default="queued", index=True
    )
    phase: Mapped[str] = mapped_column(String(64), nullable=False, default="queued")
    progress_percent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    failure_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    failure_message: Mapped[str | None] = mapped_column(String(512), nullable=True)
    track_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("tracks.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class TrackSource(Base):
    __tablename__ = "track_sources"
    __table_args__ = (
        UniqueConstraint("provider", "external_id", name="uq_track_sources_origin"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    track_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("tracks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    external_id: Mapped[str] = mapped_column(String(64), nullable=False)
    source_page_url: Mapped[str] = mapped_column(String(2048), nullable=False)
    source_title: Mapped[str] = mapped_column(String(512), nullable=False)
    source_channel: Mapped[str] = mapped_column(String(512), nullable=False)
    acquired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
