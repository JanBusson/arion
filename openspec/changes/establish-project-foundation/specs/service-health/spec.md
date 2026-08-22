## Purpose

Defines a minimal observable backend service contract that confirms the Arion API process is running before product capabilities and external dependencies are introduced.

## ADDED Requirements

### Requirement: Standalone backend startup
The backend service SHALL start with documented default development configuration and SHALL NOT require a database, audio storage, frontend, authentication provider, or any other external service during this milestone.

#### Scenario: Start the foundation service
- **WHEN** a developer starts the backend using the documented local command
- **THEN** the API process starts successfully without connecting to an external service

### Requirement: Health endpoint
The backend SHALL expose an unauthenticated `GET /health` endpoint that returns HTTP status `200`, a JSON content type, and the response body `{"status":"ok"}` while the process is healthy.

#### Scenario: Check service health
- **WHEN** a client sends `GET /health` to a running backend
- **THEN** the response has status `200` and JSON body `{"status":"ok"}`
