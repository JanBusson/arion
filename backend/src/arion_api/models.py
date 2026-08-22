"""Database models for the private track catalog."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, DateTime, Integer, String, Uuid, func
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
