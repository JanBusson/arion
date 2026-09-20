from __future__ import annotations

import json
import logging

from arion_api.logging_config import SanitizedJsonFormatter


def test_structured_formatter_keeps_allow_listed_operational_fields() -> None:
    record = logging.LogRecord(
        name="arion_api.worker",
        level=logging.WARNING,
        pathname="/private/source/worker.py",
        lineno=42,
        msg="acquisition_job_retrying",
        args=(),
        exc_info=None,
    )
    record.event = "acquisition_job_retrying"
    record.job_id = "20f7a184-04b7-414c-a8c7-dae30a2e53fd"
    record.duration_ms = 125
    record.output_bytes = 4096
    record.discovery_mode = "music"
    record.candidate_count = 5
    record.failure_code = "provider_failed"
    record.attempt = 1
    record.will_retry = True

    payload = json.loads(SanitizedJsonFormatter().format(record))

    assert payload["level"] == "WARNING"
    assert payload["message"] == "acquisition_job_retrying"
    assert payload["event"] == "acquisition_job_retrying"
    assert payload["job_id"] == "20f7a184-04b7-414c-a8c7-dae30a2e53fd"
    assert payload["duration_ms"] == 125
    assert payload["output_bytes"] == 4096
    assert payload["discovery_mode"] == "music"
    assert payload["candidate_count"] == 5
    assert payload["failure_code"] == "provider_failed"
    assert payload["attempt"] == 1
    assert payload["will_retry"] is True


def test_structured_formatter_excludes_paths_commands_secrets_and_external_output() -> None:
    record = logging.LogRecord(
        name="arion_api.worker",
        level=logging.ERROR,
        pathname="/private/source/worker.py",
        lineno=42,
        msg="acquisition_job_failed",
        args=(),
        exc_info=None,
    )
    record.event = "acquisition_job_failed"
    record.raw_command = ["yt-dlp", "--cookies", "/private/cookies.txt"]
    record.workspace = "/private/staging/job-id"
    record.secret = "do-not-log"
    record.stderr = "unbounded external output"

    rendered = SanitizedJsonFormatter().format(record)
    payload = json.loads(rendered)

    assert payload["event"] == "acquisition_job_failed"
    assert "raw_command" not in payload
    assert "workspace" not in payload
    assert "secret" not in payload
    assert "stderr" not in payload
    assert "/private" not in rendered
    assert "do-not-log" not in rendered
    assert "unbounded external output" not in rendered
