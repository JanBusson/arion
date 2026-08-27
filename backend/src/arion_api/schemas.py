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


class YouTubeCandidateResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    candidate_id: str = Field(min_length=16, max_length=4096)
    video_id: str = Field(pattern=r"^[A-Za-z0-9_-]{11}$")
    title: str = Field(min_length=1, max_length=512)
    channel: str = Field(min_length=1, max_length=512)
    duration_seconds: int | None = Field(default=None, ge=0)
    thumbnail_url: str | None = Field(default=None, max_length=2048)
    page_url: str = Field(min_length=1, max_length=2048)


class YouTubeCandidateListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[YouTubeCandidateResponse]


class AcquisitionJobCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    candidate_id: str = Field(min_length=16, max_length=4096)
    authorization_acknowledged: bool

    @model_validator(mode="after")
    def require_authorization(self) -> "AcquisitionJobCreate":
        if not self.authorization_acknowledged:
            raise ValueError("authorization acknowledgement is required")
        return self


class AcquisitionCandidateSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True, extra="forbid")

    video_id: str
    title: str
    channel: str
    duration_seconds: int | None
    thumbnail_url: str | None
    page_url: str


class AcquisitionJobResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    state: str
    phase: str
    progress_percent: int
    attempts: int
    candidate: AcquisitionCandidateSummary
    track_id: UUID | None
    failure_code: str | None
    failure_message: str | None
    created_at: datetime
    updated_at: datetime
