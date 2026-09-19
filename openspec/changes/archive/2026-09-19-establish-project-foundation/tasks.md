## 1. Python Project Foundation

- [x] 1.1 Create the `backend/src/arion_api` and `backend/tests` package layout with a Python 3.13 `pyproject.toml`, minimal runtime and test dependencies, and project metadata; verify `uv sync` installs the project successfully in a clean environment.
- [x] 1.2 Generate and commit `backend/uv.lock`, then verify `uv sync --frozen --project backend` succeeds without changing the lockfile.
- [x] 1.3 Add typed `ARION_`-prefixed application settings with documented development defaults and validation, then verify automated tests cover default loading and rejection of at least one invalid setting.
- [x] 1.4 Add repository and Docker ignore rules plus a secret-free root `.env.example`; verify `.env` and local variants are ignored, `.env.example` remains trackable, and no credential value is present in the example.

## 2. Backend Service and Tests

- [x] 2.1 Implement the FastAPI application factory and module-level ASGI app without external service initialization; verify the app can be created and started with the documented default configuration.
- [x] 2.2 Implement unauthenticated `GET /health` with the exact foundation response contract; verify a focused pytest asserts status `200`, JSON content type, and body `{"status":"ok"}` using the in-process test client.
- [x] 2.3 Run the complete backend test suite with `uv run --frozen --project backend pytest backend/tests` and verify it passes without a database, network service, or music fixture.

## 3. Containerized Operation

- [x] 3.1 Add a multi-stage `backend/Dockerfile` and `.dockerignore` that install locked runtime dependencies, run under a non-root user, and define a standard-library health check against `/health`; verify the image builds and its configured runtime user is not root.
- [x] 3.2 Add a one-service `compose.yaml` with environment configuration, a configurable published address and port, and a `127.0.0.1` default bind; verify `docker compose config` resolves successfully both with defaults and with the documented private-LAN override.
- [x] 3.3 Start the Compose application from a clean build and verify the container reaches `healthy` state and `GET /health` is reachable through the configured host URL, then stop it cleanly with Docker Compose.

## 4. Continuous Integration

- [x] 4.1 Add `.github/workflows/ci.yml` for pull requests and pushes to `main` and `master`, with read-only repository permissions and a frozen Python 3.13 dependency install; verify the workflow contains no secret, registry login, deployment, or self-hosted-runner step.
- [x] 4.2 Configure separate CI checks for the pytest suite and a backend Docker build with publication disabled; verify the workflow commands match the locally passing test and image-build commands and fail when either command fails.

## 5. Developer and Server Documentation

- [x] 5.1 Write `README.md` as the project entry point with repository structure, prerequisites, environment setup, direct local startup, tests, image build, Compose start, health verification, logs, and shutdown commands; verify every referenced file and command matches the implemented foundation.
- [x] 5.2 Write `docs/server.md` for private Ubuntu Server operation, including Docker prerequisites, repository checkout/update, untracked environment configuration, private-LAN binding, source-built Compose deployment, health and log checks, shutdown, update, and rollback; verify the guide clearly labels source builds as interim and does not instruct public exposure.

## 6. Foundation Acceptance

- [x] 6.1 Validate the complete change with the backend tests, locked install check, Docker image build, Compose configuration, running container health check, and an HTTP request to `/health`; record the executed commands and successful results in the implementation handoff.
- [x] 6.2 Review the resulting tree and tracked files against the proposal non-goals; verify no Flutter, PostgreSQL, streaming, metadata, authentication, reverse proxy, registry publication, deployment automation, music files, or committed local environment file was introduced.
