## 1. Production Web Image

- [x] 1.1 Add a client multi-stage Dockerfile and build-context exclusions using builder and unprivileged Nginx base images pinned to reviewed versions and immutable digests; verify a clean `docker build` uses `pubspec.lock`, Flutter 3.44.7, and completes the release web build.
- [x] 1.2 Copy only generated Flutter output and the reviewed server configuration into the runtime stage, run it as a non-root user on an unprivileged port, and verify image inspection finds no Flutter SDK, Dart cache, client source tree, `.env`, or repository metadata.
- [x] 1.3 Add a local container health check for the generated entry point and verify the standalone image becomes healthy and returns the expected Flutter HTML and referenced assets.

## 2. Static and Proxy Behavior

- [x] 2.1 Configure exact proxy handling for `/api/`, `/health`, and `/ready`, including preserved URIs, queries, methods, bodies, range headers, backend statuses, media headers, disabled proxy buffering, and no proxy caching; verify integration requests exercise catalog and operational routes through a test Compose network.
- [x] 2.2 Configure static-file serving so existing files resolve normally, extensionless browser routes fall back to `index.html`, and missing asset-like paths return `404`; verify black-box requests cover `/`, a known asset, an extensionless route, a missing script, and a proxied-path failure that never returns Flutter HTML.
- [x] 2.3 Add revalidation headers for the entry point and non-content-addressed Flutter boot/version files, restrict long-lived caching to content-addressed assets, and verify static, proxied API, media, operational, and gateway-error responses have the intended cache headers.
- [x] 2.4 Exercise a real imported test track through the gateway with complete and ranged audio requests, and verify the response body sizes, `200`/`206` statuses, `Content-Range`, `Content-Length`, `Accept-Ranges`, content type, and seeking behavior match direct FastAPI responses.

## 3. Compose Deployment

- [x] 3.1 Add `ARION_WEB_BIND_ADDRESS` and `ARION_WEB_PORT` with loopback-safe defaults to `.env.example` and Compose, then verify `docker compose config` renders exact loopback defaults and explicit private-LAN overrides without publishing PostgreSQL.
- [x] 3.2 Add the production `web` service with its image/build definition, API health dependency, host binding, container health check, and `unless-stopped` policy while preserving the existing API mapping; verify Compose reports the expected dependency graph, ports, health configuration, and restart policies.
- [x] 3.3 Start the complete stack from a clean disposable environment and verify migration gating, API readiness, web health, client loading, same-origin catalog/cover access, and clean shutdown without deleting the database or media volumes.

## 4. Automation and Operations

- [x] 4.1 Add reusable black-box gateway checks to the repository and verify they fail for incorrect proxy, SPA fallback, cache, health, or range behavior and pass against the production web image.
- [ ] 4.2 Extend GitHub Actions to build the production web image and run the black-box gateway checks alongside existing Flutter validation; verify the workflow syntax and all backend, Flutter, container, and integration jobs pass on a clean run.
- [x] 4.3 Update the README and `.env.example` with image/build commands, loopback defaults, browser first-run configuration using the current gateway origin, Android gateway use, CORS-only development guidance, and private-LAN examples; verify every documented command and URL matches the rendered Compose configuration.
- [x] 4.4 Update the Linux server runbook with trusted-checkout deployment, health and log checks, gateway-first bind settings, update order, smoke tests, and rollback to direct API access; verify the procedure does not require public exposure, TLS, database publication, volume deletion, or a host Flutter SDK.
- [ ] 4.5 Run the complete documented verification suite and a browser playback smoke test through the gateway, recording successful formatting, analysis, Flutter tests, backend tests, image build, Compose validation, static/proxy checks, and ranged seeking before marking the change complete.
