## Context

See `proposal.md` for motivation and `specs/web-client-serving/spec.md` for the behavior contract. The repository already has a pinned Flutter 3.44.7 client, a release web build in CI, and a Compose stack containing PostgreSQL, a migration gate, and FastAPI. Compose currently publishes FastAPI directly but does not package or serve `client/build/web`.

The web client constructs all application URLs from an owner-configured absolute base URL. Keeping the web page and API on one gateway origin therefore works without changing the client configuration model: on first use, the owner enters the URL already open in the browser, and Android may use that same URL. Development servers and separately hosted clients can continue to use the existing explicit CORS allow-list.

## Goals / Non-Goals

**Goals:**

- Produce one deterministic web image from the pinned Flutter SDK and committed Dart lockfile.
- Serve static files and stream proxied API responses from an unprivileged, low-overhead container.
- Give private browser and Android clients one recommended LAN origin while preserving direct loopback API access for development and compatibility.
- Make SPA fallback, cache policy, range streaming, and service health explicit and testable.
- Keep deployment suitable for rootless Docker Compose on the existing server.

**Non-Goals:**

- Automatic API URL discovery or a change to saved client settings precedence.
- TLS certificate management, DNS, public ingress, router changes, or Tailscale setup.
- Offline/PWA guarantees, service-worker-managed media, or a general-purpose content delivery network.
- API authentication, rate limiting, transcoding, or response caching.
- Publishing images to GHCR or automating server deployment.

## Decisions

### Build Flutter in a multi-stage image and run an unprivileged Nginx image

Add a production Dockerfile for the client. Its builder stage uses a Flutter image pinned to the same SDK version as `.flutter-version`, installs dependencies with the committed lockfile, and creates the release web output. A separately pinned, unprivileged Nginx stage receives only that output and the reviewed server configuration. Base images should be pinned to immutable digests when implemented, with human-readable version comments for maintainability.

This makes the deployable artifact independent of a host Flutter installation, keeps the runtime small, and exercises the same release build in CI and deployment. Nginx is selected over Caddy because this increment needs only static files, deterministic route matching, and an internal HTTP proxy; automatic TLS is intentionally out of scope. Serving files from FastAPI was rejected because it would couple frontend releases and static-server policy to the backend image and Python process.

### Use the gateway origin as the recommended API base URL

Nginx listens on an unprivileged container port and routes `/api/`, plus exact `/health` and `/ready` paths, to `http://api:8000` through Compose DNS. It preserves the original URI and query, forwards request bodies and range headers, and passes backend statuses and media headers. Proxy buffering is disabled for application routes so ranged or full audio responses remain bounded streams rather than being staged in the gateway. Proxy caching is not configured.

The Flutter app remains explicit about server selection. On first browser use, documentation tells the owner to enter the current page origin; the saved value then works for catalog, cover, and audio URLs. This avoids build-time LAN addresses, runtime rewriting of compiled JavaScript, and new platform-specific configuration behavior. Development use through `flutter run` retains `ARION_CORS_ORIGINS` and the optional Dart define.

Alternative considered: inject a runtime JSON configuration file and teach the client to load it. That removes one first-run field entry but adds a client boot dependency, precedence rules, tests, and failure states for little value in a single-user application.

### Preserve the direct API publication but make the gateway the documented LAN endpoint

Compose adds `web` with `ARION_WEB_BIND_ADDRESS` and `ARION_WEB_PORT`, both defaulting to loopback-safe values. The existing `api` host mapping remains and keeps its loopback default. The server runbook recommends binding `web` to the fixed LAN address while leaving `api` on loopback, producing one LAN entry point without breaking direct backend development or existing explicit configurations. PostgreSQL remains unpublished.

Alternative considered: remove the API host mapping entirely. It would create a cleaner production topology but would be a breaking change for current development commands and saved Android URLs. A later security-focused change can remove it after a deliberate migration.

### Separate proxied, asset-like, and browser-route locations

Nginx gives proxied routes precedence so they can never fall through to static handling. Existing files are served directly. Asset-like paths, including common script, style, image, font, manifest, and source-map extensions and generated asset directories, use an exact-file check ending in `404`. Only remaining `GET` or `HEAD` requests fall back to `index.html`, which supports future browser routing without disguising missing files as successful HTML.

Entry HTML and non-content-addressed Flutter bootstrap/version files use revalidation-oriented cache headers. Long-lived immutable caching is limited to files whose names identify their content; all other static files use short or revalidating policies. API and operational responses bypass static cache policy. This favors reliable upgrades on a private server over maximum caching.

Alternative considered: one `try_files $uri /index.html` location. It is shorter but returns successful HTML for missing JavaScript or image requests, making deployments harder to diagnose and potentially caching the wrong content type.

### Keep gateway health distinct from backend readiness

The web container health check requests its local `index.html`, proving Nginx and the packaged artifact work without depending on host networking or the public Internet. Compose starts `web` only after the API health check passes. Backend liveness and dependency readiness remain observable through the gateway's exact `/health` and `/ready` proxies.

This separates a broken static server from an unavailable backend while preserving the existing readiness contract. Marking the web container unhealthy whenever the API has a transient outage was rejected because it would conflate services and could cause unnecessary restarts; API failures remain visible through `/ready` and gateway status responses.

### Verify the image as a black box in CI

CI continues Flutter formatting, analysis, tests, and release compilation, then builds the production web image. Container checks request the entry point and known assets, validate cache and content-type headers, verify extensionless fallback and asset `404`, exercise catalog/readiness proxying, and send a ranged audio request through the gateway. Compose configuration is rendered with test values to confirm exact host bindings, dependency conditions, and the absence of a database port.

Tests should assert behavior rather than Nginx file layout so the serving implementation can be replaced later without rewriting the capability contract.

## Risks / Trade-offs

- [A stale browser cache can keep an old Flutter bootstrap] → Revalidate entry and non-content-addressed boot files, avoid promising offline behavior, and test an image replacement with unchanged origin.
- [Proxy buffering or header changes can break seeking] → Disable application-response buffering and test `Range` requests plus `206` headers through the real gateway.
- [A broad SPA fallback can hide packaging errors] → Give proxy and asset-like locations precedence and require missing assets to return `404`.
- [Two configurable host publications can be misconfigured onto the LAN] → Default both to loopback and document only the web binding for normal server use; do not use `0.0.0.0` by default.
- [Pinned image digests require deliberate upgrades] → Record readable upstream versions beside digests and update them through reviewed dependency maintenance.
- [The owner must enter the visible gateway origin once] → Document the exact value and preserve it through the existing settings store; revisit runtime discovery only if this becomes a recurring usability problem.

## Migration Plan

1. Add the pinned multi-stage client image, Nginx configuration, and black-box container tests without changing the running Compose topology.
2. Add the `web` service, loopback-safe environment defaults, API dependency, health check, and restart policy; validate the rendered Compose model.
3. Start the updated stack on loopback, configure the browser client with the gateway origin, and verify static loading, catalog access, readiness, cover retrieval, playback, and seeking.
4. On the private server, set `ARION_WEB_BIND_ADDRESS` to the fixed LAN IP, leave `ARION_BIND_ADDRESS` on loopback unless direct API access is intentionally retained, and repeat the smoke tests from a trusted PC and Android device.
5. Update CI and the operational documentation, then deploy through the existing manual trusted-checkout workflow.

Rollback stops and removes the `web` service or returns to the prior Compose file and image. No database migration or persistent-volume change is involved. The API can immediately resume serving clients through its preserved host binding, and browser users may use the prior development/static-hosting method.
