from __future__ import annotations

import json
from pathlib import Path

import pytest

from arion_api import acquisition_smoke
from arion_api.acquisition_types import DiscoveryMode
from arion_api.config import Settings


def settings(tmp_path: Path, *, enabled: bool = False) -> Settings:
    return Settings(
        _env_file=None,
        media_root=tmp_path,
        youtube_acquisition_enabled=enabled,
        youtube_candidate_secret="x" * 32,
    )


def test_toolchain_inspection_uses_fixed_version_commands(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    commands: list[list[str]] = []

    def fake_run(command: list[str], **_: object) -> object:
        commands.append(command)
        return type("Completed", (), {"returncode": 0, "stdout": "1.2.3\n", "stderr": ""})()

    monkeypatch.setattr(acquisition_smoke.subprocess, "run", fake_run)
    monkeypatch.setattr(acquisition_smoke, "version", lambda _: "1.12.2")

    assert acquisition_smoke.inspect_toolchain(settings(tmp_path)) == {
        "yt_dlp": "1.2.3",
        "node": "1.2.3",
        "ffmpeg": "1.2.3",
        "ytmusicapi": "1.12.2",
    }
    assert commands == [
        ["yt-dlp", "--version"],
        ["node", "--version"],
        ["ffmpeg", "-version"],
    ]


def test_cli_is_inspection_only_and_does_not_discover_by_default(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    monkeypatch.setattr(acquisition_smoke, "get_settings", lambda: settings(tmp_path))
    monkeypatch.setattr(
        acquisition_smoke,
        "inspect_toolchain",
        lambda _: {"yt_dlp": "x", "node": "y", "ffmpeg": "z"},
    )

    assert acquisition_smoke.main(["--inspection-only"]) == 0

    result = json.loads(capsys.readouterr().out)
    assert result["mode"] == "inspection-only"
    assert result["imported"] is False
    assert "discovery" not in result


def test_online_discovery_requires_authorization_acknowledgement(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(acquisition_smoke, "get_settings", lambda: settings(tmp_path))
    with pytest.raises(SystemExit):
        acquisition_smoke.main(
            ["--inspection-only", "--authorized-query", "authorized test asset"]
        )


def test_discovery_refuses_to_run_while_feature_is_disabled(tmp_path: Path) -> None:
    with pytest.raises(RuntimeError, match="disabled"):
        acquisition_smoke.inspect_discovery(settings(tmp_path), "authorized asset")


@pytest.mark.parametrize("mode", list(DiscoveryMode))
def test_cli_dispatches_each_authorized_discovery_mode(
    mode: DiscoveryMode,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    tmp_path: Path,
) -> None:
    calls: list[tuple[str, DiscoveryMode]] = []
    monkeypatch.setattr(acquisition_smoke, "get_settings", lambda: settings(tmp_path, enabled=True))
    monkeypatch.setattr(acquisition_smoke, "inspect_toolchain", lambda _: {})
    monkeypatch.setattr(
        acquisition_smoke,
        "inspect_discovery",
        lambda _settings, query, selected_mode: calls.append((query, selected_mode)) or {
            "discovery_mode": selected_mode.value,
            "candidate_count": 0,
            "video_ids": [],
            "imported": False,
        },
    )

    assert acquisition_smoke.main(
        [
            "--inspection-only",
            "--authorized-query",
            "authorized asset",
            "--acknowledge-authorized",
            "--discovery-mode",
            mode.value,
        ]
    ) == 0
    assert calls == [("authorized asset", mode)]
    assert json.loads(capsys.readouterr().out)["discovery"]["discovery_mode"] == mode.value


def test_cli_rejects_unsupported_discovery_mode() -> None:
    with pytest.raises(SystemExit):
        acquisition_smoke.main(
            ["--inspection-only", "--discovery-mode", "videos"]
        )
