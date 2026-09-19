## Why

The Flutter web client can be built, but the Docker Compose deployment does not serve it, so a browser user still needs a development server or a manually copied build. Arion needs a reproducible private-LAN web entry point that packages the client with the rest of the self-hosted stack.

## What Changes

- Add a production web image that builds the pinned Flutter client and serves only the generated static assets from a small Nginx runtime.
- Make the web service the private-LAN entry point and proxy `/api/` requests to FastAPI on the Compose network, allowing the configured client base URL to use the same origin as the page.
- Support Flutter single-page navigation fallback without turning missing asset requests into the application shell.
- Add web-service liveness/readiness behavior, dependency ordering, restart policy, and a configurable private host binding in Docker Compose.
- Preserve the FastAPI service's existing configurable host binding for compatibility while recommending the web gateway's origin as the single private-LAN address for browser and Android clients.
- Add automated checks for the production image, proxy behavior, static caching rules, SPA fallback, and Compose configuration.
- Document local image builds, private-server startup, first-run client configuration, verification, logging, updates, and rollback.
- Keep TLS, domains, public port forwarding, Tailscale, authentication, GHCR publishing, and automated deployment outside this change.

## Capabilities

### New Capabilities

- `web-client-serving`: Covers reproducible Flutter web packaging, private same-origin delivery and API proxying, browser-route fallback, operational health, and safe cache behavior.

### Modified Capabilities

- None.

## Impact

- Adds a client production Dockerfile, Nginx configuration, and container-level verification assets.
- Extends `compose.yaml` and `.env.example` with a web gateway and private bind/port settings; the existing loopback-default API publication remains available for development and compatibility.
- Extends CI to build and exercise the deployable web image in addition to the existing Flutter release build.
- Updates the README and Linux server runbook so browser and Android clients use the gateway origin while PostgreSQL and FastAPI remain internal Compose services.
- Introduces Nginx as the selected static server and private reverse proxy; it does not change API contracts, persistent data, or the backend storage model.
