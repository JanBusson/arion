"""Inspection-only operator smoke checks for the acquisition toolchain."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from collections.abc import Sequence

from arion_api.acquisition_provider import BoundedProcessRunner, YouTubeProvider
from arion_api.config import Settings, get_settings


def _version(command: Sequence[str]) -> str:
    completed = subprocess.run(
        list(command),
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
        env={
            "PATH": os.environ.get("PATH", ""),
            "LANG": os.environ.get("LANG", "C.UTF-8"),
        },
    )
    if completed.returncode != 0:
        raise RuntimeError("a required acquisition tool is unavailable")
    first_line = (completed.stdout or completed.stderr).splitlines()[0].strip()
    if not first_line:
        raise RuntimeError("a required acquisition tool returned no version")
    return first_line[:128]


def inspect_toolchain(settings: Settings) -> dict[str, str]:
    """Return bounded version strings without updating or contacting providers."""

    return {
        "yt_dlp": _version((settings.ytdlp_executable, "--version")),
        "node": _version(("node", "--version")),
        "ffmpeg": _version((settings.ffmpeg_executable, "-version")),
    }


def inspect_discovery(settings: Settings, query: str) -> dict[str, object]:
    """Inspect candidate discovery only; never enqueue, download, or import."""

    if not settings.youtube_acquisition_enabled:
        raise RuntimeError("YouTube acquisition is disabled")
    provider = YouTubeProvider(
        settings.ytdlp_executable,
        BoundedProcessRunner(),
        candidate_limit=settings.youtube_candidate_limit,
        discovery_timeout_seconds=settings.youtube_discovery_timeout_seconds,
        download_timeout_seconds=settings.youtube_download_timeout_seconds,
        max_duration_seconds=settings.youtube_max_duration_seconds,
        max_output_bytes=settings.youtube_max_output_bytes,
        min_free_bytes=settings.youtube_min_free_bytes,
    )
    candidates = provider.discover(query)
    return {
        "candidate_count": len(candidates),
        "video_ids": [candidate.external_id for candidate in candidates],
        "imported": False,
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Inspect acquisition tools and optional authorized discovery."
    )
    parser.add_argument("--inspection-only", action="store_true", required=True)
    parser.add_argument("--authorized-query")
    parser.add_argument("--acknowledge-authorized", action="store_true")
    args = parser.parse_args(argv)
    if args.authorized_query and not args.acknowledge_authorized:
        parser.error("--authorized-query requires --acknowledge-authorized")

    settings = get_settings()
    result: dict[str, object] = {
        "mode": "inspection-only",
        "toolchain": inspect_toolchain(settings),
        "imported": False,
    }
    if args.authorized_query:
        result["discovery"] = inspect_discovery(settings, args.authorized_query.strip())
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
