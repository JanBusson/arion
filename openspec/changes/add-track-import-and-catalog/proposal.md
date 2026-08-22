## Why

Arion's foundation is runnable but cannot yet accept or remember music. The next useful increment is a complete ingestion-to-catalog path that stores one audio file safely, extracts trustworthy metadata, and exposes the resulting track for search and correction.

## What Changes

- Add PostgreSQL-backed persistence, versioned schema migrations, and container orchestration for the catalog.
- Add a local-filesystem storage backend behind an application interface, with separate staging, audio, and cover locations and persistent server storage.
- Add a versioned API for importing one supported audio file at a time with a configured size limit, SHA-256 duplicate detection, atomic cleanup on failure, and no online recognition dependency.
- Extract embedded title, artist, album, and cover art with Mutagen; extract duration, codec, bitrate, and sample rate with `ffprobe`; apply deterministic filename and placeholder fallbacks when tags are missing.
- Add track detail, paginated listing, case-insensitive search, manual title/artist/album correction, and extracted cover retrieval.
- Add a readiness endpoint that checks the new required database and filesystem dependencies without changing the existing liveness endpoint.
- Extend automated tests, CI, Compose, configuration examples, and runbooks for PostgreSQL, migrations, media storage, `ffprobe`, and the import/catalog workflow.
- Continue to defer audio streaming and HTTP Range support, playlists, Flutter clients, authentication, background workers, public exposure, online metadata lookup, and automated production deployment.

## Capabilities

### New Capabilities

- `audio-import`: Accepts, validates, deduplicates, inspects, and durably stores a single uploaded audio file and its extracted metadata and cover art.
- `track-catalog`: Provides persistent track detail, paginated listing, search, metadata correction, and cover retrieval APIs.
- `service-readiness`: Reports whether required database and filesystem dependencies are ready while preserving process liveness semantics.

### Modified Capabilities

None.

## Impact

- Extends the FastAPI modular monolith with API, domain/application, persistence, metadata, and storage modules while retaining one deployable backend image.
- Adds PostgreSQL and a one-shot migration service to Docker Compose, plus persistent database and media storage.
- Adds SQLAlchemy, Psycopg, Alembic, Mutagen, and multipart parsing as Python dependencies and `ffprobe` as an image runtime dependency.
- Adds product API endpoints below `/api/v1`; the existing `GET /health` contract remains unchanged.
- Introduces persistent state and migrations, so server updates and rollback procedures must distinguish code rollback from database/media rollback.
