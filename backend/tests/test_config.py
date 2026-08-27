import pytest
from pydantic import ValidationError

from arion_api.config import Settings


def test_settings_use_development_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("ARION_ENVIRONMENT", raising=False)
    monkeypatch.delenv("ARION_LOG_LEVEL", raising=False)
    monkeypatch.delenv("ARION_MEDIA_ROOT", raising=False)
    monkeypatch.delenv("ARION_MAX_UPLOAD_BYTES", raising=False)
    monkeypatch.delenv("ARION_FFPROBE_EXECUTABLE", raising=False)
    monkeypatch.delenv("ARION_FFPROBE_TIMEOUT_SECONDS", raising=False)
    monkeypatch.delenv("ARION_RECONCILIATION_GRACE_SECONDS", raising=False)
    monkeypatch.delenv("ARION_CORS_ORIGINS", raising=False)

    settings = Settings(_env_file=None)

    assert settings.environment == "development"
    assert settings.log_level == "INFO"
    assert settings.media_root.as_posix() == "data/media"
    assert settings.max_upload_bytes == 500 * 1024 * 1024
    assert settings.ffprobe_executable == "ffprobe"
    assert settings.ffprobe_timeout_seconds == 30
    assert settings.reconciliation_grace_seconds == 3600
    assert settings.cors_origins == []
    assert settings.youtube_acquisition_enabled is False
    assert settings.youtube_candidate_limit == 5
    assert settings.youtube_max_duration_seconds == 900
    assert settings.youtube_max_output_bytes == 100 * 1024 * 1024
    assert settings.youtube_job_max_attempts == 2


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("http://localhost:8080", ["http://localhost:8080"]),
        (
            "http://localhost:8080, https://arion.test/",
            ["http://localhost:8080", "https://arion.test"],
        ),
    ],
)
def test_settings_parse_exact_cors_origins(
    monkeypatch: pytest.MonkeyPatch, raw: str, expected: list[str]
) -> None:
    monkeypatch.setenv("ARION_CORS_ORIGINS", raw)

    assert Settings(_env_file=None).cors_origins == expected


@pytest.mark.parametrize(
    "origin",
    [
        "localhost:8080",
        "ftp://arion.test",
        "http://user:password@arion.test",
        "http://arion.test/path",
        "http://arion.test?query=value",
    ],
)
def test_settings_reject_invalid_cors_origins(
    monkeypatch: pytest.MonkeyPatch, origin: str
) -> None:
    monkeypatch.setenv("ARION_CORS_ORIGINS", origin)

    with pytest.raises(ValidationError, match="cors_origins"):
        Settings(_env_file=None)


def test_settings_reject_invalid_log_level(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ARION_LOG_LEVEL", "VERBOSE")

    with pytest.raises(ValidationError, match="log_level"):
        Settings(_env_file=None)


def test_settings_accept_environment_overrides(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ARION_MEDIA_ROOT", "custom/media")
    monkeypatch.setenv("ARION_MAX_UPLOAD_BYTES", "1024")
    monkeypatch.setenv("ARION_FFPROBE_TIMEOUT_SECONDS", "2.5")
    monkeypatch.setenv("ARION_RECONCILIATION_GRACE_SECONDS", "0")
    monkeypatch.setenv(
        "ARION_DATABASE_URL",
        "postgresql+psycopg://private-user:private-password@db/arion",
    )

    settings = Settings(_env_file=None)

    assert settings.media_root.as_posix() == "custom/media"
    assert settings.max_upload_bytes == 1024
    assert settings.ffprobe_timeout_seconds == 2.5
    assert settings.reconciliation_grace_seconds == 0
    assert "private-password" not in repr(settings.database_url)


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("ARION_MAX_UPLOAD_BYTES", "0"),
        ("ARION_FFPROBE_TIMEOUT_SECONDS", "0"),
        ("ARION_RECONCILIATION_GRACE_SECONDS", "-1"),
    ],
)
def test_settings_reject_invalid_resource_limits(
    monkeypatch: pytest.MonkeyPatch,
    name: str,
    value: str,
) -> None:
    monkeypatch.setenv(name, value)

    with pytest.raises(ValidationError) as error:
        Settings(_env_file=None)

    assert "private-password" not in str(error.value)


def test_settings_require_strong_secret_when_acquisition_is_enabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ARION_YOUTUBE_ACQUISITION_ENABLED", "true")
    monkeypatch.setenv("ARION_YOUTUBE_CANDIDATE_SECRET", "short")

    with pytest.raises(ValidationError, match="candidate_secret"):
        Settings(_env_file=None)

    monkeypatch.setenv("ARION_YOUTUBE_CANDIDATE_SECRET", "x" * 32)
    settings = Settings(_env_file=None)
    assert settings.youtube_acquisition_enabled is True


def test_settings_reject_unsafe_acquisition_limit_combinations(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ARION_YOUTUBE_ACQUISITION_ENABLED", "true")
    monkeypatch.setenv("ARION_YOUTUBE_CANDIDATE_SECRET", "x" * 32)
    monkeypatch.setenv("ARION_YOUTUBE_MAX_OUTPUT_BYTES", "600000000")

    with pytest.raises(ValidationError, match="max_output"):
        Settings(_env_file=None)
