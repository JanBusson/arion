from __future__ import annotations

import hashlib
from io import BytesIO
from pathlib import Path
from typing import BinaryIO

import pytest

from arion_api.errors import ImportTooLargeError, UnsupportedMediaError
from arion_api.metadata import InspectedMetadata, TechnicalMetadata
from arion_api.services import UPLOAD_CHUNK_BYTES, stage_upload
from arion_api.storage import LocalMediaStorage


class RecordingStream(BytesIO):
    def __init__(self, value: bytes) -> None:
        super().__init__(value)
        self.requested_sizes: list[int] = []

    def read(self, size: int = -1) -> bytes:
        self.requested_sizes.append(size)
        return super().read(size)


def test_stage_upload_streams_and_hashes_without_unbounded_read(tmp_path: Path) -> None:
    content = b"a" * (UPLOAD_CHUNK_BYTES + 7)
    source = RecordingStream(content)
    storage = LocalMediaStorage(tmp_path)

    key, digest = stage_upload(source, storage, len(content))

    assert all(size == UPLOAD_CHUNK_BYTES for size in source.requested_sizes)
    assert storage.read_bytes(key) == content
    assert digest == hashlib.sha256(content).hexdigest()


def test_stage_upload_removes_partial_file_when_limit_is_exceeded(
    tmp_path: Path,
) -> None:
    storage = LocalMediaStorage(tmp_path)

    with pytest.raises(ImportTooLargeError):
        stage_upload(BytesIO(b"too large"), storage, 3)

    assert list((tmp_path / "staging").iterdir()) == []


def test_stage_upload_removes_partial_file_when_source_fails(tmp_path: Path) -> None:
    class FailingStream:
        calls = 0

        def read(self, _size: int = -1) -> bytes:
            self.calls += 1
            if self.calls == 1:
                return b"partial"
            raise OSError("source interrupted")

    storage = LocalMediaStorage(tmp_path)

    with pytest.raises(OSError, match="source interrupted"):
        stage_upload(FailingStream(), storage, 100)  # type: ignore[arg-type]

    assert list((tmp_path / "staging").iterdir()) == []
