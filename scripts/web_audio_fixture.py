#!/usr/bin/env python3
"""Serve two synthetic ranged WAV sources for the Flutter Chrome regression."""

from __future__ import annotations

import argparse
import io
import json
import math
import struct
import threading
import time
import urllib.parse
import wave
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def _wav_bytes(*, frequency_hz: int, duration_seconds: float) -> bytes:
    sample_rate = 8_000
    frame_count = round(sample_rate * duration_seconds)
    output = io.BytesIO()
    with wave.open(output, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(sample_rate)
        frames = bytearray()
        for index in range(frame_count):
            sample = round(
                8_000 * math.sin(2 * math.pi * frequency_hz * index / sample_rate)
            )
            frames.extend(struct.pack("<h", sample))
        audio.writeframes(frames)
    return output.getvalue()


SOURCES = {
    "/audio/first.wav": _wav_bytes(frequency_hz=440, duration_seconds=1.0),
    "/audio/second.wav": _wav_bytes(frequency_hz=660, duration_seconds=1.6),
}

DURATIONS_MS = {
    "/audio/first.wav": 1_000,
    "/audio/second.wav": 1_600,
}


class FixtureState:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._requests: list[dict[str, str | None]] = []

    def record(self, *, method: str, path: str, byte_range: str | None) -> None:
        entry = {"method": method, "path": path, "range": byte_range}
        with self._lock:
            self._requests.append(entry)
        print(json.dumps(entry, sort_keys=True), flush=True)

    def reset(self) -> None:
        with self._lock:
            self._requests.clear()

    def snapshot(self) -> list[dict[str, str | None]]:
        with self._lock:
            return list(self._requests)


class FixtureHandler(BaseHTTPRequestHandler):
    server: "FixtureServer"

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(HTTPStatus.NO_CONTENT)
        self._cors_headers()
        self.send_header("Access-Control-Allow-Headers", "Range")
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
        self.end_headers()

    def do_HEAD(self) -> None:  # noqa: N802
        self._serve(send_body=False)

    def do_GET(self) -> None:  # noqa: N802
        self._serve(send_body=True)

    def _serve(self, *, send_body: bool) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path == "/health":
            self._json({"status": "ok"})
            return
        if parsed.path == "/reset":
            self.server.state.reset()
            self._json({"status": "reset"})
            return
        if parsed.path == "/requests":
            self._json({"requests": self.server.state.snapshot()})
            return

        payload = SOURCES.get(parsed.path)
        if payload is None:
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        byte_range = self.headers.get("Range")
        self.server.state.record(
            method=self.command,
            path=parsed.path,
            byte_range=byte_range,
        )
        query = urllib.parse.parse_qs(parsed.query)
        delay_ms = min(int(query.get("delay_ms", ["0"])[0]), 5_000)
        if delay_ms > 0:
            time.sleep(delay_ms / 1_000)

        start, end = self._range(byte_range, len(payload))
        response = payload[start : end + 1]
        status = HTTPStatus.PARTIAL_CONTENT if byte_range else HTTPStatus.OK
        self.send_response(status)
        self._cors_headers()
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header(
            "X-Arion-Test-Duration-Ms", str(DURATIONS_MS[parsed.path])
        )
        self.send_header("Content-Length", str(len(response)))
        if byte_range:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(payload)}")
        self.end_headers()
        if send_body:
            try:
                self.wfile.write(response)
            except (BrokenPipeError, ConnectionResetError):
                # Superseding a delayed browser request intentionally aborts it.
                return

    @staticmethod
    def _range(header: str | None, length: int) -> tuple[int, int]:
        if not header:
            return 0, length - 1
        unit, _, value = header.partition("=")
        if unit != "bytes" or "," in value:
            raise ValueError(f"Unsupported Range header: {header}")
        start_text, _, end_text = value.partition("-")
        if not start_text:
            suffix = min(int(end_text), length)
            return length - suffix, length - 1
        start = int(start_text)
        end = min(int(end_text), length - 1) if end_text else length - 1
        return start, end

    def _json(self, value: object) -> None:
        payload = json.dumps(value).encode()
        self.send_response(HTTPStatus.OK)
        self._cors_headers()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header(
            "Access-Control-Expose-Headers",
            "Content-Range, X-Arion-Test-Duration-Ms",
        )

    def log_message(self, format: str, *args: object) -> None:
        return


class FixtureServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int]) -> None:
        super().__init__(address, FixtureHandler)
        self.state = FixtureState()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18_081)
    args = parser.parse_args()
    FixtureServer((args.host, args.port)).serve_forever()


if __name__ == "__main__":
    main()
