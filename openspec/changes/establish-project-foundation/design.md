## Context

See `proposal.md` for motivation. The repository currently contains only project guidance and OpenSpec configuration, so this milestone can establish conventions without migrating application code or data. The foundation must work for a Windows development checkout and a small Ubuntu Server host, while remaining simple enough for a single-user learning project.

The behavioral contracts are defined by the `service-health`, `containerized-operation`, and `automated-validation` delta specs. The planned product architecture is directional: this design establishes only the backend and operational seams needed now.

## Goals / Non-Goals

**Goals:**

- Make one backend service runnable directly and through Docker Compose from a clean checkout.
- Establish a Python layout that can grow into a modular monolith without adding premature application layers.
- Keep dependency installation, tests, container builds, and documentation reproducible across local and CI environments.
- Make configuration explicit, validated where it enters the application, and safe to commit by separating examples from local values.
- Provide an initial private-server run path that does not pretend image publishing or automated deployment already exists.

**Non-Goals:**

- Establish domain modules, database models, migrations, storage interfaces, background workers, or frontend structure before those capabilities exist.
- Add a reverse proxy, TLS, public exposure, Tailscale configuration, registry publication, or self-hosted-runner deployment.
- Add custom logging infrastructure, metrics, tracing, linting gates, release automation, or a generic application framework beyond what the foundation needs.
- Guarantee production hardening; this milestone produces a private, observable starting point rather than a complete production platform.

## Decisions

### 1. Use a backend-focused repository layout with a Python `src` package

The initial tree will be organized as follows:

```text
.
├── .github/workflows/ci.yml
├── backend/
│   ├── src/arion_api/
│   │   ├── __init__.py
│   │   ├── config.py
│   │   └── main.py
│   ├── tests/test_health.py
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── pyproject.toml
│   └── uv.lock
├── docs/server.md
├── .env.example
├── .gitignore
├── compose.yaml
└── README.md
```

`arion_api.main` will expose both a small `create_app()` factory and the module-level ASGI `app`. This supports isolated tests and conventional ASGI startup without inventing domain, repository, or service layers that have no behavior yet. Future product capabilities can add packages beneath `arion_api` while remaining in one deployable backend.

Alternatives considered:

- A flat `main.py` at repository root is initially shorter, but it creates an awkward migration as tests and domain modules grow.
- A full monorepo skeleton with empty `frontend`, `infrastructure`, and domain directories signals decisions that the project has intentionally deferred.

### 2. Use Python 3.13, `pyproject.toml`, and `uv` with a committed lockfile

Python 3.13 will be the single declared runtime for local development, CI, and the container. Runtime and development dependencies will be declared once in `backend/pyproject.toml`; `uv.lock` will be committed and frozen installs will be used in CI and container builds. The minimal dependency set will be FastAPI, an ASGI server, Pydantic Settings, pytest, and the HTTP test client dependency required by FastAPI's test utilities. Tool versions and the project version will be explicit.

This gives the project lockfile-based, cross-platform dependency management that is common in modern Python and Data/AI work without introducing a separate packaging service.

Alternatives considered:

- `pip` plus hand-maintained `requirements.txt` and `requirements-dev.txt` is familiar, but duplicates dependency declarations or requires an additional lock-generation tool.
- Poetry provides similar guarantees but adds a larger project-management abstraction than this foundation needs.
- Selecting the newest interpreter available on each machine would reduce pinning work, but makes local, CI, and image behavior less reproducible.

### 3. Keep configuration small and separate application settings from host exposure

Application settings will use Pydantic Settings with the `ARION_` prefix. The initial validated values will be an environment label and log level with non-secret development defaults. Compose-facing values will control the host bind address and published port. `.env.example` will document all supported values; `.env` and variant local environment files will be ignored while the example remains tracked.

The container will listen on a fixed internal address and port. Compose will default its published address to `127.0.0.1` and allow the owner to opt into a private LAN address through local environment configuration. Keeping host exposure outside the application prevents deployment topology from leaking into API code and avoids public exposure by default.

Invalid application values will be rejected during startup by typed settings validation. Invalid Compose bind or port values will fail during Compose configuration or startup with the responsible variable documented.

Alternatives considered:

- Hard-coding configuration is simpler for one endpoint but establishes an unsafe precedent before deployment begins.
- Committing a development `.env` would be convenient now but conflicts with the repository's secret-handling rule and makes later mistakes more likely.
- Binding Compose to all interfaces by default is convenient on the server but unnecessarily exposes the service on developer machines.

### 4. Keep `/health` operational and outside future versioned product APIs

