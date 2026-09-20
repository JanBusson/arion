## Purpose

Defines how Arion packages and serves its Flutter browser client as a private, reproducible web entry point with same-origin access to the existing API and audio streams.

## ADDED Requirements

### Requirement: Reproducible production web artifact
The system SHALL build the committed Flutter client into a version-pinned production container that contains the release web output and the minimum runtime needed to serve it. The runtime image SHALL NOT contain repository secrets, the Flutter SDK, Dart build caches, or client source files that are not part of the generated web output.

#### Scenario: Build the deployable web image
- **WHEN** an operator builds the web image from a clean checkout using the documented container command
- **THEN** dependency resolution uses the committed lockfile and pinned toolchain, the Flutter release build completes, and the resulting image can serve the generated application without a host-installed Flutter SDK

#### Scenario: Inspect the runtime image
- **WHEN** the completed web image is inspected
- **THEN** it contains the generated static application and serving runtime but excludes build-only toolchains, caches, source configuration files, and deployment secrets

### Requirement: Private configurable web binding
The Compose deployment SHALL publish the web gateway on an operator-configurable host address and port, SHALL default the address to loopback, and SHALL NOT publish it on all interfaces implicitly. The existing API publication SHALL retain its loopback default for development and compatibility.

#### Scenario: Start with default bindings
- **WHEN** the operator starts the stack without web or API bind overrides
- **THEN** both published endpoints are bound to loopback and are not reachable through every host interface

#### Scenario: Enable private-LAN access explicitly
- **WHEN** the operator sets the web bind address to the server's fixed private-LAN address and starts the stack
- **THEN** the browser client and proxied server routes are reachable through the configured web port on that address without publishing PostgreSQL

### Requirement: Same-origin API and media gateway
The web gateway SHALL forward requests under `/api/` to the FastAPI service without changing the path, query, method, request body, or application response semantics. It SHALL also forward the exact `/health` and `/ready` operational routes. Proxy failures SHALL return an HTTP gateway error and SHALL NOT return the Flutter application shell.

#### Scenario: Request catalog data from the served client origin
- **WHEN** a client configured with the web gateway origin requests an `/api/` route
- **THEN** the gateway forwards the request over the private Compose network and returns the backend status, body, content type, and relevant response headers on the same origin

#### Scenario: Seek through the gateway
- **WHEN** a client sends a valid `Range` request to a track audio route through the gateway
- **THEN** the backend receives the range request and the client receives the corresponding `206` response, bounded audio body, `Content-Range`, `Content-Length`, and `Accept-Ranges` headers without the gateway first buffering the complete track

#### Scenario: Check backend readiness through the gateway
- **WHEN** an operator requests `/health` or `/ready` from the published web origin
- **THEN** the gateway returns the corresponding FastAPI operational response and status without substituting a static page

#### Scenario: Backend is unavailable
- **WHEN** the gateway cannot reach FastAPI for a proxied route
- **THEN** it returns a non-successful gateway response and does not expose an internal container address, serve cached API data, or fall back to `index.html`

### Requirement: Static application and browser-route handling
The web gateway SHALL serve the generated application entry point and existing static assets for `GET` and `HEAD` requests. It SHALL return the application entry point for an otherwise unknown extensionless browser route, while a request that identifies a missing asset SHALL return `404` rather than the application entry point.

#### Scenario: Open the browser application
- **WHEN** a browser requests `/` from the published web origin
- **THEN** it receives the generated Flutter entry document and can load the referenced scripts, manifest, icons, and assets from that origin

#### Scenario: Refresh a client-side route
- **WHEN** a browser directly requests an extensionless route that is not a real file or proxied server route
- **THEN** the gateway returns the application entry point so the browser application can handle the route

#### Scenario: Request a missing static asset
- **WHEN** a browser requests a nonexistent script, stylesheet, image, font, manifest, or other asset-like path
- **THEN** the gateway returns `404` and does not return HTML with a successful status

### Requirement: Update-safe static caching
The gateway SHALL require browsers to revalidate the application entry point and non-content-addressed boot or version metadata so a restarted deployment can advertise a new client build. It MAY give content-addressed assets a longer cache lifetime, but it SHALL NOT apply persistent caching to API, media, health, readiness, or gateway-error responses.

#### Scenario: Deploy a newer client build
- **WHEN** the web container is replaced with a newer release and a browser revisits the application
- **THEN** cache rules allow the browser to discover the new entry point and boot metadata without requiring the owner to clear site data manually

#### Scenario: Receive a proxied response
- **WHEN** a client receives catalog, media, operational, or proxy-error data through the gateway
- **THEN** the gateway does not mark that response as a persistently cacheable static asset

### Requirement: Observable web-service operation
The Compose web service SHALL declare a container health check that proves its local serving process can return the application entry point, start only after the API has passed its startup dependency gate, and use a restart policy suitable for the private long-running server.

#### Scenario: Start the complete stack
- **WHEN** database readiness, migration, API readiness, and web startup all succeed
- **THEN** Compose reports the database, API, and web services healthy and the published origin serves both the client entry point and proxied readiness route

#### Scenario: Static serving process fails
- **WHEN** the web process cannot return its local application entry point
- **THEN** the web container health check fails so the operator can distinguish a broken gateway from a client-side rendering problem
