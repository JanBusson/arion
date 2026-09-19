## Why

Arion currently has architectural direction but no runnable project baseline. Establishing a small, reproducible foundation now makes later backend and data-pipeline work easier to test, containerize, deploy, and evolve without prematurely implementing product features.

## What Changes

- Establish a clear repository layout centered on a modular FastAPI backend, with dedicated locations for tests, container configuration, CI workflows, and documentation.
- Add an initial FastAPI application with a minimal health endpoint suitable for developer checks and container health monitoring.
- Define environment-based configuration with safe defaults, ignored local secrets, and a committed placeholder example.
- Define a Docker image and Docker Compose workflow that can run the same backend foundation locally and on the private Linux server.
- Add a basic automated test setup for the application and health endpoint.
- Add an initial GitHub Actions workflow that runs tests and verifies the container image can be built, without publishing or deploying it yet.
- Document local setup, container usage, configuration, testing, and the initial server run procedure.
- Explicitly defer music streaming, Flutter clients, PostgreSQL, metadata extraction, authentication, reverse proxy selection, registry publishing, and automated deployment.

## Capabilities

### New Capabilities

- `service-health`: Defines the runnable backend service and its minimal health-check behavior.
- `containerized-operation`: Defines environment-driven configuration and reproducible Docker Compose operation for development and the private Linux server.
- `automated-validation`: Defines the automated test and CI checks required for the foundation.

### Modified Capabilities

None.

## Impact

- Introduces the initial backend source tree, Python dependency metadata and lock data, tests, Docker assets, Compose configuration, GitHub Actions workflow, environment example, ignore rules, and operator/developer documentation.
- Establishes FastAPI and its ASGI server as runtime dependencies, plus focused configuration and test dependencies.
- Creates one stateless backend container only; no database, persistent audio storage, frontend, reverse proxy, registry publication, or deployment automation is introduced in this milestone.
- Provides the baseline contracts that later milestones can extend with versioned APIs, storage abstractions, observability, and product behavior.
