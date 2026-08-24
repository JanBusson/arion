#!/usr/bin/env python3
"""Black-box acceptance checks for the production Arion web gateway."""

from __future__ import annotations

import argparse
import io
import json
import math
import struct
import sys
import uuid
import wave
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urljoin
from urllib.request import Request, urlopen


FLUTTER_MARKERS = (b"flutter_bootstrap.js", b"<flt-glass-pane")


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
) -> Response:
    url = urljoin(f"{base_url.rstrip('/')}/", path.lstrip("/"))
    req = Request(url, data=body, method=method, headers=headers or {})
    try:
        with urlopen(req, timeout=20) as result:
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
        raise AssertionError(f"request to {url} failed: {error}") from error


def assert_status(response: Response, expected: int, label: str) -> None:
    assert response.status == expected, (
        f"{label}: expected HTTP {expected}, got {response.status}: "
        f"{response.body[:300]!r}"
    )


def assert_cache_contains(response: Response, token: str, label: str) -> None:
    value = response.headers.get("cache-control", "").lower()
    assert token in value, f"{label}: expected Cache-Control containing {token!r}, got {value!r}"


def assert_not_flutter_shell(response: Response, label: str) -> None:
    lower_body = response.body.lower()
    assert b"flutter_bootstrap.js" not in lower_body, f"{label}: returned Flutter index HTML"
    assert b"<title>arion</title>" not in lower_body, f"{label}: returned Flutter index HTML"


def wav_fixture(frequency: int) -> bytes:
    sample_rate = 8_000
    frame_count = sample_rate // 5
    output = io.BytesIO()
    with wave.open(output, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        frames = bytearray()
        for index in range(frame_count):
            sample = int(8_000 * math.sin(2 * math.pi * frequency * index / sample_rate))
            frames.extend(struct.pack("<h", sample))
        wav_file.writeframes(bytes(frames))
    return output.getvalue()


def multipart_file(field: str, filename: str, content_type: str, data: bytes) -> tuple[bytes, str]:
    boundary = f"arion-{uuid.uuid4().hex}"
    prefix = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
        f"Content-Type: {content_type}\r\n\r\n"
    ).encode("ascii")
    suffix = f"\r\n--{boundary}--\r\n".encode("ascii")
    return prefix + data + suffix, f"multipart/form-data; boundary={boundary}"


def verify_static(base_url: str) -> None:
    index = request(base_url, "/")
    assert_status(index, 200, "application entry point")
    assert "text/html" in index.headers.get("content-type", "").lower()
    assert any(marker in index.body for marker in FLUTTER_MARKERS)
    assert_cache_contains(index, "no-cache", "application entry point")

    bootstrap = request(base_url, "/flutter_bootstrap.js")
    assert_status(bootstrap, 200, "Flutter bootstrap")
    assert "javascript" in bootstrap.headers.get("content-type", "").lower()
    assert_cache_contains(bootstrap, "no-cache", "Flutter bootstrap")

    browser_route = request(base_url, "/library/now-playing")
    assert_status(browser_route, 200, "extensionless browser route")
    assert b"flutter_bootstrap.js" in browser_route.body
    assert_cache_contains(browser_route, "no-cache", "extensionless browser route")

    for path in ("/missing.js", "/assets/missing-font"):
        missing = request(base_url, path)
        assert_status(missing, 404, f"missing asset {path}")
        assert_not_flutter_shell(missing, f"missing asset {path}")


def verify_api(base_url: str, direct_api_url: str | None) -> None:
    health = request(base_url, "/health")
    assert_status(health, 200, "gateway health proxy")
    assert json.loads(health.body) == {"status": "ok"}
    assert_cache_contains(health, "no-store", "gateway health proxy")

    ready = request(base_url, "/ready")
    assert_status(ready, 200, "gateway readiness proxy")
    assert json.loads(ready.body) == {"status": "ready"}
    assert_cache_contains(ready, "no-store", "gateway readiness proxy")

    probe = uuid.uuid4().hex[:12]
    filename = f"Gateway Artist - Gateway Probe {probe}.wav"
    audio = wav_fixture(440 + int(probe[:2], 16))
    upload, content_type = multipart_file("file", filename, "audio/wav", audio)
    created = request(
        base_url,
        "/api/v1/tracks/import",
        method="POST",
        body=upload,
        headers={"Content-Type": content_type},
    )
    assert_status(created, 201, "gateway track import")
    assert_cache_contains(created, "no-store", "gateway track import")
    track_id = json.loads(created.body)["id"]

    listing = request(
        base_url,
        f"/api/v1/tracks?limit=10&offset=0&q={quote(f'Gateway Probe {probe}')}",
    )
    assert_status(listing, 200, "gateway catalog query")
    assert any(item["id"] == track_id for item in json.loads(listing.body)["items"])
    assert_cache_contains(listing, "no-store", "gateway catalog query")

    cover = request(base_url, f"/api/v1/tracks/{track_id}/cover")
    assert_status(cover, 404, "cover fallback through gateway")
    assert_not_flutter_shell(cover, "cover fallback through gateway")
    assert_cache_contains(cover, "no-store", "cover fallback through gateway")

    audio_path = f"/api/v1/tracks/{track_id}/audio"
    complete = request(base_url, audio_path)
    assert_status(complete, 200, "complete gateway audio")
    assert complete.body == audio
    assert complete.headers.get("accept-ranges", "").lower() == "bytes"
    assert int(complete.headers["content-length"]) == len(audio)
    assert complete.headers.get("content-type", "").startswith("audio/")
    assert_cache_contains(complete, "no-store", "complete gateway audio")

    range_header = {"Range": "bytes=10-31"}
    partial = request(base_url, audio_path, headers=range_header)
    assert_status(partial, 206, "ranged gateway audio")
    assert partial.body == audio[10:32]
    assert partial.headers.get("content-range") == f"bytes 10-31/{len(audio)}"
    assert partial.headers.get("content-length") == "22"
    assert partial.headers.get("accept-ranges", "").lower() == "bytes"
    assert_cache_contains(partial, "no-store", "ranged gateway audio")

    if direct_api_url:
        direct_complete = request(direct_api_url, audio_path)
        direct_partial = request(direct_api_url, audio_path, headers=range_header)
        assert direct_complete.status == complete.status
        assert direct_complete.body == complete.body
        assert direct_partial.status == partial.status
        assert direct_partial.body == partial.body
        for header in ("content-range", "content-length", "accept-ranges", "content-type"):
            assert direct_partial.headers.get(header) == partial.headers.get(header), (
                f"ranged gateway audio changed {header}: "
                f"{direct_partial.headers.get(header)!r} != {partial.headers.get(header)!r}"
            )


def verify_unavailable(base_url: str) -> None:
    response = request(base_url, "/api/v1/tracks")
    assert response.status in {502, 503, 504}, (
        f"unavailable API: expected a gateway error, got {response.status}: {response.body[:300]!r}"
    )
    assert_not_flutter_shell(response, "unavailable API")
    assert_cache_contains(response, "no-store", "unavailable API")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True, help="Published web gateway origin")
    parser.add_argument("--direct-api-url", help="Optional direct API origin for response comparison")
    parser.add_argument(
        "--expect-api-unavailable",
        action="store_true",
        help="Only assert that an API request returns a non-cacheable gateway error",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.expect_api_unavailable:
        verify_unavailable(args.base_url)
        print("web gateway unavailable-backend checks passed")
        return 0

    verify_static(args.base_url)
    verify_api(args.base_url, args.direct_api_url)
    print("web gateway static, proxy, cache, health, and range checks passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
