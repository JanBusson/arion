from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

import pytest

from arion_api.acquisition_provider import (
    AcquisitionCandidate,
    BoundedProcessRunner,
    CandidateTokenSigner,
    ProcessResult,
    YouTubeProvider,
)
from arion_api.errors import AcquisitionFailure, YouTubeProviderUnavailableError


class FakeRunner:
    def __init__(self, *results: ProcessResult | Exception) -> None:
        self.results = list(results)
        self.calls: list[tuple[list[str], Path | None]] = []

    def run(
        self,
        args: list[str],
        *,
        cwd: Path | None,
        timeout_seconds: float,
        max_workspace_bytes: int | None = None,
        min_free_bytes: int = 0,
    ) -> ProcessResult:
        self.calls.append((args, cwd))
        result = self.results.pop(0)
        if isinstance(result, Exception):
            raise result
        return result


def provider(runner: FakeRunner) -> YouTubeProvider:
    return YouTubeProvider(
        "yt-dlp",
        runner,
        candidate_limit=5,
        discovery_timeout_seconds=2,
        download_timeout_seconds=5,
        max_duration_seconds=900,
        max_output_bytes=1024,
        min_free_bytes=0,
    )


def sample_candidate() -> AcquisitionCandidate:
    return AcquisitionCandidate(
        provider="youtube",
        external_id="abcdefghijk",
        title="Title",
        channel="Channel",
        duration_seconds=120,
        thumbnail_url="https://i.ytimg.com/vi/abcdefghijk/default.jpg",
        page_url="https://www.youtube.com/watch?v=abcdefghijk",
    )


def test_candidate_tokens_round_trip_expire_detect_tampering_and_rotate() -> None:
    old = "o" * 32
    current = "c" * 32
    old_signer = CandidateTokenSigner(old)
    token = old_signer.sign(sample_candidate(), now=100, ttl_seconds=60)

    assert CandidateTokenSigner(current, (old,)).verify(token, now=159) == sample_candidate()
    with pytest.raises(AcquisitionFailure, match="invalid or has expired"):
        CandidateTokenSigner(current, (old,)).verify(token, now=161)
    with pytest.raises(AcquisitionFailure):
        CandidateTokenSigner(current, (old,)).verify(token + "changed", now=110)


def test_discovery_filters_untrusted_and_ineligible_results() -> None:
    payload = {
        "entries": [
            {
                "id": "abcdefghijk",
                "title": "  Good   Song  ",
                "channel": "Artist",
                "duration": 120,
                "thumbnail": "https://i.ytimg.com/vi/abcdefghijk/default.jpg",
            },
            {"id": "livevideo01", "title": "Live", "is_live": True},
            {"id": "toolong0001", "title": "Long", "duration": 901},
            {"id": "--cookies=x", "title": "Injection"},
        ]
    }
    runner = FakeRunner(ProcessResult(json.dumps(payload), ""))

    candidates = provider(runner).discover("  artist ; --cookies secret ")

    assert candidates == [sample_candidate().__class__(
        provider="youtube",
        external_id="abcdefghijk",
        title="Good Song",
        channel="Artist",
        duration_seconds=120,
        thumbnail_url="https://i.ytimg.com/vi/abcdefghijk/default.jpg",
        page_url="https://www.youtube.com/watch?v=abcdefghijk",
    )]
    args, _ = runner.calls[0]
    assert "--" in args
    assert args[-1].startswith("ytsearch5:")
    assert "--cookies" not in args[:-1]


def test_discovery_maps_malformed_output_to_safe_provider_error() -> None:
    runner = FakeRunner(ProcessResult("not json", "secret path C:/private"))
    with pytest.raises(YouTubeProviderUnavailableError):
        provider(runner).discover("song")


@pytest.mark.parametrize(
    "extra",
    [
        {"is_live": True},
        {"live_status": "is_upcoming"},
        {"availability": "private"},
        {"age_limit": 18},
        {"duration": 901},
    ],
)
def test_revalidation_rejects_each_ineligible_video(extra: dict[str, object]) -> None:
    payload: dict[str, object] = {
        "id": "abcdefghijk",
        "title": "Song",
        "channel": "Artist",
        "duration": 120,
        **extra,
    }
    runner = FakeRunner(ProcessResult(json.dumps(payload), ""))
    with pytest.raises(AcquisitionFailure, match="not eligible"):
        provider(runner).revalidate("abcdefghijk")


def test_download_accepts_only_workspace_output(
    tmp_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    class DownloadRunner(FakeRunner):
        def run(self, args: list[str], **kwargs: object) -> ProcessResult:
            cwd = kwargs["cwd"]
            assert isinstance(cwd, Path)
            (cwd / "source.m4a").write_bytes(b"audio")
            return super().run(args, **kwargs)  # type: ignore[arg-type]

    runner = DownloadRunner(ProcessResult("source.m4a\n", ""))
    with caplog.at_level(logging.INFO):
        output = provider(runner).download(
            "abcdefghijk", tmp_path, job_id="job-123"
        )
    assert output == (tmp_path / "source.m4a").resolve()
    args, _ = runner.calls[0]
    assert args[-1] == "https://www.youtube.com/watch?v=abcdefghijk"
    assert "--cookies" not in args
    record = next(
        record
        for record in caplog.records
        if record.message == "youtube_download_completed"
    )
    assert record.job_id == "job-123"  # type: ignore[attr-defined]
    assert str(tmp_path) not in caplog.text


def test_bounded_runner_stops_timeout_and_workspace_growth(tmp_path: Path) -> None:
    runner = BoundedProcessRunner(poll_seconds=0.01)
    with pytest.raises(AcquisitionFailure, match="time limit"):
        runner.run(
            [sys.executable, "-c", "import time; time.sleep(2)"],
            cwd=tmp_path,
            timeout_seconds=0.05,
        )

    script = "from pathlib import Path; import time; Path('large').write_bytes(b'x'*20); time.sleep(2)"
    with pytest.raises(AcquisitionFailure, match="size limit"):
        runner.run(
            [sys.executable, "-c", script],
            cwd=tmp_path,
            timeout_seconds=2,
            max_workspace_bytes=10,
        )


def test_provider_logs_are_structured_and_do_not_leak_external_output(
    caplog: pytest.LogCaptureFixture,
) -> None:
    runner = FakeRunner(
        AcquisitionFailure("provider_failed", "secret-cookie C:/private")
    )
    with caplog.at_level(logging.WARNING), pytest.raises(
        YouTubeProviderUnavailableError
    ):
        provider(runner).discover("song")
    assert "youtube_discovery_failed" in caplog.text
    assert "secret-cookie" not in caplog.text
    assert "C:/private" not in caplog.text
