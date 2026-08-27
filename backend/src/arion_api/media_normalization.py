"""Normalize acquired audio into the existing supported media matrix."""

from __future__ import annotations

import logging
import os
import subprocess
from pathlib import Path

from arion_api.errors import AcquisitionFailure

logger = logging.getLogger(__name__)

SUPPORTED_SUFFIXES = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav"}


class AudioNormalizer:
    def __init__(self, ffmpeg_executable: str, timeout_seconds: float) -> None:
        self.ffmpeg_executable = ffmpeg_executable
        self.timeout_seconds = timeout_seconds

    def normalize(self, source: Path, *, job_id: object | None = None) -> Path:
        suffix = source.suffix.lower()
        if suffix in SUPPORTED_SUFFIXES:
            return source
        if suffix == ".webm":
            remuxed = source.with_name("normalized.opus")
            if self._ffmpeg(source, remuxed, ["-c:a", "copy"], job_id=job_id):
                return remuxed
            remuxed.unlink(missing_ok=True)
        transcoded = source.with_name("normalized.m4a")
        if self._ffmpeg(
            source,
            transcoded,
            ["-c:a", "aac", "-b:a", "192k"],
            job_id=job_id,
        ):
            return transcoded
        transcoded.unlink(missing_ok=True)
        raise AcquisitionFailure(
            "normalization_failed", "The acquired audio could not be normalized."
        )

    def _ffmpeg(
        self,
        source: Path,
        output: Path,
        codec_args: list[str],
        *,
        job_id: object | None,
    ) -> bool:
        environment = {
            key: os.environ[key]
            for key in ("PATH", "LANG", "LC_ALL", "SYSTEMROOT")
            if key in os.environ
        }
        args = [
            self.ffmpeg_executable,
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-vn",
            *codec_args,
            str(output),
        ]
        try:
            result = subprocess.run(  # noqa: S603 - fixed executable and argv
                args,
                cwd=source.parent,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=self.timeout_seconds,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            output.unlink(missing_ok=True)
            return False
        if result.returncode != 0 or not output.is_file() or output.stat().st_size == 0:
            output.unlink(missing_ok=True)
            return False
        logger.info(
            "acquisition_audio_normalized",
            extra={
                "event": "acquisition_audio_normalized",
                "job_id": str(job_id) if job_id is not None else None,
                "output_bytes": output.stat().st_size,
                "stream_copy": "copy" in codec_args,
            },
        )
        return True
