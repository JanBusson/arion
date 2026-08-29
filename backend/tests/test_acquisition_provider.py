from __future__ import annotations

import json
import logging
import sys
import base64
import hashlib
import hmac
from dataclasses import replace
from pathlib import Path

import pytest

from arion_api.acquisition_provider import (
    AcquisitionCandidate,
    BoundedProcessRunner,
    CandidateTokenSigner,
    DiscoveryProvider,
    ProcessResult,
    YouTubeDiscoveryRouter,
    YouTubeMusicProvider,
    YouTubeProvider,
    unauthenticated_music_client,
)
from arion_api import acquisition_provider as provider_module
from arion_api.acquisition_types import DiscoveryMode
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
        discovery_mode=DiscoveryMode.ALL,
        provider="youtube",
        external_id="abcdefghijk",
        title="Title",
        channel="Channel",
        duration_seconds=120,
        thumbnail_url="https://i.ytimg.com/vi/abcdefghijk/default.jpg",
        page_url="https://www.youtube.com/watch?v=abcdefghijk",
    )


def _resign_token(token: str, key: str, mutate: object) -> str:
    encoded, _ = token.split(".", 1)
    padding = "=" * (-len(encoded) % 4)
    payload = json.loads(base64.urlsafe_b64decode(encoded + padding))
    mutate(payload)
    changed = base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    ).rstrip(b"=").decode()
    signature = hmac.new(key.encode(), changed.encode(), hashlib.sha256).digest()
    return f"{changed}.{base64.urlsafe_b64encode(signature).rstrip(b'=').decode()}"


@pytest.mark.parametrize("mode", list(DiscoveryMode))
def test_candidate_tokens_round_trip_expire_detect_tampering_and_rotate(
    mode: DiscoveryMode,
) -> None:
    old = "o" * 32
    current = "c" * 32
    old_signer = CandidateTokenSigner(old)
    candidate = replace(sample_candidate(), discovery_mode=mode)
    token = old_signer.sign(candidate, now=100, ttl_seconds=60)

    assert CandidateTokenSigner(current, (old,)).verify(token, now=159) == candidate
    with pytest.raises(AcquisitionFailure, match="invalid or has expired"):
        CandidateTokenSigner(current, (old,)).verify(token, now=161)
    with pytest.raises(AcquisitionFailure):
        CandidateTokenSigner(current, (old,)).verify(token + "changed", now=110)


def test_candidate_tokens_reject_missing_mode_and_provider_mismatch() -> None:
    key = "k" * 32
    signer = CandidateTokenSigner(key)
    token = signer.sign(sample_candidate(), now=100, ttl_seconds=60)
    missing_mode = _resign_token(
        token, key, lambda payload: payload["candidate"].pop("discovery_mode")
    )
    wrong_provider = _resign_token(
        token,
        key,
        lambda payload: payload["candidate"].__setitem__("provider", "other"),
    )

    with pytest.raises(AcquisitionFailure):
        signer.verify(missing_mode, now=110)
    with pytest.raises(AcquisitionFailure):
        signer.verify(wrong_provider, now=110)


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
        discovery_mode=DiscoveryMode.ALL,
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


def test_broad_discovery_keeps_the_configured_result_limit() -> None:
    payload = {
        "entries": [
            {
                "id": f"broadid{i:04d}",
                "title": f"Video {i}",
                "channel": "Uploader",
            }
            for i in range(8)
        ]
    }

    candidates = provider(
        FakeRunner(ProcessResult(json.dumps(payload), ""))
    ).discover("remix")

    assert len(candidates) == 5
    assert all(candidate.discovery_mode is DiscoveryMode.ALL for candidate in candidates)


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


