"""Application configuration loaded from environment variables."""

from functools import lru_cache
from pathlib import Path
from typing import Annotated, Literal
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator
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
    ffprobe_timeout_seconds: float = Field(default=30.0, gt=0)
    reconciliation_grace_seconds: int = Field(default=3600, ge=0)
    cors_origins: Annotated[list[str], NoDecode] = Field(default_factory=list)

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


@lru_cache
def get_settings() -> Settings:
    """Return one validated settings instance per application process."""

    return Settings()
