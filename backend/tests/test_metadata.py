from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
from mutagen.flac import FLAC, Picture

from arion_api.errors import UnreadableMediaError, UnsupportedMediaError
from arion_api.metadata import MediaInspector, apply_fallbacks, normalize_text

FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")


def generate_audio(path: Path, codec: str) -> None:
    if not FFMPEG:
        pytest.skip("ffmpeg is required for real media integration tests")
    subprocess.run(
        [
            FFMPEG,
            "-v",
            "error",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:duration=0.12",
            "-c:a",
            codec,
            "-y",
            str(path),
        ],
        check=True,
        capture_output=True,
    )


@pytest.mark.parametrize(
    ("filename", "encoder", "expected_codec"),
    [
        ("sample.mp3", "libmp3lame", "mp3"),
        ("sample.flac", "flac", "flac"),
        ("sample-aac.m4a", "aac", "aac"),
        ("sample-alac.m4a", "alac", "alac"),
        ("sample.ogg", "libvorbis", "vorbis"),
        ("sample.opus", "libopus", "opus"),
        ("sample.wav", "pcm_s16le", "pcm_s16le"),
    ],
)
def test_inspector_accepts_supported_real_audio(
    tmp_path: Path, filename: str, encoder: str, expected_codec: str
) -> None:
    if not FFPROBE:
        pytest.skip("ffprobe is required for real media integration tests")
    path = tmp_path / filename
    generate_audio(path, encoder)

    result = MediaInspector(FFPROBE).inspect(path, filename)

    assert result.technical.codec == expected_codec
    assert result.technical.duration_ms > 0
    assert result.technical.sample_rate_hz > 0


def test_inspector_extracts_normalized_flac_tags_and_png_cover(tmp_path: Path) -> None:
    path = tmp_path / "ignored-name.flac"
    generate_audio(path, "flac")
    audio = FLAC(path)
    audio["title"] = ["  First   Title ", "Second"]
    audio["artist"] = " Test   Artist "
    audio["album"] = " Test Album "
    picture = Picture()
    picture.mime = "image/png"
    picture.data = b"\x89PNG\r\n\x1a\nsynthetic"
    audio.add_picture(picture)
    audio.save()

    result = MediaInspector(FFPROBE or "ffprobe").inspect(path, path.name)

    assert result.title == "First Title; Second"
    assert result.artist == "Test Artist"
    assert result.album == "Test Album"
    assert result.cover is not None
    assert result.cover.media_type == "image/png"
    assert result.cover.data == picture.data


def test_inspector_ignores_malformed_optional_cover(tmp_path: Path) -> None:
    path = tmp_path / "Artist - Title.flac"
    generate_audio(path, "flac")
    audio = FLAC(path)
    picture = Picture()
    picture.mime = "image/jpeg"
    picture.data = b"not-an-image"
    audio.add_picture(picture)
    audio.save()

    result = MediaInspector(FFPROBE or "ffprobe").inspect(path, path.name)

    assert result.cover is None
    assert result.title == "Title"
    assert result.artist == "Artist"


def test_inspector_distinguishes_unsupported_and_corrupt_known_content(
    tmp_path: Path,
) -> None:
    unsupported = tmp_path / "text.bin"
    unsupported.write_text("not audio", encoding="utf-8")
    corrupt = tmp_path / "broken.flac"
    corrupt.write_bytes(b"fLaCbroken")
    inspector = MediaInspector(FFPROBE or "ffprobe")

    with pytest.raises(UnsupportedMediaError):
        inspector.inspect(unsupported, unsupported.name)
    with pytest.raises(UnreadableMediaError):
        inspector.inspect(corrupt, corrupt.name)


def test_inspector_translates_probe_timeout(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    path = tmp_path / "sample.wav"
    path.write_bytes(b"RIFF1234WAVE")

    def timeout(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
        raise subprocess.TimeoutExpired(cmd="ffprobe", timeout=1)

    monkeypatch.setattr(subprocess, "run", timeout)

    with pytest.raises(UnreadableMediaError):
        MediaInspector(timeout_seconds=1).inspect(path, path.name)


def test_text_normalization_and_fallbacks() -> None:
    assert normalize_text([" one ", "two  words"]) == "one; two words"
    assert apply_fallbacks(
        title=None,
        artist=None,
        album=None,
        filename="Example Artist - Example Title.flac",
    ) == ("Example Title", "Example Artist", "Unknown Album")
    assert apply_fallbacks(
        title="Tagged",
        artist="Tagged Artist",
        album="Tagged Album",
        filename="ignored.wav",
    ) == ("Tagged", "Tagged Artist", "Tagged Album")
    assert apply_fallbacks(
        title=None, artist=None, album=None, filename="single stem.mp3"
    ) == ("single stem", "Unknown Artist", "Unknown Album")
