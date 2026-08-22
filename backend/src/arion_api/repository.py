"""PostgreSQL repository for tracks."""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import Select, func, or_, select, text
from sqlalchemy.orm import Session

from arion_api.models import Track


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
