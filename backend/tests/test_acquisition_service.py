from __future__ import annotations

from pathlib import Path

import pytest

from arion_api.acquisition import AcquisitionService
from arion_api.acquisition_provider import AcquisitionCandidate, CandidateTokenSigner
from arion_api.acquisition_types import DiscoveryMode
from arion_api.config import Settings
from arion_api.errors import YouTubeAcquisitionDisabledError


class FakeProvider:
    def __init__(self) -> None:
        self.calls: list[tuple[str, DiscoveryMode]] = []

    def discover(
        self, query: str, mode: DiscoveryMode
    ) -> list[AcquisitionCandidate]:
        self.calls.append((query, mode))
        return [
            AcquisitionCandidate(
                discovery_mode=mode,
                provider="youtube",
                external_id="abcdefghijk",
                title="Song",
                channel="Artist",
                duration_seconds=120,
                thumbnail_url=None,
                page_url="https://www.youtube.com/watch?v=abcdefghijk",
            )
        ]


def test_disabled_service_never_contacts_provider(tmp_path: Path) -> None:
    fake = FakeProvider()
    service = AcquisitionService(
        Settings(_env_file=None, media_root=tmp_path),
        object(),  # type: ignore[arg-type]
        fake,  # type: ignore[arg-type]
        CandidateTokenSigner("replace-me"),
    )
    with pytest.raises(YouTubeAcquisitionDisabledError):
        service.discover("song")
    assert fake.calls == []


def test_enabled_discovery_returns_signed_candidate(tmp_path: Path) -> None:
    fake = FakeProvider()
    signer = CandidateTokenSigner("x" * 32)
    service = AcquisitionService(
        Settings(
            _env_file=None,
            media_root=tmp_path,
            youtube_acquisition_enabled=True,
            youtube_candidate_secret="x" * 32,
        ),
        object(),  # type: ignore[arg-type]
        fake,  # type: ignore[arg-type]
        signer,
    )
    candidates = service.discover("  Song  ")
    assert candidates[0].video_id == "abcdefghijk"
    assert candidates[0].discovery_mode is DiscoveryMode.MUSIC
    assert fake.calls == [("  Song  ", DiscoveryMode.MUSIC)]
    assert signer.verify(candidates[0].candidate_id, now=0).external_id == "abcdefghijk"
