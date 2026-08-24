# Arion

Arion is a private, self-hosted music application and a learning project for backend, data, container, and deployment practices. The FastAPI backend imports audio, extracts metadata, stores media on the local server, exposes a searchable catalog, and streams original audio with HTTP byte-range seeking. One Flutter client connects from Android or is served through the private web gateway to search the library and play tracks.

Playlists, authentication, public exposure, online metadata services, transcoding, background playback, and automated deployment are not implemented yet.

## Repository structure

```text
.
|-- .github/workflows/ci.yml       # Backend and pinned-SDK Flutter validation
|-- backend/
|   |-- migrations/                # Alembic schema history
|   |-- src/arion_api/             # API, services, persistence, metadata, storage
|   |-- tests/                     # Unit, parser, PostgreSQL, and API tests
|   |-- Dockerfile                 # Non-root production and explicit test targets
|   |-- pyproject.toml             # Python project and dependency constraints
|   `-- uv.lock                    # Reproducible dependency lock
|-- client/                        # Flutter app, production web image, Nginx gateway, and tests
|-- docs/server.md                 # Rootless-Docker Linux runbook
|-- scripts/                       # Compose and black-box web gateway verification
|-- .flutter-version               # Pinned Flutter stable SDK version
|-- .env.example                   # Non-secret configuration example
`-- compose.yaml                   # Web gateway, API, migration job, and PostgreSQL
```

## Prerequisites

For direct backend development:

- `uv` 0.12.5 and Python 3.13
- PostgreSQL 18
- FFmpeg/`ffprobe` 7 or later

For client development:

- Flutter 3.44.7 stable (the version in `.flutter-version`)
- Chrome or Edge for web development
- Android Studio/Android SDK plus an emulator or connected device for APK work

Run `flutter doctor -v` after installing Flutter. The web toolchain should list an available browser; Android builds additionally require an accepted and healthy Android toolchain.

For the recommended container workflow:

- Docker Engine or Docker Desktop
- Docker Compose v2 (`docker compose`)

The production web image downloads and verifies the pinned Flutter SDK while building, so the Docker Compose workflow does not require Flutter on the host.

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
| `ARION_CORS_ORIGINS` | empty | Comma-separated exact browser origins allowed to call the API |
| `ARION_BIND_ADDRESS` | `127.0.0.1` | Host address where Compose publishes the API |
| `ARION_PORT` | `8000` | Published host port |
| `ARION_WEB_BIND_ADDRESS` | `127.0.0.1` | Host address where Compose publishes the web/API gateway |
| `ARION_WEB_PORT` | `8080` | Published web/API gateway port |
| `ARION_API_IMAGE` | `arion-api:local` | API/migration image name; override for isolated or versioned builds |
| `ARION_WEB_IMAGE` | `arion-web:local` | Web gateway image name; override for isolated or versioned builds |

Do not commit `.env`, database dumps, credentials, private keys, real audio, or generated media.

## Run with Docker Compose

Build the image, start PostgreSQL, run the migration gate, and start the API:

```bash
docker compose up --detach --build
docker compose ps --all
```

Verify the direct API and the published web gateway:

```bash
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8000/ready
curl --fail http://127.0.0.1:8080/
curl --fail http://127.0.0.1:8080/health
curl --fail http://127.0.0.1:8080/ready
```

Expected healthy responses are `{"status":"ok"}` and `{"status":"ready"}`. `/health` deliberately remains healthy during database or media-storage outages; `/ready` returns `503` and safe dependency states.

View logs or stop containers without deleting data:

```bash
docker compose logs --follow web api migrate db
docker compose down
```

Do not add `--volumes` unless permanent database and media deletion is explicitly intended and backed up.

### Use the production web gateway

Open `http://127.0.0.1:8080` after the stack is healthy. On first launch, enter that same origin, `http://127.0.0.1:8080`, as the Arion API address. Catalog, cover, and audio requests then use the gateway's same-origin `/api/` proxy, while `/health` and `/ready` expose the existing safe operational responses.

For private-LAN use, keep the direct API on loopback and publish only the gateway on the server's fixed LAN address:

