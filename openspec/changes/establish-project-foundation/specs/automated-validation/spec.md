## Purpose

Defines the repeatable automated checks that protect the initial backend foundation and prove that its application and container remain buildable.

## ADDED Requirements

### Requirement: Automated backend tests
The repository SHALL provide an automated test suite that runs without external services and verifies both application creation and the complete `GET /health` response contract.

#### Scenario: Run tests from a clean environment
- **WHEN** a developer installs the locked development dependencies and runs the documented test command
- **THEN** the tests execute without a database, network service, or music file and report success for a conforming foundation

#### Scenario: Detect a health contract regression
- **WHEN** the health endpoint no longer returns the specified status, content type, or JSON body
- **THEN** the automated test suite fails

### Requirement: Continuous integration checks
The repository SHALL define a GitHub Actions workflow that runs for pull requests and pushes to the primary branch, installs locked dependencies, executes the test suite, and builds the backend container image without publishing or deploying it.

#### Scenario: Validate a conforming change
- **WHEN** a pull request or primary-branch push contains passing tests and a buildable container definition
- **THEN** the continuous integration workflow completes successfully

#### Scenario: Reject an invalid change
- **WHEN** the test suite fails or the backend container cannot be built
- **THEN** the continuous integration workflow fails visibly at the corresponding check

### Requirement: Least-privilege CI
The initial continuous integration workflow SHALL use read-only repository permissions and SHALL NOT require deployment credentials, registry credentials, or access to the private server.

#### Scenario: Run CI without project secrets
- **WHEN** the workflow runs for a pull request from a repository checkout
- **THEN** all foundation checks complete without reading project or deployment secrets
