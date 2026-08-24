import os
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from arion_api.storage import LocalMediaStorage, StorageKey, StoredAudio


@pytest.mark.parametrize(
    "value",
    ["/etc/passwd", "audio/../secret", "audio\\secret", "audio", "other/file"],
)
def test_storage_key_rejects_unsafe_values(value: str) -> None:
    with pytest.raises(ValueError):
        StorageKey(value)


def test_local_storage_stages_promotes_reads_and_removes(tmp_path: Path) -> None:
    storage = LocalMediaStorage(tmp_path)
    staged = storage.create_staging(".upload")
    with storage.open_for_write(staged) as stream:
        stream.write(b"audio bytes")

    durable = storage.promote(staged, "audio", ".flac")

    assert durable.value.startswith("audio/")
    assert durable.value.endswith(".flac")
    assert storage.read_bytes(durable) == b"audio bytes"
    assert not storage.staged_path(staged).exists()
    storage.remove(durable)
    storage.remove(durable)
    assert not (tmp_path / durable.value).exists()


@pytest.mark.parametrize(
    ("suffix", "media_type"),
    [
        (".mp3", "audio/mpeg"),
        (".flac", "audio/flac"),
        (".m4a", "audio/mp4"),
        (".ogg", "audio/ogg"),
        (".opus", "audio/ogg"),
        (".wav", "audio/wav"),
    ],
)
def test_audio_info_maps_canonical_suffixes(
    tmp_path: Path, suffix: str, media_type: str
) -> None:
    storage = LocalMediaStorage(tmp_path)
    staged = storage.create_staging()
    with storage.open_for_write(staged) as stream:
        stream.write(b"audio")
    durable = storage.promote(staged, "audio", suffix)

    assert storage.audio_info(durable) == StoredAudio(
        size=5, media_type=media_type
    )


def test_audio_info_rejects_missing_non_audio_and_unknown_suffixes(
    tmp_path: Path,
) -> None:
    storage = LocalMediaStorage(tmp_path)

    with pytest.raises(FileNotFoundError):
        storage.audio_info(StorageKey("audio/missing.flac"))
    with pytest.raises(ValueError, match="only audio"):
        storage.audio_info(StorageKey("covers/cover.png"))
    with pytest.raises(ValueError, match="unsupported"):
        storage.audio_info(StorageKey("audio/track.bin"))


def test_iter_bytes_yields_bounded_complete_and_partial_chunks(
    tmp_path: Path,
) -> None:
    storage = LocalMediaStorage(tmp_path)
    staged = storage.create_staging()
    with storage.open_for_write(staged) as stream:
        stream.write(b"0123456789")
    durable = storage.promote(staged, "audio", ".flac")

    assert list(storage.iter_bytes(durable, 0, 9, chunk_size=4)) == [
        b"0123",
        b"4567",
        b"89",
    ]
    assert list(storage.iter_bytes(durable, 2, 8, chunk_size=3)) == [
        b"234",
        b"567",
        b"8",
    ]


def test_iter_bytes_closes_file_when_consumer_stops(tmp_path: Path) -> None:
    storage = LocalMediaStorage(tmp_path)
    staged = storage.create_staging()
    with storage.open_for_write(staged) as stream:
        stream.write(b"0123456789")
    durable = storage.promote(staged, "audio", ".flac")
    chunks = storage.iter_bytes(durable, 0, 9, chunk_size=2)

    assert next(chunks) == b"01"
    chunks.close()  # type: ignore[attr-defined]
    storage.remove(durable)

    assert not (tmp_path / durable.value).exists()


@pytest.mark.parametrize(
    ("start", "end", "chunk_size"),
    [(-1, 1, 1), (2, 1, 1), (0, 10, 1), (0, 1, 0)],
)
def test_iter_bytes_rejects_invalid_intervals(
    tmp_path: Path, start: int, end: int, chunk_size: int
) -> None:
    storage = LocalMediaStorage(tmp_path)
    staged = storage.create_staging()
    with storage.open_for_write(staged) as stream:
        stream.write(b"0123456789")
    durable = storage.promote(staged, "audio", ".flac")

    with pytest.raises(ValueError):
        storage.iter_bytes(durable, start, end, chunk_size)


def test_storage_reconciliation_honors_references_age_and_database_guard(
    tmp_path: Path,
) -> None:
    storage = LocalMediaStorage(tmp_path)
    referenced = storage.create_staging()
    with storage.open_for_write(referenced) as stream:
        stream.write(b"keep")
    referenced = storage.promote(referenced, "audio", ".flac")
    orphan = storage.create_staging()
    with storage.open_for_write(orphan) as stream:
        stream.write(b"remove")
    orphan = storage.promote(orphan, "audio", ".flac")
    recent = storage.create_staging()

    old = datetime.now(UTC) - timedelta(hours=2)
    for key in (referenced, orphan):
        timestamp = old.timestamp()
        os.utime(tmp_path / key.value, (timestamp, timestamp))

    assert storage.reconcile(None, 60, database_available=False) == []
    assert storage.read_bytes(orphan) == b"remove"

    removed = storage.reconcile(
        {referenced.value}, 60, now=datetime.now(UTC), database_available=True
    )

    assert orphan in removed
    assert storage.read_bytes(referenced) == b"keep"
    assert storage.staged_path(recent).exists()


def test_storage_readiness_probe_cleans_up(tmp_path: Path) -> None:
    storage = LocalMediaStorage(tmp_path)

    assert storage.probe_ready() is True
    assert list((tmp_path / "staging").iterdir()) == []
