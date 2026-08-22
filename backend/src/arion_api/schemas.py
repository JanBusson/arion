"""Allow-listed public API schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class TrackResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    artist: str
    album: str
    duration_ms: int
    codec: str
    bitrate_kbps: int | None
    sample_rate_hz: int
    original_filename: str
    has_cover: bool
    created_at: datetime
    updated_at: datetime


class TrackListResponse(BaseModel):
    items: list[TrackResponse]
    total: int
    limit: int
    offset: int


class TrackPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str | None = Field(default=None)
    artist: str | None = Field(default=None)
    album: str | None = Field(default=None)

    @field_validator("title", "artist", "album")
    @classmethod
    def normalize_non_empty(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split())
        if not normalized:
            raise ValueError("value must not be empty")
        return normalized

    @model_validator(mode="after")
    def require_change(self) -> "TrackPatch":
        if self.title is None and self.artist is None and self.album is None:
            raise ValueError("at least one editable field is required")
        return self
