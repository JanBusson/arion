## Purpose

Defines how the foundation is configured and run reproducibly in containers for local development and private operation on the project owner's Linux server.

## ADDED Requirements

### Requirement: Environment-based configuration
The backend and Compose workflow SHALL obtain deployment-specific settings from documented environment variables, SHALL provide non-secret defaults sufficient for local startup, and SHALL fail with a clear configuration error when a supplied value is invalid.

#### Scenario: Start with default configuration
- **WHEN** a developer starts the documented local workflow without creating a secrets file
- **THEN** the backend starts with the documented non-secret development defaults

#### Scenario: Reject invalid configuration
- **WHEN** an operator supplies an invalid value for a validated environment setting
- **THEN** startup fails and identifies the invalid setting

### Requirement: Secret-safe environment files
The repository SHALL include a placeholder environment example containing no real credentials, SHALL exclude local `.env` files from version control, and SHALL document that secrets remain outside the repository.

#### Scenario: Prepare local configuration
- **WHEN** a developer follows the documented environment setup
- **THEN** they can create a local configuration file from the committed example without modifying a tracked secrets file

### Requirement: Reproducible backend image
The repository SHALL define a version-controlled backend image build with locked Python dependencies, a non-root runtime user, and a container health check based on the service health endpoint.

#### Scenario: Build the backend image
- **WHEN** an operator builds the image from a clean repository checkout using the documented command
- **THEN** the build installs the locked dependencies and produces a runnable backend image

#### Scenario: Observe container health
- **WHEN** the container is running and `GET /health` returns the healthy response
- **THEN** the container runtime reports the container as healthy

### Requirement: Compose operation
The repository SHALL provide a Docker Compose definition for the single backend service, expose the API through a configurable host address and port, and default host exposure to loopback so that the service is not publicly exposed by default.

#### Scenario: Run locally with Compose
- **WHEN** a developer starts the documented Compose workflow with default settings
- **THEN** the backend becomes healthy and is reachable from the host through the documented loopback URL

#### Scenario: Run on the private Linux server
- **WHEN** the owner configures the documented private-network bind address and starts the Compose workflow on the supported Linux server
- **THEN** the backend becomes healthy and is reachable through the configured private-network address

### Requirement: Operational documentation
The repository SHALL document prerequisites and exact commands for local installation, local execution, testing, image building, Compose operation, configuration, health verification, logs, shutdown, and the initial Linux server run procedure.

#### Scenario: Follow a documented runbook
- **WHEN** a developer or server operator starts from a clean checkout with the documented prerequisites
- **THEN** they can start the backend and verify its health using only the repository documentation and placeholder configuration