```dotenv
ARION_BIND_ADDRESS=127.0.0.1
ARION_WEB_BIND_ADDRESS=192.168.1.50
ARION_WEB_PORT=8080
```

Then open `http://192.168.1.50:8080` and enter that exact origin in the client. Android can use the same gateway address. The loopback defaults prevent implicit publication on all interfaces; do not replace either address with `0.0.0.0` as an ad hoc fix.

Build only the deployable web image when needed:

```bash
docker compose build web
```

The multi-stage build verifies the official Flutter 3.44.7 archive checksum and copies only `build/web` into a pinned unprivileged Nginx runtime. Source maps are not produced, and the runtime contains neither the Flutter toolchain nor the client source tree.

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

## Run the Flutter client

Install the committed application dependencies from the repository root:

```bash
cd client
flutter pub get --enforce-lockfile
```

On first launch, Arion asks for an absolute API URL such as `http://192.168.1.50:8000`. The accepted value is normalized and saved locally, and it can be changed later from Settings. A development or CI build can provide an initial value without embedding a production address in source code:

```bash
flutter run -d chrome --web-port 8080 \
  --dart-define=ARION_API_BASE_URL=http://127.0.0.1:8000
```

A saved setting takes precedence over `ARION_API_BASE_URL`. A separately served development client requires its exact origin in the backend allow-list. For the command above, use this `.env` value and restart the API:

```dotenv
ARION_CORS_ORIGINS=http://localhost:8080
```

Multiple separate development origins are comma-separated. Do not use `*`; an empty value is the default and grants no cross-origin browser access. The production gateway is same-origin and does not require a CORS entry.

Run client checks and create the web release:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
```

Build and install an Android debug APK when the Android toolchain is available:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Android permits owner-configured cleartext HTTP so it can reach a private LAN server. Keep the API bound to the private network and send no credentials over HTTP. Prefer HTTPS or Tailscale before any remote access, and do not expose Arion through public port forwarding by default.

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

Cover retrieval returns `404` when the track has no valid embedded JPEG/PNG cover.

Stream the complete original audio object:

```bash
curl --fail --output track-audio \
  http://127.0.0.1:8000/api/v1/tracks/<track-id>/audio
```

Request an inclusive byte range, as browser and Android players do when seeking:

```bash
curl --fail --header "Range: bytes=0-65535" --output first-audio-range \
  http://127.0.0.1:8000/api/v1/tracks/<track-id>/audio
```

A complete request returns `200`; a satisfiable single range returns `206` with `Content-Range`, `Content-Length`, and `Accept-Ranges: bytes`. Bounded (`start-end`), open-ended (`start-`), and suffix (`-length`) ranges are supported. Invalid, multiple, or unsatisfiable ranges return `416` with no audio bytes. Arion streams the imported object in bounded chunks with its canonical audio media type; it does not transcode or adapt bitrate.

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

With the disposable Compose stack running, exercise the production gateway and compare proxied audio responses with direct FastAPI responses:

```bash
docker compose config --format json | python scripts/verify_compose_config.py
python scripts/verify_web_gateway.py \
  --base-url http://127.0.0.1:8080 \
  --direct-api-url http://127.0.0.1:8000
```

The gateway check creates a unique tiny synthetic WAV in the configured development stack. Do not run it against production data. CI also stops its disposable API briefly and verifies that the gateway returns a non-cacheable error rather than the Flutter application shell.

## Continuous integration

GitHub Actions uses hosted runners for pull requests and pushes to `main` or `master`. It:

- installs the frozen Python environment and FFmpeg
- starts a disposable PostgreSQL 18 service
- verifies migration upgrade, downgrade, and re-upgrade
- runs all unit, real-parser, PostgreSQL concurrency, and API tests
- installs Flutter 3.44.7, verifies formatting and analysis, runs client tests, and builds the web release
- builds the non-root production image without publishing it
- renders and checks loopback/private-LAN Compose bindings, builds the production web image, starts a disposable stack, and verifies static routes, proxying, caching, health, failure handling, and ranged playback

No deployment or registry credentials are used in this milestone. See [the Linux server runbook](docs/server.md) for manual private deployment and persistent-volume operations.
