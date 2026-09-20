from __future__ import annotations

import logging
from pathlib import Path
from types import SimpleNamespace

import pytest
from pytest import MonkeyPatch

import arion_api.media_normalization as module
from arion_api.media_normalization import AudioNormalizer


def test_supported_audio_is_not_transcoded(tmp_path: Path) -> None:
    source = tmp_path / "source.m4a"
    source.write_bytes(b"audio")
    assert AudioNormalizer("ffmpeg", 1).normalize(source) == source


def test_webm_is_remuxed_without_lossy_transcode(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    source = tmp_path / "source.webm"
    source.write_bytes(b"webm")
    calls: list[list[str]] = []

    def fake_run(args: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(args)
        Path(args[-1]).write_bytes(b"opus")
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(module.subprocess, "run", fake_run)
    with caplog.at_level(logging.INFO):
        output = AudioNormalizer("ffmpeg", 1).normalize(source, job_id="job-123")
    assert output.suffix == ".opus"
    assert "copy" in calls[0]
    record = next(
        record
        for record in caplog.records
        if record.message == "acquisition_audio_normalized"
    )
    assert record.job_id == "job-123"  # type: ignore[attr-defined]
    assert str(tmp_path) not in caplog.text


def test_incompatible_audio_uses_single_fallback_transcode(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    source = tmp_path / "source.unknown"
    source.write_bytes(b"audio")
    calls: list[list[str]] = []

    def fake_run(args: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(args)
        Path(args[-1]).write_bytes(b"aac")
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(module.subprocess, "run", fake_run)
    output = AudioNormalizer("ffmpeg", 1).normalize(source)
    assert output.suffix == ".m4a"
    assert len(calls) == 1
    assert "aac" in calls[0]


def test_failed_and_timed_out_normalization_remove_partial_output(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    source = tmp_path / "source.unknown"
    source.write_bytes(b"audio")

    def failed(args: list[str], **_kwargs: object) -> SimpleNamespace:
        Path(args[-1]).write_bytes(b"partial")
        return SimpleNamespace(returncode=1)

    monkeypatch.setattr(module.subprocess, "run", failed)
    with pytest.raises(Exception, match="could not be normalized"):
        AudioNormalizer("ffmpeg", 1).normalize(source)
    assert not (tmp_path / "normalized.m4a").exists()

    def timed_out(_args: list[str], **_kwargs: object) -> SimpleNamespace:
        raise module.subprocess.TimeoutExpired("ffmpeg", 1)

    monkeypatch.setattr(module.subprocess, "run", timed_out)
    with pytest.raises(Exception, match="could not be normalized"):
        AudioNormalizer("ffmpeg", 1).normalize(source)
    assert not (tmp_path / "normalized.m4a").exists()
