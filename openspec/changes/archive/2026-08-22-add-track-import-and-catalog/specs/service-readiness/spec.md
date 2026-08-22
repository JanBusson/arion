## Purpose

Defines separate liveness and readiness contracts so operators can distinguish a running API process from one that can safely serve catalog and import requests using its required dependencies.

## ADDED Requirements

### Requirement: Preserve process liveness
The existing unauthenticated `GET /health` endpoint SHALL retain status `200` and body `{"status":"ok"}` while the API process is running, regardless of temporary database or storage availability.

#### Scenario: Dependency outage does not change liveness
- **WHEN** the API process is running but PostgreSQL or media storage is unavailable
- **THEN** `GET /health` still returns status `200` and body `{"status":"ok"}`

### Requirement: Dependency readiness endpoint
The system SHALL expose unauthenticated `GET /ready`. It SHALL verify that the expected migrated catalog schema is queryable and that the configured media staging and durable storage locations are accessible to the API process.

#### Scenario: All dependencies are ready
- **WHEN** the migrated database and required storage locations are available
- **THEN** `GET /ready` returns status `200` and body `{"status":"ready"}`

#### Scenario: A dependency is unavailable
- **WHEN** the database schema or any required storage location is unavailable
- **THEN** `GET /ready` returns status `503` with `status` set to `not_ready` and a dependency map containing only readiness states

### Requirement: Safe readiness diagnostics
Readiness responses SHALL identify the `database` and `storage` dependency states without returning credentials, connection strings, filesystem paths, exception traces, or other sensitive configuration.

#### Scenario: Report a database failure safely
- **WHEN** the readiness database check fails
- **THEN** the response marks `database` as unavailable without revealing its connection details or underlying exception text
