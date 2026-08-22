# Arion

Arion is a private, self-hosted music application and a learning project for backend, data, container, and deployment practices. The current milestone provides a FastAPI backend that imports one audio file at a time, extracts metadata, stores media on the local server, and exposes a persistent searchable track catalog.

Audio playback/streaming, Flutter clients, playlists, authentication, public exposure, online metadata services, and automated deployment are not implemented yet.

## Repository structure

```text
.
|-- .github/workflows/ci.yml       # PostgreSQL tests and production image build
|-- backend/
|   |-- migrations/                # Alembic schema history
|   |-- src/arion_api/             # API, services, persistence, metadata, storage
|   |-- tests/                     # Unit, parser, PostgreSQL, and API tests
|   |-- Dockerfile                 # Non-root production and explicit test targets
|   |-- pyproject.toml             # Python project and dependency constraints
|   `-- uv.lock                    # Reproducible dependency lock
|-- docs/server.md                 # Rootless-Docker Linux runbook
|-- .env.example                   # Non-secret configuration example
`-- compose.yaml                   # API, migration job, and PostgreSQL
```

## Prerequisites

For direct backend development:

- `uv` 0.12.5 and Python 3.13
- PostgreSQL 18
- FFmpeg/`ffprobe` 7 or later

For the recommended container workflow:

- Docker Engine or Docker Desktop
- Docker Compose v2 (`docker compose`)

## Configuration

Create an untracked environment file and replace the database password placeholder in both `POSTGRES_PASSWORD` and `ARION_DATABASE_URL`:

```powershell
Copy-Item .env.example .env
```

On Linux or macOS:

```bash
cp .env.example .env
```

| Variable | Default/example | Purpose |
| --- | --- | --- |
| `ARION_ENVIRONMENT` | `development` | `development` or `production` label |
| `ARION_LOG_LEVEL` | `INFO` | Python application log level |
| `ARION_DATABASE_URL` | PostgreSQL URL | Psycopg/SQLAlchemy connection URL; treat it as a secret |
| `ARION_MEDIA_ROOT` | `/var/lib/arion/media` in Compose | Root containing staging, audio, and cover objects |
| `ARION_MAX_UPLOAD_BYTES` | `524288000` | Maximum received bytes per import (500 MiB) |
| `ARION_FFPROBE_EXECUTABLE` | `ffprobe` | Probe executable name or path |
| `ARION_FFPROBE_TIMEOUT_SECONDS` | `30` | Maximum probe duration |
| `ARION_RECONCILIATION_GRACE_SECONDS` | `3600` | Minimum age before crash artifacts can be removed |
| `ARION_BIND_ADDRESS` | `127.0.0.1` | Host address where Compose publishes the API |
| `ARION_PORT` | `8000` | Published host port |

Do not commit `.env`, database dumps, credentials, private keys, real audio, or generated media.

## Run with Docker Compose

Build the image, start PostgreSQL, run the migration gate, and start the API:

```bash
docker compose up --detach --build
docker compose ps --all
```

Verify process liveness and dependency readiness:

```bash
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8000/ready
```

Expected healthy responses are `{"status":"ok"}` and `{"status":"ready"}`. `/health` deliberately remains healthy during database or media-storage outages; `/ready` returns `503` and safe dependency states.

View logs or stop containers without deleting data:

```bash
docker compose logs --follow api migrate db
docker compose down
```

Do not add `--volumes` unless permanent database and media deletion is explicitly intended and backed up.

## Run directly for development

Install dependencies and ensure a disposable PostgreSQL 18 database is reachable from the host:

```bash
uv sync --frozen --project backend
```

For a host-run API, point the URL at the published development database (publish a PostgreSQL port through a local override if needed), set a writable media directory, and apply migrations:

```bash
export ARION_DATABASE_URL='postgresql+psycopg://arion:<password>@127.0.0.1:5432/arion'
export ARION_MEDIA_ROOT='./data/media'
uv run --frozen --project backend alembic -c backend/alembic.ini upgrade head
uv run --frozen --project backend uvicorn arion_api.main:app --reload --host 127.0.0.1 --port 8000
```

Compose does not publish PostgreSQL by default. Prefer running the whole stack unless direct host debugging requires a temporary loopback-only database-port override.

## Import and use the catalog

Generate a tiny synthetic WAV fixture; this commits no copyrighted media:

```bash
ffmpeg -v error -f lavfi -i sine=frequency=440:duration=0.2 -c:a pcm_s16le -y "Example Artist - Example Title.wav"
```

Import it and save the returned UUID:

```bash
curl --fail --form "file=@Example Artist - Example Title.wav" \
  http://127.0.0.1:8000/api/v1/tracks/import
```

The endpoint supports valid MP3, FLAC, AAC/ALAC in MP4/M4A, Ogg Vorbis, Ogg Opus, and PCM WAV. It inspects content rather than trusting the extension, calculates SHA-256 while streaming, rejects duplicates, and uses embedded tags before deterministic filename fallbacks.

Use the returned `<track-id>`:

```bash
curl --fail http://127.0.0.1:8000/api/v1/tracks
curl --fail --get --data-urlencode "q=example artist" \
  http://127.0.0.1:8000/api/v1/tracks
curl --fail http://127.0.0.1:8000/api/v1/tracks/<track-id>
curl --fail --request PATCH --header "Content-Type: application/json" \
  --data '{"title":"Corrected Title","album":"Corrected Album"}' \
  http://127.0.0.1:8000/api/v1/tracks/<track-id>
curl --fail --output cover-image \
  http://127.0.0.1:8000/api/v1/tracks/<track-id>/cover
```

Cover retrieval returns `404` when the track has no valid embedded JPEG/PNG cover. There is intentionally no audio download or streaming endpoint yet.

## Migrations and tests

Apply the current schema explicitly:

```bash
docker compose run --rm migrate
```

Run fast tests locally; PostgreSQL tests skip when no dedicated test URL is supplied:

```bash
uv run --frozen --project backend pytest backend/tests
```

For the complete suite, supply a disposable PostgreSQL database through `ARION_TEST_DATABASE_URL`. Tests create and drop the `tracks` table in that database, so never point the variable at production:

```bash
ARION_TEST_DATABASE_URL='postgresql+psycopg://arion:<password>@127.0.0.1:5432/arion_test' \
  uv run --frozen --project backend pytest backend/tests
```

The container test target also contains the locked dev dependencies and suite:

```bash
docker build --target test --tag arion-api:test ./backend
```

## Continuous integration

GitHub Actions uses hosted runners for pull requests and pushes to `main` or `master`. It:

- installs the frozen Python environment and FFmpeg
- starts a disposable PostgreSQL 18 service
- verifies migration upgrade, downgrade, and re-upgrade
- runs all unit, real-parser, PostgreSQL concurrency, and API tests
- builds the non-root production image without publishing it

No deployment or registry credentials are used in this milestone. See [the Linux server runbook](docs/server.md) for manual private deployment and persistent-volume operations.
