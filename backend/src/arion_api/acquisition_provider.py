"""Restricted external acquisition provider and candidate tokens."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit

from arion_api.errors import AcquisitionFailure, YouTubeProviderUnavailableError

logger = logging.getLogger(__name__)

_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_THUMBNAIL_HOSTS = {"i.ytimg.com", "img.youtube.com", "yt3.ggpht.com"}
_MAX_PROCESS_OUTPUT = 1024 * 1024


def _bounded_text(value: object, fallback: str, limit: int = 512) -> str:
    if not isinstance(value, str):
        return fallback
    normalized = " ".join(value.split())
    return (normalized or fallback)[:limit]


def _thumbnail_url(value: object) -> str | None:
    if not isinstance(value, str) or len(value) > 2048:
        return None
    parsed = urlsplit(value)
    if parsed.scheme != "https" or parsed.hostname not in _THUMBNAIL_HOSTS:
        return None
    return value


def canonical_youtube_url(video_id: str) -> str:
    if not _VIDEO_ID.fullmatch(video_id):
        raise AcquisitionFailure("invalid_video_id", "The video identifier is invalid.")
    return f"https://www.youtube.com/watch?v={video_id}"


@dataclass(frozen=True, slots=True)
class AcquisitionCandidate:
    provider: str
    external_id: str
    title: str
    channel: str
    duration_seconds: int | None
    thumbnail_url: str | None
    page_url: str


class CandidateTokenSigner:
    """HMAC candidate envelope supporting current and previous verification keys."""

    def __init__(self, current_key: str, previous_keys: tuple[str, ...] = ()) -> None:
        keys = (current_key, *previous_keys)
        if any(not key for key in keys):
            raise ValueError("candidate signing keys must not be empty")
        self._keys = tuple(key.encode("utf-8") for key in keys)

    @staticmethod
    def _encode(value: bytes) -> str:
        return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")

    @staticmethod
    def _decode(value: str) -> bytes:
        padding = "=" * (-len(value) % 4)
        return base64.urlsafe_b64decode(value + padding)

    def sign(
        self,
        candidate: AcquisitionCandidate,
        *,
        now: int,
        ttl_seconds: int,
    ) -> str:
        payload = {
            "v": 1,
            "iat": now,
            "exp": now + ttl_seconds,
            "candidate": asdict(candidate),
        }
        encoded = self._encode(
            json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
        )
        signature = hmac.new(self._keys[0], encoded.encode("ascii"), hashlib.sha256)
        return f"{encoded}.{self._encode(signature.digest())}"

    def verify(self, token: str, *, now: int) -> AcquisitionCandidate:
        try:
            encoded, signature_text = token.split(".", 1)
            signature = self._decode(signature_text)
            if not any(
                hmac.compare_digest(
                    signature,
                    hmac.new(key, encoded.encode("ascii"), hashlib.sha256).digest(),
                )
                for key in self._keys
            ):
                raise ValueError("signature mismatch")
            payload = json.loads(self._decode(encoded))
            if payload.get("v") != 1 or int(payload["exp"]) < now:
                raise ValueError("expired token")
            candidate = AcquisitionCandidate(**payload["candidate"])
            if candidate.provider != "youtube":
                raise ValueError("provider mismatch")
            if not _VIDEO_ID.fullmatch(candidate.external_id):
                raise ValueError("invalid video id")
            if candidate.page_url != canonical_youtube_url(candidate.external_id):
                raise ValueError("invalid page url")
            return candidate
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            raise AcquisitionFailure(
                "invalid_candidate", "The selected candidate is invalid or has expired."
            ) from error


@dataclass(frozen=True, slots=True)
class ProcessResult:
    stdout: str
    stderr: str


class ProcessRunner(Protocol):
    def run(
        self,
        args: list[str],
        *,
        cwd: Path | None,
        timeout_seconds: float,
        max_workspace_bytes: int | None = None,
        min_free_bytes: int = 0,
    ) -> ProcessResult: ...


class BoundedProcessRunner:
    """Run a fixed argv with bounded disk, time, and captured output."""

    def __init__(self, poll_seconds: float = 0.1) -> None:
        self.poll_seconds = poll_seconds

    def run(
        self,
        args: list[str],
        *,
        cwd: Path | None,
        timeout_seconds: float,
        max_workspace_bytes: int | None = None,
        min_free_bytes: int = 0,
    ) -> ProcessResult:
        environment = {
            key: os.environ[key]
            for key in ("PATH", "LANG", "LC_ALL", "SSL_CERT_FILE", "SYSTEMROOT")
            if key in os.environ
        }
        deadline = time.monotonic() + timeout_seconds
        with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
            process = subprocess.Popen(  # noqa: S603 - argv is fixed by provider
                args,
                cwd=cwd,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=stdout_file,
                stderr=stderr_file,
                shell=False,
            )
            failure: AcquisitionFailure | None = None
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    failure = AcquisitionFailure(
                        "acquisition_timeout", "Acquisition exceeded its time limit."
                    )
                elif cwd is not None and max_workspace_bytes is not None:
                    size = sum(
                        path.stat().st_size
                        for path in cwd.rglob("*")
                        if path.is_file() and not path.is_symlink()
                    )
                    if size > max_workspace_bytes:
                        failure = AcquisitionFailure(
                            "output_too_large", "Acquired media exceeded its size limit."
                        )
                    elif shutil.disk_usage(cwd).free < min_free_bytes:
                        failure = AcquisitionFailure(
                            "insufficient_disk", "The server has insufficient free space."
                        )
                if failure is not None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                    break
                time.sleep(self.poll_seconds)

            process.wait()
            stdout_file.seek(0)
            stderr_file.seek(0)
            stdout = stdout_file.read(_MAX_PROCESS_OUTPUT + 1)
            stderr = stderr_file.read(_MAX_PROCESS_OUTPUT + 1)
            if failure is not None:
                raise failure
            if len(stdout) > _MAX_PROCESS_OUTPUT or len(stderr) > _MAX_PROCESS_OUTPUT:
                raise AcquisitionFailure(
                    "provider_output_too_large", "The provider returned excessive output."
                )
            if process.returncode != 0:
                raise AcquisitionFailure(
                    "provider_failed", "The provider could not acquire this candidate."
                )
            return ProcessResult(
                stdout=stdout.decode("utf-8", errors="replace"),
                stderr=stderr.decode("utf-8", errors="replace")[-4096:],
            )


class YouTubeProvider:
    provider_name = "youtube"

    def __init__(
        self,
        executable: str,
        runner: ProcessRunner,
        *,
        candidate_limit: int,
        discovery_timeout_seconds: float,
        download_timeout_seconds: float,
        max_duration_seconds: int,
        max_output_bytes: int,
        min_free_bytes: int,
    ) -> None:
        self.executable = executable
        self.runner = runner
        self.candidate_limit = min(candidate_limit, 5)
        self.discovery_timeout_seconds = discovery_timeout_seconds
        self.download_timeout_seconds = download_timeout_seconds
        self.max_duration_seconds = max_duration_seconds
        self.max_output_bytes = max_output_bytes
        self.min_free_bytes = min_free_bytes

    def _base_args(self) -> list[str]:
        return [
            self.executable,
            "--ignore-config",
            "--no-cache-dir",
            "--no-update",
            "--no-playlist",
            "--no-remote-components",
            "--js-runtimes",
            "node",
        ]

    def discover(self, query: str) -> list[AcquisitionCandidate]:
        normalized = " ".join(query.split())
        if not normalized:
            return []
        target = f"ytsearch{self.candidate_limit}:{normalized}"
        args = [
            *self._base_args(),
            "--flat-playlist",
            "--dump-single-json",
            "--playlist-end",
            str(self.candidate_limit),
            "--",
            target,
        ]
        started = time.monotonic()
        try:
            result = self.runner.run(
                args, cwd=None, timeout_seconds=self.discovery_timeout_seconds
            )
            payload = json.loads(result.stdout)
        except (AcquisitionFailure, json.JSONDecodeError, OSError) as error:
            logger.warning(
                "youtube_discovery_failed",
                extra={"event": "youtube_discovery_failed", "duration_ms": int((time.monotonic() - started) * 1000)},
            )
            raise YouTubeProviderUnavailableError() from error
        entries = payload.get("entries") if isinstance(payload, dict) else None
        if not isinstance(entries, list):
            raise YouTubeProviderUnavailableError()
        candidates: list[AcquisitionCandidate] = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            candidate = self._candidate_from_info(entry, strict=False)
            if candidate is not None:
                candidates.append(candidate)
            if len(candidates) >= self.candidate_limit:
                break
        logger.info(
            "youtube_discovery_completed",
            extra={
                "event": "youtube_discovery_completed",
                "candidate_count": len(candidates),
                "duration_ms": int((time.monotonic() - started) * 1000),
            },
        )
        return candidates

    def revalidate(self, video_id: str) -> AcquisitionCandidate:
        target = canonical_youtube_url(video_id)
        args = [*self._base_args(), "--skip-download", "--dump-single-json", "--", target]
        try:
            result = self.runner.run(
                args, cwd=None, timeout_seconds=self.discovery_timeout_seconds
            )
            payload = json.loads(result.stdout)
        except (AcquisitionFailure, json.JSONDecodeError, OSError) as error:
            raise AcquisitionFailure(
                "candidate_unavailable", "The selected candidate is unavailable."
            ) from error
        if not isinstance(payload, dict):
            raise AcquisitionFailure(
                "candidate_unavailable", "The selected candidate is unavailable."
            )
        candidate = self._candidate_from_info(payload, strict=True)
        if candidate is None or candidate.external_id != video_id:
            raise AcquisitionFailure(
                "candidate_ineligible", "The selected candidate is not eligible."
            )
        return candidate

    def _candidate_from_info(
        self, info: dict[str, object], *, strict: bool
    ) -> AcquisitionCandidate | None:
        video_id = info.get("id")
        if not isinstance(video_id, str) or not _VIDEO_ID.fullmatch(video_id):
            return None
        if info.get("is_live") is True or info.get("live_status") in {
            "is_live",
            "is_upcoming",
            "post_live",
        }:
            return None
        if strict:
            availability = info.get("availability")
            if availability not in (None, "public", "unlisted"):
                return None
            age_limit = info.get("age_limit")
            if isinstance(age_limit, (int, float)) and age_limit > 0:
                return None
        raw_duration = info.get("duration")
        duration = int(raw_duration) if isinstance(raw_duration, (int, float)) else None
        if duration is not None and duration > self.max_duration_seconds:
            return None
        thumbnail = info.get("thumbnail")
        if thumbnail is None and isinstance(info.get("thumbnails"), list):
            for item in reversed(info["thumbnails"]):  # type: ignore[index]
                if isinstance(item, dict) and _thumbnail_url(item.get("url")):
                    thumbnail = item.get("url")
                    break
        return AcquisitionCandidate(
            provider="youtube",
            external_id=video_id,
            title=_bounded_text(info.get("title"), "Untitled video"),
            channel=_bounded_text(
                info.get("channel") or info.get("uploader"), "Unknown channel"
            ),
            duration_seconds=duration,
            thumbnail_url=_thumbnail_url(thumbnail),
            page_url=canonical_youtube_url(video_id),
        )

    def download(
        self,
        video_id: str,
        workspace: Path,
        *,
        job_id: object | None = None,
    ) -> Path:
        target = canonical_youtube_url(video_id)
        output_template = "source.%(ext)s"
        args = [
            *self._base_args(),
            "--format",
            "bestaudio[ext=m4a]/bestaudio",
            "--max-filesize",
            str(self.max_output_bytes),
            "--no-write-comments",
            "--no-write-subs",
            "--no-write-thumbnail",
            "--output",
            output_template,
            "--print",
            "after_move:filepath",
            "--",
            target,
        ]
        started = time.monotonic()
        self.runner.run(
            args,
            cwd=workspace,
            timeout_seconds=self.download_timeout_seconds,
            max_workspace_bytes=self.max_output_bytes,
            min_free_bytes=self.min_free_bytes,
        )
        files = [
            path.resolve()
            for path in workspace.iterdir()
            if path.is_file() and not path.name.endswith((".part", ".ytdl"))
        ]
        if len(files) != 1 or workspace.resolve() not in files[0].parents:
            raise AcquisitionFailure(
                "invalid_provider_output", "The provider produced invalid media output."
            )
        if files[0].stat().st_size > self.max_output_bytes:
            raise AcquisitionFailure(
                "output_too_large", "Acquired media exceeded its size limit."
            )
        logger.info(
            "youtube_download_completed",
            extra={
                "event": "youtube_download_completed",
                "job_id": str(job_id) if job_id is not None else None,
                "duration_ms": int((time.monotonic() - started) * 1000),
                "output_bytes": files[0].stat().st_size,
            },
        )
        return files[0]
