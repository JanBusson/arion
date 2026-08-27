"""Sanitized structured logging for background operations."""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime

_SAFE_EVENT_FIELDS = (
    "event",
    "job_id",
    "state",
    "phase",
    "progress_percent",
    "duration_ms",
    "output_bytes",
    "candidate_count",
    "attempt",
    "will_retry",
    "failure_code",
    "stream_copy",
    "removed_jobs",
    "removed_workspaces",
)


class SanitizedJsonFormatter(logging.Formatter):
    """Serialize only operational fields that are safe to expose in logs."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for field in _SAFE_EVENT_FIELDS:
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value
        return json.dumps(payload, ensure_ascii=True, separators=(",", ":"))


def configure_structured_logging(level: str) -> None:
    """Configure the worker process with one predictable JSON log handler."""

    handler = logging.StreamHandler()
    handler.setFormatter(SanitizedJsonFormatter())
    logging.basicConfig(level=level, handlers=[handler], force=True)
