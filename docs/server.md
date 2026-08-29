# Private Linux server runbook

This runbook deploys Arion through rootless Docker Compose on a private Linux server. The stack includes an unprivileged Nginx container that serves the Flutter web build and proxies the private API. It does not configure public access, router port forwarding, TLS, Tailscale, or automatic deployment.

## Prerequisites and security boundary

- Use only the dedicated non-root deployment user.
- Docker Engine and Compose v2 must already work for that user.
- Use a trusted checkout and private LAN address.
- Never use `sudo` for these application procedures.
- Never run untrusted pull-request code on this server.
- A host Flutter SDK is not required; the pinned web-image builder provides it.

Verify the rootless context:

```bash
whoami
docker version
docker compose version
```

## Initial configuration

Clone the trusted repository and create an untracked configuration:

```bash
git clone <repository-url> arion
cd arion
cp .env.example .env
```

Edit `.env` with a unique database password, using its URL-encoded value in `ARION_DATABASE_URL`. Keep the direct API on loopback and bind only the web gateway to the fixed private address:

```dotenv
ARION_ENVIRONMENT=production
ARION_LOG_LEVEL=INFO
POSTGRES_DB=arion
POSTGRES_USER=arion
POSTGRES_PASSWORD=<strong-private-password>
ARION_DATABASE_URL=postgresql+psycopg://arion:<url-encoded-password>@db:5432/arion
ARION_BIND_ADDRESS=127.0.0.1
ARION_PORT=8000
ARION_WEB_BIND_ADDRESS=<server-lan-ip>
ARION_WEB_PORT=8080
```

Keep the default `/var/lib/arion/media` container path. Compose stores PostgreSQL and media in rootless-Docker named volumes, avoiding fragile host UID mappings.

Resolve and inspect configuration before starting:

```bash
docker compose config --quiet
docker compose config
```

Confirm that the web service publishes only the intended private address, the API publishes only loopback, PostgreSQL has no published host port, and no real credential appears in a checked-in file. Do not use `0.0.0.0` or configure router forwarding unless public exposure is designed in a later security change.

## First deployment

Build the API and web images, start PostgreSQL, run the one-shot migration, and start the API and gateway:

```bash
docker compose up --detach --build
docker compose ps --all
```

The expected states are:

- `db`: running and healthy
- `migrate`: exited successfully with status 0
- `api`: running and healthy
- `worker`: running and idle while YouTube acquisition is disabled
- `web`: running and healthy

Check both operational endpoints from the server:

```bash
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8000/ready
curl --fail http://<server-lan-ip>:8080/
curl --fail http://<server-lan-ip>:8080/health
curl --fail http://<server-lan-ip>:8080/ready
```

The first direct API command above must use `127.0.0.1`, because the API is intentionally not published to the LAN. From a trusted PC, open `http://<server-lan-ip>:8080`, enter that same origin as the server address on first launch, then load the library and play a track. Android can use the same gateway origin. If access fails, inspect the configured bind address and existing host-network policy; do not weaken server or router security as an ad hoc fix.

## Logs and readiness diagnosis

```bash
docker compose logs --follow web api worker
docker compose logs migrate db
docker compose ps --all
```

`/health` confirms that the FastAPI process is alive. `/ready` additionally checks the migrated catalog table and writable media storage. Its public response contains only `database` and `storage` states; detailed errors remain in logs.

## Persistent volumes

List and inspect the project volumes:

```bash
docker volume ls --filter label=com.docker.compose.project=arion
docker volume inspect arion_postgres_data
docker volume inspect arion_media_data
```

`arion_postgres_data` contains catalog metadata and storage references. `arion_media_data` contains staging, audio, and covers. Treat them as one backup set because restoring only one can leave missing media or orphaned files.

Stopping the stack preserves both volumes:

```bash
docker compose down
```

Never use `docker compose down --volumes` for a normal stop or update.

## Backup

Create a private backup directory with permissions limited to the deployment user:

```bash
mkdir -p backups
chmod 700 backups
```

Create a consistent PostgreSQL dump while the database is running:

```bash
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > backups/arion-database.dump
```

Pause imports, then archive the media volume:

