"""Opaque local-filesystem storage for staged and durable media."""

from __future__ import annotations

import os
import re
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Literal, Protocol
from uuid import uuid4

Namespace = Literal["staging", "audio", "covers"]
_SAFE_SUFFIX = re.compile(r"^\.[a-z0-9]{1,10}$")
AUDIO_READ_CHUNK_BYTES = 64 * 1024
_AUDIO_MEDIA_TYPES = {
    ".mp3": "audio/mpeg",
    ".flac": "audio/flac",
    ".m4a": "audio/mp4",
    ".ogg": "audio/ogg",
    ".opus": "audio/ogg",
    ".wav": "audio/wav",
}


@dataclass(frozen=True, slots=True)
class StorageKey:
    value: str

    def __post_init__(self) -> None:
        path = PurePosixPath(self.value)
        if (
            path.is_absolute()
            or len(path.parts) != 2
            or path.parts[0] not in {"staging", "audio", "covers"}
            or any(part in {"", ".", ".."} for part in path.parts)
            or "\\" in self.value
        ):
            raise ValueError("invalid opaque storage key")

    @property
    def namespace(self) -> Namespace:
        return self.value.split("/", 1)[0]  # type: ignore[return-value]


@dataclass(frozen=True, slots=True)
class StoredAudio:
    size: int
    media_type: str


class MediaStorage(Protocol):
    def create_staging(self, suffix: str = ".upload") -> StorageKey: ...

    def open_for_write(self, key: StorageKey) -> BinaryIO: ...

    def staged_path(self, key: StorageKey) -> Path: ...

    def promote(
        self, key: StorageKey, namespace: Literal["audio", "covers"], suffix: str
    ) -> StorageKey: ...

    def read_bytes(self, key: StorageKey) -> bytes: ...

    def audio_info(self, key: StorageKey) -> StoredAudio: ...

    def iter_bytes(
        self,
        key: StorageKey,
        start: int,
        end: int,
        chunk_size: int = AUDIO_READ_CHUNK_BYTES,
    ) -> Iterator[bytes]: ...

    def remove(self, key: StorageKey) -> None: ...


class LocalMediaStorage:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()

    def _ensure_namespaces(self) -> None:
        for namespace in ("staging", "audio", "covers"):
            (self.root / namespace).mkdir(parents=True, exist_ok=True)

    @staticmethod
    def _suffix(value: str) -> str:
        normalized = value.lower()
        return normalized if _SAFE_SUFFIX.fullmatch(normalized) else ".bin"

    def _path(self, key: StorageKey) -> Path:
        candidate = self.root.joinpath(*PurePosixPath(key.value).parts).resolve()
        if self.root not in candidate.parents:
            raise ValueError("storage key escaped the configured root")
        return candidate

    def create_staging(self, suffix: str = ".upload") -> StorageKey:
        self._ensure_namespaces()
        key = StorageKey(f"staging/{uuid4().hex}{self._suffix(suffix)}")
        path = self._path(key)
        path.touch(exist_ok=False)
        return key

    def open_for_write(self, key: StorageKey) -> BinaryIO:
        if key.namespace != "staging":
            raise ValueError("only staging objects are writable")
        return self._path(key).open("wb")

    def staged_path(self, key: StorageKey) -> Path:
        if key.namespace != "staging":
            raise ValueError("only staging objects have probe paths")
        return self._path(key)

    def promote(
        self,
        key: StorageKey,
        namespace: Literal["audio", "covers"],
        suffix: str,
    ) -> StorageKey:
        if key.namespace != "staging":
            raise ValueError("only staging objects can be promoted")
        durable = StorageKey(
            f"{namespace}/{uuid4().hex}{self._suffix(suffix)}"
        )
        os.replace(self._path(key), self._path(durable))
        return durable

    def read_bytes(self, key: StorageKey) -> bytes:
        return self._path(key).read_bytes()

    def audio_info(self, key: StorageKey) -> StoredAudio:
        if key.namespace != "audio":
            raise ValueError("only audio objects have audio metadata")
        path = self._path(key)
        suffix = path.suffix.lower()
        try:
            media_type = _AUDIO_MEDIA_TYPES[suffix]
        except KeyError as error:
            raise ValueError("unsupported stored audio suffix") from error
        return StoredAudio(size=path.stat().st_size, media_type=media_type)

    def iter_bytes(
        self,
        key: StorageKey,
        start: int,
        end: int,
        chunk_size: int = AUDIO_READ_CHUNK_BYTES,
    ) -> Iterator[bytes]:
        if key.namespace != "audio":
            raise ValueError("only audio objects can be streamed")
        if start < 0 or end < start:
            raise ValueError("invalid inclusive byte interval")
        if chunk_size <= 0:
            raise ValueError("chunk_size must be positive")

        path = self._path(key)
        object_size = path.stat().st_size
        if end >= object_size:
            raise ValueError("byte interval exceeds the object")

        def chunks() -> Iterator[bytes]:
            remaining = end - start + 1
            with path.open("rb") as stream:
                stream.seek(start)
                while remaining:
                    chunk = stream.read(min(chunk_size, remaining))
                    if not chunk:
                        raise OSError("stored audio ended before the requested range")
                    remaining -= len(chunk)
                    yield chunk

        return chunks()

    def remove(self, key: StorageKey) -> None:
        self._path(key).unlink(missing_ok=True)

    def probe_ready(self) -> bool:
        key: StorageKey | None = None
        try:
            key = self.create_staging(".probe")
            with self.open_for_write(key) as stream:
                stream.write(b"ready")
            return self.read_bytes(key) == b"ready"
        except OSError:
            return False
        finally:
            if key is not None:
                try:
                    self.remove(key)
                except OSError:
                    pass

    def reconcile(
        self,
        referenced_keys: set[str] | None,
        grace_seconds: int,
        *,
        now: datetime | None = None,
        database_available: bool = True,
    ) -> list[StorageKey]:
        """Remove aged crash artifacts; never delete without database references."""

        if not database_available or referenced_keys is None:
            return []
        self._ensure_namespaces()
        current = now or datetime.now(UTC)
        cutoff = current - timedelta(seconds=grace_seconds)
        removed: list[StorageKey] = []
        for namespace in ("staging", "audio", "covers"):
            for path in (self.root / namespace).iterdir():
                if not path.is_file():
                    continue
                modified = datetime.fromtimestamp(path.stat().st_mtime, tz=UTC)
                key = StorageKey(f"{namespace}/{path.name}")
                is_orphan = namespace == "staging" or key.value not in referenced_keys
                if is_orphan and modified <= cutoff:
                    path.unlink(missing_ok=True)
                    removed.append(key)
        return removed


ReferenceProvider = Callable[[], set[str]]
