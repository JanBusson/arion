from datetime import UTC, datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError

from arion_api.schemas import AcquisitionJobCreate, TrackResponse


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
    with pytest.raises(ValidationError, match="extra"):
        AcquisitionJobCreate.model_validate(
            {
                "candidate_id": "x" * 32,
                "authorization_acknowledged": True,
                "command": "--cookies secret",
            }
        )
