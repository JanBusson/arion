# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.13
ARG UV_VERSION=0.12.5

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM python:${PYTHON_VERSION}-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

COPY --from=uv /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY src ./src
RUN uv sync --frozen --no-dev --no-editable

FROM python:${PYTHON_VERSION}-slim AS runtime

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 arion \
    && useradd --system --uid 10001 --gid arion --home-dir /nonexistent arion

WORKDIR /app

COPY --from=builder --chown=10001:10001 /app/.venv /app/.venv
COPY --from=builder --chown=10001:10001 /app/src /app/src
COPY --chown=10001:10001 alembic.ini ./alembic.ini
COPY --chown=10001:10001 migrations ./migrations

RUN mkdir --parents /var/lib/arion/media \
    && chown --recursive 10001:10001 /var/lib/arion/media

USER 10001:10001

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).read()"]

CMD ["uvicorn", "arion_api.main:app", "--host", "0.0.0.0", "--port", "8000"]

FROM builder AS test-builder

RUN uv sync --frozen --no-editable

FROM runtime AS test

USER root
COPY --from=test-builder --chown=10001:10001 /app/.venv /app/.venv
COPY --chown=10001:10001 tests /app/tests
USER 10001:10001

CMD ["pytest", "/app/tests"]

FROM runtime AS production
