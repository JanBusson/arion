"""Application configuration loaded from environment variables."""

from functools import lru_cache
from pathlib import Path
from typing import Annotated, Literal
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    """Validated settings for the Arion API process."""

    environment: Literal["development", "production"] = "development"
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    database_url: SecretStr = SecretStr(
        "postgresql+psycopg://arion:arion@127.0.0.1:5432/arion"
    )
    media_root: Path = Path("data/media")
    max_upload_bytes: int = Field(default=500 * 1024 * 1024, gt=0)
    ffprobe_executable: str = Field(default="ffprobe", min_length=1)
    ffmpeg_executable: str = Field(default="ffmpeg", min_length=1)
    ffprobe_timeout_seconds: float = Field(default=30.0, gt=0)
    reconciliation_grace_seconds: int = Field(default=3600, ge=0)
    cors_origins: Annotated[list[str], NoDecode] = Field(default_factory=list)
    youtube_acquisition_enabled: bool = False
    youtube_candidate_secret: SecretStr = SecretStr("replace-me")
    youtube_candidate_ttl_seconds: int = Field(default=600, ge=60, le=3600)
    youtube_candidate_limit: int = Field(default=5, ge=1, le=5)
    youtube_discovery_timeout_seconds: float = Field(default=20.0, gt=0, le=120)
    youtube_max_duration_seconds: int = Field(default=15 * 60, ge=1, le=6 * 3600)
    youtube_max_output_bytes: int = Field(default=100 * 1024 * 1024, gt=0)
    youtube_min_free_bytes: int = Field(default=1024 * 1024 * 1024, ge=0)
    youtube_download_timeout_seconds: float = Field(default=10 * 60, gt=0)
    youtube_processing_timeout_seconds: float = Field(default=3 * 60, gt=0)
    youtube_job_max_attempts: int = Field(default=2, ge=1, le=5)
    youtube_job_lease_seconds: int = Field(default=120, ge=30, le=3600)
    youtube_job_retention_seconds: int = Field(default=7 * 24 * 3600, ge=3600)
    youtube_worker_poll_seconds: float = Field(default=2.0, ge=0.25, le=60)
    ytdlp_executable: str = Field(default="yt-dlp", min_length=1)

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="ARION_",
        extra="ignore",
        case_sensitive=False,
    )

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, value: object) -> object:
        """Accept a comma-separated environment value or an explicit list."""

        if isinstance(value, str):
            if not value.strip():
                return []
            return [origin.strip() for origin in value.split(",")]
        return value

    @field_validator("cors_origins")
    @classmethod
    def validate_cors_origins(cls, origins: list[str]) -> list[str]:
        """Require normalized HTTP(S) origins without paths or credentials."""

        normalized: list[str] = []
        for origin in origins:
            try:
                parsed = urlsplit(origin)
                port = parsed.port
            except ValueError as error:
                raise ValueError(f"invalid CORS origin: {origin}") from error
            if (
                parsed.scheme not in {"http", "https"}
                or parsed.hostname is None
                or parsed.username is not None
                or parsed.password is not None
                or parsed.path not in {"", "/"}
                or parsed.query
                or parsed.fragment
            ):
                raise ValueError(f"invalid CORS origin: {origin}")
            host = parsed.hostname.lower()
            if ":" in host:
                host = f"[{host}]"
            authority = f"{host}:{port}" if port is not None else host
            exact_origin = f"{parsed.scheme.lower()}://{authority}"
            if exact_origin not in normalized:
                normalized.append(exact_origin)
        return normalized

    @model_validator(mode="after")
    def validate_acquisition_limits(self) -> "Settings":
        if (
            self.youtube_acquisition_enabled
            and self.youtube_max_output_bytes > self.max_upload_bytes
        ):
            raise ValueError(
                "youtube_max_output_bytes must not exceed max_upload_bytes"
            )
        if self.youtube_job_lease_seconds >= self.youtube_download_timeout_seconds:
            raise ValueError(
                "youtube_job_lease_seconds must be shorter than "
                "youtube_download_timeout_seconds"
            )
        if self.youtube_acquisition_enabled:
            secret = self.youtube_candidate_secret.get_secret_value()
            if secret == "replace-me" or len(secret.encode("utf-8")) < 32:
                raise ValueError(
                    "youtube_candidate_secret must contain at least 32 bytes "
                    "when acquisition is enabled"
                )
        return self


@lru_cache
def get_settings() -> Settings:
    """Return one validated settings instance per application process."""

    return Settings()
