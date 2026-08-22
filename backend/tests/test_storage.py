import os
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from arion_api.storage import LocalMediaStorage, StorageKey


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