`GET /health` will return only `{"status":"ok"}` and will perform no external dependency checks. It represents process liveness for the foundation and is suitable for the container health check. Future product endpoints can live below a versioned `/api/v1` prefix, while readiness checks can be added separately when the backend acquires required dependencies.

Alternatives considered:

- Placing health under `/api/v1` would tie an operational contract to product API versioning.
- Adding build metadata, timestamps, or dependency status creates unstable output and requirements that are not useful before those dependencies exist.

### 5. Build one non-root backend image and one-service Compose application

The Dockerfile will use a slim Python base, install the locked runtime environment in a build stage, and copy only runtime artifacts into the final stage. The final process will run as an unprivileged user. The image health check will call `/health` using Python's standard library, avoiding an extra operating-system package solely for health checks.

`compose.yaml` will contain only the backend service, build it from the checked-in Dockerfile, apply the documented environment, publish the configurable host endpoint, and wait for the image-defined health check. No database, volume, proxy, or worker placeholder will be added.

Alternatives considered:

- Running directly from a bind-mounted source tree inside Compose improves hot reload, but makes the deployment definition development-specific. Direct local execution already provides a fast edit/test loop; Compose will model the deployable runtime.
- Separate development and production Compose files add maintenance overhead before their behavior actually differs.

### 6. Test through the ASGI application and keep CI stateless

Pytest will instantiate the application and use FastAPI's in-process test client. Tests will cover application creation and assert the exact health status code, content type, and JSON body. They will not require listening sockets, a database, music fixtures, or network access.

GitHub Actions will use hosted runners, read-only repository permissions, a locked dependency install, and two clear checks: backend tests and a Docker build with publication disabled. It will run on pull requests and pushes to both `main` and the repository's current `master` branch; `master` can be removed from the trigger after the default branch is intentionally renamed. No secrets or self-hosted runner will be used.

Alternatives considered:

- Running CI only on `main` would miss the repository's current branch name.
- Publishing every successful image to GHCR would get closer to the target CI/CD flow, but requires image naming, permissions, tagging, and server rollout decisions that deserve a later milestone.
- Using a self-hosted runner for all jobs would risk exposing the home server to untrusted pull-request code.

### 7. Document a source-built server procedure as an explicit interim deployment

`README.md` will be the entry point for prerequisites and local commands. `docs/server.md` will cover installing Docker on the private Ubuntu host, cloning or updating the repository, creating local environment configuration, building and starting Compose, checking health and logs, stopping the service, and updating by pulling trusted source then rebuilding.

Because CI does not publish images in this milestone, the server will build the image from the checked-out source. The documentation will label this as temporary; a later change can switch Compose to versioned GHCR images and add a controlled deployment job.

Alternatives considered:

- Manually transferring locally built images adds an error-prone step without improving the learning goal.
- Adding GHCR and deployment now would broaden this milestone from foundation validation into release and credentials management.

## Risks / Trade-offs

- [Python 3.13 is not the distribution's default interpreter] → Direct development uses `uv`, and Docker supplies the pinned interpreter, so the host does not need to replace its system Python.
- [A source-built server update is slower and less immutable than pulling a versioned image] → Document it as an interim workflow and defer registry-backed releases to a dedicated CI/CD change.
- [Loopback exposure can surprise an operator expecting LAN access] → Make the private-network bind override prominent in `.env.example` and the server runbook, while retaining the safer default.
- [A liveness-only health response will not detect future dependency failures] → Keep its semantics explicit and add a distinct readiness endpoint when required dependencies are introduced.
- [Using major-version GitHub Actions tags is less tamper-resistant than commit-SHA pinning] → Use trusted first-party or widely adopted official actions with minimal permissions now; evaluate SHA pinning together with dependency-update automation in a later CI hardening change.
- [The initial package layout may evolve as real domain behavior appears] → Keep only the app factory and settings module now, and let later OpenSpec changes introduce structure based on actual boundaries.

## Migration Plan

There is no existing application or persistent data to migrate.

1. Add the backend package, dependency lock, tests, and configuration example.
2. Add and locally verify the Docker image and Compose service.
3. Add CI and verify both test and image-build jobs in GitHub Actions.
4. Add the local and server documentation, then validate every documented command from a clean checkout where practical.
5. On the private server, clone the repository, create the untracked local environment file, and start the Compose service with a source build.

Rollback is code-only: stop the Compose service and return to the previous repository revision. No database, volume, or user data is created by this milestone.

## Open Questions

- The eventual reverse proxy choice remains Caddy versus Nginx; it does not affect this direct private-network foundation.
- The eventual GHCR image name and version-tagging convention can be decided when image publication is proposed.
