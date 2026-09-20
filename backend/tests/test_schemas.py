from datetime import UTC, datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError

from arion_api.acquisition_types import DiscoveryMode
from arion_api.schemas import (
    AcquisitionJobCreate,
    TrackResponse,
    YouTubeCandidateResponse,
)


def test_track_response_is_an_allow_list() -> None:
    response = TrackResponse.model_validate(
        {
            "id": uuid4(),
            "title": "Title",
            "artist": "Artist",
            "album": "Album",
            "duration_ms": 1000,
            "codec": "flac",
            "bitrate_kbps": 700,
            "sample_rate_hz": 44100,
            "original_filename": "track.flac",
            "has_cover": False,
            "created_at": datetime.now(UTC),
            "updated_at": datetime.now(UTC),
            "sha256": "secret digest",
            "audio_storage_key": "audio/internal.flac",
        }
    )

    payload = response.model_dump(mode="json")

    assert "sha256" not in payload
    assert "audio_storage_key" not in payload
    assert "cover_storage_key" not in payload


def test_acquisition_job_create_requires_acknowledgement_and_forbids_extras() -> None:
    with pytest.raises(ValidationError, match="acknowledgement"):
        AcquisitionJobCreate(
            candidate_id="x" * 32,
            authorization_acknowledged=False,
        )


def test_candidate_response_discovery_mode_is_allow_listed_and_forbids_extras() -> None:
    payload = {
        "candidate_id": "x" * 32,
        "discovery_mode": DiscoveryMode.MUSIC,
        "video_id": "abcdefghijk",
        "title": "Song",
        "channel": "Artist",
        "duration_seconds": 120,
        "thumbnail_url": None,
        "page_url": "https://www.youtube.com/watch?v=abcdefghijk",
    }
    assert (
        YouTubeCandidateResponse.model_validate(payload).discovery_mode
        is DiscoveryMode.MUSIC
    )
    with pytest.raises(ValidationError):
        YouTubeCandidateResponse.model_validate(
            {**payload, "discovery_mode": "videos"}
        )
    with pytest.raises(ValidationError):
        YouTubeCandidateResponse.model_validate(
            {**payload, "discovery_mode": "m" * 1024}
        )
    with pytest.raises(ValidationError, match="extra"):
        YouTubeCandidateResponse.model_validate({**payload, "command": "unsafe"})
    with pytest.raises(ValidationError, match="extra"):
        AcquisitionJobCreate.model_validate(
            {
                "candidate_id": "x" * 32,
                "authorization_acknowledged": True,
                "command": "--cookies secret",
            }
        )
