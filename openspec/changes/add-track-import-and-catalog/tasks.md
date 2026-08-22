## 1. Dependencies and configuration

- [x] 1.1 Add SQLAlchemy 2, Psycopg 3, Alembic, Mutagen, and multipart parsing as pinned-compatible backend dependencies, and verify a clean development install plus the existing test suite succeeds.
- [x] 1.2 Add settings for the PostgreSQL URL, media root, 500 MiB default upload limit, `ffprobe` executable and timeout, and reconciliation grace period; verify unit tests cover defaults, environment overrides, invalid values, and secret-safe validation errors.
- [x] 1.3 Extend `.env.example` and ignore rules for database placeholders, local media data, generated audio, and secrets; verify the example is sufficient to start Compose and `git check-ignore` covers local state without ignoring source fixtures.
- [x] 1.4 Add FFmpeg/`ffprobe` to the production image while retaining the non-root runtime user, and verify the built image reports an `ffprobe` version and the API process UID is non-root.

## 2. PostgreSQL persistence and migrations

- [x] 2.1 Create the synchronous SQLAlchemy engine/session lifecycle and application dependency boundaries, and verify sessions close on success and failure with focused tests.
- [x] 2.2 Define the track persistence model with UUID identity, public metadata, timestamps, unique SHA-256 digest, and opaque storage references; verify model/schema tests demonstrate internal fields cannot enter API representations.
- [x] 2.3 Configure Alembic and add the initial catalog migration, then verify upgrade from an empty PostgreSQL database reaches `head`, creates all constraints, and a migration round trip succeeds on an ephemeral database.
- [x] 2.4 Implement repository operations for digest lookup, create, detail, paginated count/list/search, and textual updates; verify PostgreSQL integration tests cover uniqueness, escaped case-insensitive search, deterministic ordering, pagination totals, and updated timestamps.
- [x] 2.5 Implement the transaction-scoped advisory lock for a content digest and verify a concurrent PostgreSQL integration test serializes identical import contenders.

## 3. Local media storage

- [x] 3.1 Define the narrow staging/durable storage interface and opaque key types, and verify type/unit tests reject absolute paths, traversal segments, and caller-controlled filesystem locations.
- [x] 3.2 Implement local staging writes, atomic audio/cover promotion, reads, and idempotent removal beneath separate namespaces; verify unit tests cover byte preservation, generated keys, cleanup, and filesystem errors.
- [x] 3.3 Implement reconciliation for aged staging and unreferenced durable objects with a database-availability guard and grace period; verify tests retain referenced/recent objects, remove eligible orphans, and perform no deletion when references cannot be queried.

## 4. Media inspection and normalization

- [x] 4.1 Implement the shell-free, timeout-bounded `ffprobe` JSON adapter and supported format/codec validation; verify real generated fixtures cover MP3, FLAC, AAC/ALAC in MP4/M4A, Ogg Vorbis, Ogg Opus, and PCM WAV plus unsupported, corrupt, and timeout cases.
- [x] 4.2 Implement Mutagen extraction for title, artist, album, and the first valid JPEG/PNG cover; verify synthetic tagged fixtures cover normalized single/multi-value tags, valid cover bytes and media type, no cover, and ignored malformed/unsupported cover data.
- [x] 4.3 Implement deterministic whitespace normalization and filename/placeholder fallbacks, and verify unit tests cover tag precedence, `Artist - Title`, stem-only title, and all required placeholder combinations.

## 5. Recoverable import workflow

- [x] 5.1 Implement chunked upload staging with simultaneous byte counting and SHA-256 calculation, and verify tests show the full request is never read in one operation, the configured limit is enforced with `413`, and staged bytes are removed on interruption or overflow.
- [x] 5.2 Implement the import application service in the designed validation-lock-promotion-commit order, and verify tests cover a durable success, unsupported `415`, unreadable `422`, ordinary failure compensation, and cleanup at every failing step.
- [x] 5.3 Implement duplicate resolution using advisory locking plus the database uniqueness constraint, and verify sequential and concurrent identical imports produce one track, one durable audio object, and `409` responses identifying the existing public track.
- [x] 5.4 Run startup reconciliation only after database access is established, and verify a restart integration test removes aged crash artifacts without deleting committed media.

## 6. Track API

- [x] 6.1 Add allow-listed Pydantic schemas and shared API error mapping, and verify serialization and error tests never expose digests, storage keys, local paths, connection details, command output, or tracebacks.
- [x] 6.2 Add `POST /api/v1/tracks/import` for exactly one multipart `file`, and verify API tests cover `201`, `409`, `413`, `415`, `422`, missing/extra file fields, fallback metadata, technical fields, and `has_cover`.
- [x] 6.3 Add track detail and paginated list/search endpoints, and verify API tests cover defaults, bounds, totals, stable ordering, blank queries, mixed-case substring matches, literal `%`/`_`, and `404` detail responses.
- [x] 6.4 Add partial title/artist/album correction, and verify API tests cover trimmed updates, unchanged omitted fields, advancing `updated_at`, empty-value `422`, read-only-field rejection, and missing-track `404`.
- [x] 6.5 Add cover retrieval through the storage interface, and verify API tests return exact JPEG/PNG bytes and media type while covering tracks without covers, missing tracks, and absent underlying objects without revealing keys.

## 7. Liveness and readiness

- [x] 7.1 Preserve `/health` as a dependency-independent process check, and verify it still returns exactly `200 {"status":"ok"}` while database and storage checks are forced to fail.
- [x] 7.2 Add `/ready` database-schema and storage write probes with bounded, safe diagnostics, and verify tests cover ready `200`, each dependency's `503` state, cleanup of probe files, and absence of secrets, paths, exceptions, and connection strings.

## 8. Compose and continuous integration

- [x] 8.1 Extend Compose with a pinned PostgreSQL service, health check, persistent database/media volumes, one-shot migration service, API dependency ordering, and loopback binding by default; verify `docker compose config` succeeds without embedding secrets.
- [x] 8.2 Verify the Compose lifecycle on a clean local project: build, migrate, become ready, import generated audio, restart containers, retain the track/media, and shut down without deleting named volumes.
- [x] 8.3 Extend GitHub Actions with PostgreSQL, migration, real media-tool tests, the complete backend suite, and the production container build; verify the workflow syntax is valid and all jobs pass on a branch or pull request.

## 9. Developer and server operations documentation

- [x] 9.1 Document direct and Compose development setup, environment creation, migrations, tests, synthetic fixture generation, and example import/detail/list/search/edit/cover requests; verify every documented local command works from a clean checkout.
- [x] 9.2 Document rootless-Docker server deployment, private LAN binding, volume discovery, paired database/media backup and restore, update/migration order, readiness diagnosis, and rollback limits; verify the runbook avoids `sudo`, public exposure, committed secrets, and destructive automatic downgrades.

## 10. End-to-end acceptance and scope check

- [x] 10.1 On the authorized Linux host as its deploy user, build and start the stack with rootless Docker Compose and verify migrations, `/health`, `/ready`, import, detail/list/search/edit, optional cover retrieval, duplicate rejection, and persistence across restart.
- [x] 10.2 Run the full automated suite and production image build, inspect the repository for secrets or media artifacts, and verify no audio streaming, Range support, playlist, Flutter, authentication, online lookup, background-worker, or automatic-deployment feature entered this change.
