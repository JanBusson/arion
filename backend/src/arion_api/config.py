"""Application configuration loaded from environment variables."""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


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

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="ARION_",
        extra="ignore",
        case_sensitive=False,
    )


@lru_cache
def get_settings() -> Settings:
    """Return one validated settings instance per application process."""

    return Settings()
