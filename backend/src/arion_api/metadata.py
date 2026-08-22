"""Audio inspection through ffprobe and Mutagen."""

from __future__ import annotations

import base64
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import mutagen
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, ID3
from mutagen.mp4 import MP4, MP4Cover

from arion_api.errors import UnsupportedMediaError, UnreadableMediaError


@dataclass(frozen=True, slots=True)
class Cover:
    data: bytes
    media_type: str


@dataclass(frozen=True, slots=True)
class TechnicalMetadata:
    duration_ms: int
    codec: str
    bitrate_kbps: int | None
    sample_rate_hz: int
    suffix: str


@dataclass(frozen=True, slots=True)
class InspectedMetadata:
    title: str
    artist: str
    album: str
    technical: TechnicalMetadata
    cover: Cover | None


def normalize_text(value: object) -> str | None:
    if isinstance(value, (list, tuple)):
        parts = [normalize_text(part) for part in value]
        normalized = "; ".join(part for part in parts if part)
    elif value is None:
        normalized = ""
    else:
        normalized = " ".join(str(value).split())
    return normalized or None


def apply_fallbacks(
    *, title: object, artist: object, album: object, filename: str
) -> tuple[str, str, str]:
    normalized_title = normalize_text(title)
    normalized_artist = normalize_text(artist)
    normalized_album = normalize_text(album)
    stem = " ".join(Path(filename).stem.split()) or "Unknown Title"
    fallback_artist: str | None = None
    fallback_title = stem
    if " - " in stem:
        left, right = stem.split(" - ", 1)
        if left.strip() and right.strip():
            fallback_artist = left.strip()
            fallback_title = right.strip()
    return (
        normalized_title or fallback_title,
        normalized_artist or fallback_artist or "Unknown Artist",
        normalized_album or "Unknown Album",
    )


def _cover_from_bytes(data: bytes, declared: str | None = None) -> Cover | None:
    if data.startswith(b"\xff\xd8\xff"):
        return Cover(data=data, media_type="image/jpeg")
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return Cover(data=data, media_type="image/png")
    if declared in {"image/jpeg", "image/png"}:
        return None
    return None


def _extract_cover(path: Path) -> Cover | None:
    try:
        audio = mutagen.File(path)
        if isinstance(audio, FLAC):
            for picture in audio.pictures:
                cover = _cover_from_bytes(picture.data, picture.mime)
                if cover:
                    return cover
        if isinstance(audio, MP4) and audio.tags:
            for item in audio.tags.get("covr", []):
                declared = (
                    "image/png"
                    if getattr(item, "imageformat", None) == MP4Cover.FORMAT_PNG
                    else "image/jpeg"
                )
                cover = _cover_from_bytes(bytes(item), declared)
                if cover:
                    return cover
        try:
            tags = ID3(path)
        except Exception:
            tags = None
        if tags:
            for frame in tags.getall("APIC"):
                if isinstance(frame, APIC):
                    cover = _cover_from_bytes(frame.data, frame.mime)
                    if cover:
                        return cover
        if audio is not None and audio.tags:
            for encoded in audio.tags.get("metadata_block_picture", []):
                try:
                    picture = Picture(base64.b64decode(encoded))
                except Exception:
                    continue
                cover = _cover_from_bytes(picture.data, picture.mime)
                if cover:
                    return cover
    except Exception:
        return None
    return None


def _looks_like_supported_container(path: Path) -> bool:
    with path.open("rb") as stream:
        header = stream.read(16)
    return (
        header.startswith((b"ID3", b"fLaC", b"OggS"))
        or (header.startswith(b"RIFF") and header[8:12] == b"WAVE")
        or (len(header) >= 8 and header[4:8] == b"ftyp")
        or (len(header) >= 2 and header[0] == 0xFF and header[1] & 0xE0 == 0xE0)
    )


class MediaInspector:
    def __init__(self, executable: str = "ffprobe", timeout_seconds: float = 30) -> None:
        self.executable = executable
        self.timeout_seconds = timeout_seconds

    def _probe(self, path: Path) -> dict[str, Any]:
        command = [
            self.executable,
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(path),
        ]
        try:
            result = subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
                shell=False,
            )
            return json.loads(result.stdout)
        except subprocess.TimeoutExpired as error:
            raise UnreadableMediaError() from error
        except (subprocess.CalledProcessError, json.JSONDecodeError, OSError) as error:
            exception = (
                UnreadableMediaError()
                if _looks_like_supported_container(path)
                else UnsupportedMediaError()
            )
            raise exception from error

    def inspect(self, path: Path, original_filename: str) -> InspectedMetadata:
        payload = self._probe(path)
        streams = payload.get("streams") or []
        audio_stream = next(
            (stream for stream in streams if stream.get("codec_type") == "audio"),
            None,
        )
        if audio_stream is None:
            raise UnsupportedMediaError()
        codec = str(audio_stream.get("codec_name") or "").lower()
        format_name = str((payload.get("format") or {}).get("format_name") or "")
        suffix = self._validate_supported(codec, format_name)
        duration_value = audio_stream.get("duration") or (payload.get("format") or {}).get(
            "duration"
        )
        sample_rate = audio_stream.get("sample_rate")
        if duration_value is None or sample_rate is None:
            raise UnreadableMediaError()
        try:
            duration_ms = max(0, round(float(duration_value) * 1000))
            sample_rate_hz = int(sample_rate)
            bit_rate = audio_stream.get("bit_rate") or (payload.get("format") or {}).get(
                "bit_rate"
            )
            bitrate_kbps = round(int(bit_rate) / 1000) if bit_rate else None
        except (TypeError, ValueError) as error:
            raise UnreadableMediaError() from error

        title: object = None
        artist: object = None
        album: object = None
        try:
            easy_audio = mutagen.File(path, easy=True)
            if easy_audio is not None and easy_audio.tags:
                title = easy_audio.tags.get("title")
                artist = easy_audio.tags.get("artist")
                album = easy_audio.tags.get("album")
        except Exception:
            pass
        normalized_title, normalized_artist, normalized_album = apply_fallbacks(
            title=title,
            artist=artist,
            album=album,
            filename=original_filename,
        )
        return InspectedMetadata(
            title=normalized_title,
            artist=normalized_artist,
            album=normalized_album,
            technical=TechnicalMetadata(
                duration_ms=duration_ms,
                codec=codec,
                bitrate_kbps=bitrate_kbps,
                sample_rate_hz=sample_rate_hz,
                suffix=suffix,
            ),
            cover=_extract_cover(path),
        )

    @staticmethod
    def _validate_supported(codec: str, format_name: str) -> str:
        formats = set(format_name.split(","))
        if codec == "mp3" and "mp3" in formats:
            return ".mp3"
        if codec == "flac" and "flac" in formats:
            return ".flac"
        if codec in {"aac", "alac"} and formats.intersection(
            {"mov", "mp4", "m4a", "3gp", "3g2", "mj2"}
        ):
            return ".m4a"
        if codec in {"vorbis", "opus"} and "ogg" in formats:
            return ".ogg" if codec == "vorbis" else ".opus"
        if codec.startswith("pcm_") and "wav" in formats:
            return ".wav"
        raise UnsupportedMediaError()
