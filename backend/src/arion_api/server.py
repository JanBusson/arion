"""Production API process with sanitized logging and no query-bearing access log."""

from __future__ import annotations

import uvicorn

from arion_api.config import get_settings
from arion_api.logging_config import configure_structured_logging


def main() -> None:
    settings = get_settings()
    configure_structured_logging(settings.log_level)
    uvicorn.run(
        "arion_api.main:app",
        host="0.0.0.0",
        port=8000,
        access_log=False,
        log_config=None,
    )


if __name__ == "__main__":
    main()
