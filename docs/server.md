# Private Linux server runbook

This runbook deploys Arion through rootless Docker Compose on a private Linux server. It does not configure public access, router port forwarding, TLS, a reverse proxy, Tailscale, or automatic deployment.

## Prerequisites and security boundary

- Use only the dedicated non-root deployment user.
- Docker Engine and Compose v2 must already work for that user.
- Use a trusted checkout and private LAN address.
- Never use `sudo` for these application procedures.
- Never run untrusted pull-request code on this server.

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

Edit `.env` with a unique database password, using its URL-encoded value in `ARION_DATABASE_URL`, and bind only to the fixed private address:

```dotenv
ARION_ENVIRONMENT=production
ARION_LOG_LEVEL=INFO
POSTGRES_DB=arion
POSTGRES_USER=arion
POSTGRES_PASSWORD=<strong-private-password>
ARION_DATABASE_URL=postgresql+psycopg://arion:<url-encoded-password>@db:5432/arion
ARION_BIND_ADDRESS=<server-lan-ip>
ARION_PORT=8000
```

Keep the default `/var/lib/arion/media` container path. Compose stores PostgreSQL and media in rootless-Docker named volumes, avoiding fragile host UID mappings.

Resolve and inspect configuration before starting:

```bash
docker compose config --quiet
docker compose config
```

Confirm that the API publishes only the intended private address, PostgreSQL has no published host port, and no real credential appears in a checked-in file. Do not use `0.0.0.0` or configure router forwarding unless public exposure is designed in a later security change.

## First deployment

Build, start PostgreSQL, run the one-shot migration, and start the API:

```bash
docker compose up --detach --build
docker compose ps --all
```

The expected states are:

- `db`: running and healthy
- `migrate`: exited successfully with status 0
- `api`: running and healthy

Check both operational endpoints from the server:

```bash
curl --fail http://<server-lan-ip>:8000/health
curl --fail http://<server-lan-ip>:8000/ready
```

From a trusted PC on the same LAN, open `http://<server-lan-ip>:8000/health`, `http://<server-lan-ip>:8000/ready`, or `http://<server-lan-ip>:8000/docs`. If access fails, inspect the configured bind address and existing host-network policy; do not weaken server or router security as an ad hoc fix.

## Logs and readiness diagnosis

```bash
docker compose logs --follow api
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
docker compose stop api
docker run --rm \
  --volume arion_media_data:/data:ro \
  --volume "$PWD/backups:/backup" \
  alpine:3.22 tar -czf /backup/arion-media.tar.gz -C /data .
docker compose start api
curl --fail http://<server-lan-ip>:8000/ready
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
docker compose ps --all
curl --fail http://<server-lan-ip>:8000/health
curl --fail http://<server-lan-ip>:8000/ready
```

The migration job is a gate: do not start the new API if it fails. Imports and catalog edits remain in the named volumes across container restarts.

## Rollback

Application rollback and data rollback are different operations:

1. Stop the API while leaving PostgreSQL and volumes intact.
2. Return to a previously verified commit/image only if it is documented as compatible with the current schema.
3. Rebuild/start that API and check both operational endpoints.
4. Do not automatically run `alembic downgrade`, delete volumes, or restore only one half of the backup set.

If a schema/data rollback is genuinely necessary, stop writes and restore the matching PostgreSQL and media backups together. This milestone's initial migration is additive, so leaving the schema in place is normally safer than downgrading it.