def test_unauthenticated_music_client_uses_only_bounded_session(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: dict[str, object] = {}

    def fake_ytmusic(*args: object, **kwargs: object) -> FakeMusicClient:
        captured["args"] = args
        captured["kwargs"] = kwargs
        return FakeMusicClient([])

    monkeypatch.setattr(provider_module, "YTMusic", fake_ytmusic)

    unauthenticated_music_client(12)

    assert captured["args"] == ()
    kwargs = captured["kwargs"]
    assert isinstance(kwargs, dict)
    assert set(kwargs) == {"requests_session"}
    session = kwargs["requests_session"]
    assert isinstance(session, provider_module.requests.Session)
    assert len(session.cookies) == 0
    assert "Authorization" not in session.headers


class FakeMusicClient:
    def __init__(self, result: object) -> None:
        self.result = result
        self.calls: list[tuple[str, str, int]] = []

    def search(
        self, query: str, *, filter: str, limit: int
    ) -> list[dict[str, object]]:
        self.calls.append((query, filter, limit))
        if isinstance(self.result, Exception):
            raise self.result
        return self.result  # type: ignore[return-value]


def music_provider(client: FakeMusicClient) -> YouTubeMusicProvider:
    return YouTubeMusicProvider(
        lambda: client,
        candidate_limit=5,
        max_duration_seconds=900,
    )


def test_music_discovery_uses_only_song_filter_and_normalizes_safe_fields() -> None:
    client = FakeMusicClient(
        [
            {
                "resultType": "song",
                "videoId": "abcdefghijk",
                "title": "  Good   Song ",
                "artists": [{"name": " First  Artist "}, {"name": "Guest"}],
                "duration_seconds": 120,
                "thumbnails": [{"url": "https://attacker.invalid/image"}],
            },
            {
                "resultType": "video",
                "videoId": "notasong001",
                "title": "Video",
                "artists": [{"name": "Artist"}],
            },
            {
                "resultType": "song",
                "videoId": "nodur000001",
                "title": "No Duration",
                "artists": [{"name": "Artist"}],
            },
        ]
    )

    candidates = music_provider(client).discover("  my   query ")

    assert client.calls == [("my query", "songs", 5)]
    assert candidates == [
        AcquisitionCandidate(
            discovery_mode=DiscoveryMode.MUSIC,
            provider="youtube",
            external_id="abcdefghijk",
            title="Good Song",
            channel="First Artist, Guest",
            duration_seconds=120,
            thumbnail_url="https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg",
            page_url="https://www.youtube.com/watch?v=abcdefghijk",
        ),
        AcquisitionCandidate(
            discovery_mode=DiscoveryMode.MUSIC,
            provider="youtube",
            external_id="nodur000001",
            title="No Duration",
            channel="Artist",
            duration_seconds=None,
            thumbnail_url="https://i.ytimg.com/vi/nodur000001/mqdefault.jpg",
            page_url="https://www.youtube.com/watch?v=nodur000001",
        ),
    ]


def test_music_discovery_skips_malformed_rows_and_caps_excess_results() -> None:
    valid_rows = [
        {
            "resultType": "song",
            "videoId": f"validid{i:04d}",
            "title": f"Song {i}",
            "artists": [{"name": "Artist"}],
            "duration_seconds": 100,
        }
        for i in range(8)
    ]
    invalid_rows: list[object] = [
        None,
        {"resultType": "song", "videoId": "bad", "title": "Bad", "artists": []},
        {"resultType": "song", "videoId": "toolong0001", "title": "Long", "artists": [{"name": "A"}], "duration_seconds": 901},
        {"resultType": "song", "videoId": "wrongdur001", "title": "Duration", "artists": [{"name": "A"}], "duration_seconds": "12"},
        {"resultType": "song", "videoId": "artists0001", "title": "Artists", "artists": [{"name": "A"}] * 9},
    ]
    client = FakeMusicClient([*invalid_rows, *valid_rows])

    candidates = music_provider(client).discover("song")

    assert len(candidates) == 5
    assert all(candidate.discovery_mode is DiscoveryMode.MUSIC for candidate in candidates)


@pytest.mark.parametrize("failure", [TimeoutError("timeout"), ValueError("protocol")])
def test_music_discovery_maps_failures_without_leaking_provider_data(
    failure: Exception, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level(logging.WARNING), pytest.raises(
        YouTubeProviderUnavailableError
    ):
        music_provider(FakeMusicClient(failure)).discover("private query")
    assert "private query" not in caplog.text
    assert str(failure) not in caplog.text


def test_music_discovery_rejects_unusable_response() -> None:
    with pytest.raises(YouTubeProviderUnavailableError):
        music_provider(FakeMusicClient({"unexpected": True})).discover("song")


class StubDiscovery(DiscoveryProvider):
    def __init__(self, result: list[AcquisitionCandidate] | Exception) -> None:
        self.result = result
        self.calls: list[str] = []

    def discover(self, query: str) -> list[AcquisitionCandidate]:
        self.calls.append(query)
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


def test_discovery_router_never_falls_back_between_modes() -> None:
    music = StubDiscovery([])
    broad = StubDiscovery([sample_candidate()])
    router = YouTubeDiscoveryRouter(music, broad)

    assert router.discover("song", DiscoveryMode.MUSIC) == []
    assert music.calls == ["song"]
    assert broad.calls == []

    assert router.discover("song", DiscoveryMode.ALL) == [sample_candidate()]
    assert broad.calls == ["song"]


def test_discovery_logs_include_mode_and_count_but_not_query(
    caplog: pytest.LogCaptureFixture,
) -> None:
    client = FakeMusicClient([])
    with caplog.at_level(logging.INFO):
        assert music_provider(client).discover("private song query") == []
    record = next(
        record
        for record in caplog.records
        if record.message == "youtube_discovery_completed"
    )
    assert record.discovery_mode == "music"  # type: ignore[attr-defined]
    assert record.candidate_count == 0  # type: ignore[attr-defined]
    assert "private song query" not in caplog.text
