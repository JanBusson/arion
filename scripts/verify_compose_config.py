#!/usr/bin/env python3
"""Assert security-sensitive fields in `docker compose config --format json`."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def published_port(service: dict[str, Any], target: int) -> dict[str, Any]:
    for port in service.get("ports", []):
        if int(port.get("target", -1)) == target:
            return port
    raise AssertionError(f"no published mapping targets container port {target}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-web-host", default="127.0.0.1")
    parser.add_argument("--expected-web-port", default="8080")
    parser.add_argument("--expected-api-host", default="127.0.0.1")
    parser.add_argument("--expected-api-port", default="8000")
    args = parser.parse_args()

    config = json.load(sys.stdin)
    services = config["services"]
    assert set(("db", "migrate", "api", "worker", "web")).issubset(services)

    assert not services["db"].get("ports"), "PostgreSQL must not publish a host port"

    api_port = published_port(services["api"], 8000)
    assert api_port.get("host_ip") == args.expected_api_host
    assert str(api_port.get("published")) == args.expected_api_port

    web = services["web"]
    web_port = published_port(web, 8080)
    assert web_port.get("host_ip") == args.expected_web_host
    assert str(web_port.get("published")) == args.expected_web_port
    assert web.get("restart") == "unless-stopped"
    assert web.get("read_only") is True
    assert web.get("depends_on", {}).get("api", {}).get("condition") == "service_healthy"
    assert web.get("healthcheck", {}).get("test"), "web health check is missing"

    worker = services["worker"]
    assert worker.get("command") == ["python", "-m", "arion_api.worker"]
    assert worker.get("user") == "10001:10001"
    assert worker.get("read_only") is True
    assert worker.get("restart") == "unless-stopped"
    assert worker.get("healthcheck", {}).get("disable") is True
    assert worker.get("depends_on", {}).get("migrate", {}).get("condition") == (
        "service_completed_successfully"
    )
    assert worker.get("security_opt") == ["no-new-privileges:true"]
    assert worker.get("environment", {}).get("ARION_YOUTUBE_ACQUISITION_ENABLED") == (
        "false"
    )
    api_volumes = {volume.get("target") for volume in services["api"].get("volumes", [])}
    worker_volumes = {volume.get("target") for volume in worker.get("volumes", [])}
    assert "/var/lib/arion/media" in api_volumes & worker_volumes
    assert float(worker.get("cpus", 0)) == 1.0
    assert int(worker.get("mem_limit", 0)) == 805306368

    print(
        "Compose bindings, worker isolation, dependency, health, restart, "
        "and database isolation checks passed"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, TypeError, ValueError) as error:
        print(f"Compose verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