```bash
docker compose stop api worker
docker run --rm \
  --volume arion_media_data:/data:ro \
  --volume "$PWD/backups:/backup" \
  alpine:3.22 tar -czf /backup/arion-media.tar.gz -C /data .
docker compose start api worker
curl --fail http://127.0.0.1:8000/ready
```

Record the application commit/image version with the paired files. Store another encrypted copy away from the server. A backup is not trusted until a restore rehearsal succeeds.

## Restore rehearsal

Restore only into an explicitly selected empty test project or during a planned recovery. Stop the target stack first and confirm the exact target volumes before changing them.

For PostgreSQL, start the empty database, recreate the target database if required, and feed the custom dump to `pg_restore` inside the database container. For media, extract the matching archive into the exact target media volume through a short-lived container. Then run the application migration, start the API, and verify `/ready`, catalog detail, and cover retrieval.

Do not copy a production dump into a development database or empty a named volume based on a wildcard. The exact restore commands depend on whether the target database already exists, so document and review the recovery target before executing them.

## Update and migration order

Before updating, create paired backups and inspect the checkout:

```bash
git status --short
git pull --ff-only
docker compose build
docker compose up --detach db
docker compose run --rm migrate
docker compose up --detach api
docker compose up --detach worker
docker compose up --detach web
docker compose ps --all
curl --fail http://127.0.0.1:8000/health
curl --fail http://<server-lan-ip>:8080/ready
curl --fail http://<server-lan-ip>:8080/
```

The migration job is a gate: do not start the new API if it fails. Imports and catalog edits remain in the named volumes across container restarts.

## Experimental acquisition operations

Keep `ARION_YOUTUBE_ACQUISITION_ENABLED=false` unless you are deliberately testing owner-authorized media. Before enabling it, generate a unique signing secret of at least 32 random bytes, store it only in `.env`, review the duration/output/free-space/time/retry limits in `.env.example`, and recreate both processes:

```bash
docker compose up --detach api worker
docker compose logs --follow api worker
```

The worker uses the API image, database, and media volume, runs unprivileged with one CPU and 768 MiB limits, and processes one job at a time. Search and approval happen in the client. Music search is the default and returns only YouTube Music Songs; use All for unofficial remixes or video-only releases. There is no automatic fallback or result merging between modes. Logs use job IDs and stable failure codes; discovery events add only mode, count, and duration and omit query text and raw provider responses. Never add cookies, arbitrary yt-dlp flags, user-supplied URLs, or public network exposure to work around a provider rejection.

Inspect the toolchain without network access or import:

```bash
docker compose run --rm worker python -m arion_api.acquisition_smoke --inspection-only
```

Only after selecting a small public item you are authorized to acquire, add `--authorized-query "<title>" --discovery-mode music --acknowledge-authorized` to inspect song discovery. Repeat with `--discovery-mode all` when broad results are required. Both modes are inspection-only: they never enqueue or download. If a job fails, inspect `docker compose logs worker`, leave the worker running for bounded automatic retry, and verify the media volume has sufficient free space. Interrupted jobs are reclaimed after their lease expires and staging is cleaned after terminal processing.

To stop acquisition, set the enable flag to `false` and recreate `api` and `worker`; existing catalog media is unaffected. Update the exactly pinned `ytmusicapi` and `yt-dlp` versions only through `backend/pyproject.toml` plus a regenerated `backend/uv.lock`, then rebuild and smoke-test both modes. Roll this client/API contract back with its previously verified paired API and web images; it adds no database migration. Do not remove volumes, expose PostgreSQL, run provider self-updates, or automatically downgrade the schema.

## Rollback

Application rollback and data rollback are different operations:

1. Stop the API while leaving PostgreSQL and volumes intact.
2. Return to a previously verified commit/image only if it is documented as compatible with the current schema.
3. Rebuild/start that API and check both operational endpoints.
4. Do not automatically run `alembic downgrade`, delete volumes, or restore only one half of the backup set.

If a schema/data rollback is genuinely necessary, stop writes and restore the matching PostgreSQL and media backups together. This milestone's initial migration is additive, so leaving the schema in place is normally safer than downgrading it.

The web gateway has no persistent state. To roll it back independently, stop `web` and temporarily bind the preserved API publication to the private LAN address only after reviewing that exposure and updating the saved client URL. Reverting the web service never requires a database downgrade or volume deletion.
