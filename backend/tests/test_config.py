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

    settings = Settings(_env_file=None)

    assert settings.environment == "development"
    assert settings.log_level == "INFO"
    assert settings.media_root.as_posix() == "data/media"
    assert settings.max_upload_bytes == 500 * 1024 * 1024
    assert settings.ffprobe_executable == "ffprobe"
    assert settings.ffprobe_timeout_seconds == 30
    assert settings.reconciliation_grace_seconds == 3600


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
