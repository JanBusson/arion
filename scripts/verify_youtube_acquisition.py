#!/usr/bin/env python3
"""Run an explicitly authorized acquisition through the public HTTP API."""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urljoin, urlsplit
from urllib.request import Request, urlopen


@dataclass(frozen=True)
class Response:
    status: int
    headers: dict[str, str]
    body: bytes


def request(
    base_url: str,
    path: str,
    *,
    method: str = "GET",
    body: bytes | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = 30,
) -> Response:
    target = urljoin(f"{base_url.rstrip('/')}/", path.lstrip("/"))
    operation = Request(target, data=body, method=method, headers=headers or {})
    try:
        with urlopen(operation, timeout=timeout) as result:
            return Response(
                result.status,
                {key.lower(): value for key, value in result.headers.items()},
                result.read(),
            )
    except HTTPError as error:
        return Response(
            error.code,
            {key.lower(): value for key, value in error.headers.items()},
            error.read(),
        )
    except URLError as error:
        raise AssertionError(f"request failed: {error.reason}") from error


def expect_json(response: Response, status: int, label: str) -> dict[str, object]:
    assert response.status == status, (
        f"{label}: expected HTTP {status}, got {response.status}: "
        f"{response.body[:300]!r}"
    )
    payload = json.loads(response.body)
    assert isinstance(payload, dict), f"{label}: expected a JSON object"
    return payload


def run(args: argparse.Namespace) -> dict[str, object]:
    parsed = urlsplit(args.base_url)
    assert parsed.scheme == "http" and parsed.hostname in {"127.0.0.1", "localhost", "::1"}, (
        "this verification command only permits a loopback HTTP deployment"
    )

    query = urlencode({"q": args.authorized_query})
    discovery = expect_json(
        request(
            args.base_url,
            f"/api/v1/acquisition/youtube/candidates?{query}",
            timeout=args.discovery_timeout_seconds,
        ),
        200,
        "candidate discovery",
    )
    items = discovery.get("items")
    assert isinstance(items, list), "candidate discovery: missing items"
    candidate = next(
        (
            item
            for item in items
            if isinstance(item, dict)
            and item.get("video_id") == args.expected_video_id
        ),
        None,
    )
    assert candidate is not None, (
        f"authorized video {args.expected_video_id!r} was not among the "
        f"{len(items)} bounded candidates"
    )
    candidate_id = candidate.get("candidate_id")
    assert isinstance(candidate_id, str), "candidate discovery: missing candidate token"
    print(
        "authorized candidate selected: "
        f"{candidate.get('title')} — {candidate.get('channel')} "
        f"({candidate.get('duration_seconds')}s)"
    )

    job = expect_json(
        request(
            args.base_url,
            "/api/v1/acquisition/jobs",
            method="POST",
            body=json.dumps(
                {
                    "candidate_id": candidate_id,
                    "authorization_acknowledged": True,
                }
            ).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        ),
        202,
        "job creation",
    )
    job_id = job.get("id")
    assert isinstance(job_id, str), "job creation: missing job ID"

    deadline = time.monotonic() + args.job_timeout_seconds
    last_progress: tuple[object, object, object] | None = None
    while True:
        progress = expect_json(
            request(args.base_url, f"/api/v1/acquisition/jobs/{quote(job_id)}"),
            200,
            "job polling",
        )
        marker = (
            progress.get("state"),
            progress.get("phase"),
            progress.get("progress_percent"),
        )
        if marker != last_progress:
            print(f"job {job_id}: state={marker[0]} phase={marker[1]} progress={marker[2]}%")
            last_progress = marker
        if progress.get("state") == "completed":
            job = progress
            break
        if progress.get("state") in {"failed", "cancelled"}:
            raise AssertionError(
                "acquisition failed safely: "
                f"{progress.get('failure_code')}: {progress.get('failure_message')}"
            )
        if time.monotonic() >= deadline:
            raise AssertionError("acquisition job did not finish before the timeout")
        time.sleep(args.poll_seconds)

    track_id = job.get("track_id")
    assert isinstance(track_id, str), "completed job: missing track ID"
    track = expect_json(
        request(args.base_url, f"/api/v1/tracks/{quote(track_id)}"),
        200,
        "resulting track",
    )
    assert track.get("id") == track_id

    title = track.get("title")
    assert isinstance(title, str) and title, "resulting track: missing title"
    catalog = expect_json(
        request(
            args.base_url,
            f"/api/v1/tracks?limit=100&offset=0&q={quote(title)}",
        ),
        200,
        "catalog refresh",
    )
    catalog_items = catalog.get("items")
    assert isinstance(catalog_items, list)
    assert any(
        isinstance(item, dict) and item.get("id") == track_id
        for item in catalog_items
    ), "catalog refresh: imported track was not listed"

    partial = request(
        args.base_url,
        f"/api/v1/tracks/{quote(track_id)}/audio",
        headers={"Range": "bytes=0-1023"},
    )
    assert partial.status == 206, f"ranged playback: expected HTTP 206, got {partial.status}"
    assert 1 <= len(partial.body) <= 1024
    assert partial.headers.get("accept-ranges", "").lower() == "bytes"
    assert partial.headers.get("content-range", "").startswith("bytes 0-")

    return {
        "candidate_video_id": args.expected_video_id,
        "job_id": job_id,
        "job_state": job.get("state"),
        "job_attempts": job.get("attempts"),
        "track_id": track_id,
        "track_title": title,
        "range_status": partial.status,
        "range_bytes": len(partial.body),
        "authorization_basis": args.authorization_basis,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--authorized-query", required=True)
    parser.add_argument("--expected-video-id", required=True)
    parser.add_argument("--authorization-basis", required=True)
    parser.add_argument("--acknowledge-authorized", action="store_true", required=True)
    parser.add_argument("--discovery-timeout-seconds", type=float, default=60)
    parser.add_argument("--job-timeout-seconds", type=float, default=900)
    parser.add_argument("--poll-seconds", type=float, default=2)
    return parser.parse_args()


def main() -> int:
    result = run(parse_args())
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, ValueError, json.JSONDecodeError) as error:
        print(f"verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
