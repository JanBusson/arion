from __future__ import annotations

import pytest

from arion_api import server
from arion_api.config import Settings


def test_server_uses_sanitized_logging_without_access_log(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    configured: list[str] = []
    calls: list[tuple[str, dict[str, object]]] = []
    monkeypatch.setattr(
        server,
        "get_settings",
        lambda: Settings(_env_file=None, log_level="WARNING"),
    )
    monkeypatch.setattr(
        server,
        "configure_structured_logging",
        lambda level: configured.append(level),
    )
    monkeypatch.setattr(
        server.uvicorn,
        "run",
        lambda application, **kwargs: calls.append((application, kwargs)),
    )

    server.main()

    assert configured == ["WARNING"]
    assert calls == [
        (
            "arion_api.main:app",
            {
                "host": "0.0.0.0",
                "port": 8000,
                "access_log": False,
                "log_config": None,
            },
        )
    ]
