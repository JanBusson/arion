## Context

See `proposal.md` for motivation. The repository currently contains a FastAPI catalog with list/search, cover, and standards-compatible ranged-audio endpoints, but no client project or browser-origin policy. The intended clients are an Android APK and a browser app on a private LAN, initially without authentication. Flutter and Dart are not currently installed on the development workstation.

The client must tolerate API and media failures without losing navigation state, and its logic needs deterministic tests even though the real audio engine and browser networking are platform integrations.

## Goals / Non-Goals

**Goals:**

- Keep Android and web behavior in one small, idiomatic Flutter package.
- Separate API, persistence, playback, state, and widgets enough to test each boundary with fakes.
- Make private-server configuration explicit and avoid source-code environment values.
- Preserve bounded server streaming and native/browser range-seeking behavior by giving the player the audio URL rather than downloading audio into Dart memory.
- Provide a responsive Material interface with accessible labels and predictable loading/error states.

**Non-Goals:**

- Background playback, lock-screen controls, queues, shuffle, repeat, or platform media notifications.
- Offline caching, downloads, client-side transcoding, or waveform generation.
- Deep links, browser URL routing, multiple servers, accounts, or secret storage.
- Importing files, editing metadata, or managing playlists from this client increment.
- Packaging the web build into the backend container or selecting the production reverse proxy.

## Decisions

### Create a feature-oriented Flutter package under `client/`

Generate only the Android and web targets and organize Dart code around configuration, library, and player features, with shared API models and reusable widgets. Keep `main.dart` as a composition root that creates concrete adapters and injects them into controllers.

Alternative considered: separate Android and web applications. That would duplicate the API model and most user-interface behavior before either platform has divergent requirements.

### Use small observable controllers and constructor injection

Use Flutter's built-in `ChangeNotifier` and `ListenableBuilder` for the library, settings, and player state. Define narrow interfaces for the API, settings store, and audio player, then pass implementations through constructors. This is sufficient for the first few screens and permits unit/widget tests with fakes.

Alternative considered: Riverpod or Bloc. Both are capable, but they add concepts and dependencies without solving a current state-management problem. Revisit if navigation and feature count make manual composition unwieldy.

### Use the standard HTTP client behind an Arion API adapter

Use one injected `package:http` client for JSON requests, close it at application disposal, validate response status and shape, and map failures to client-safe error types. Build all request URIs through one normalized base-URL value. Cover URLs remain lazy image URLs; audio URLs go directly to the player.

Alternative considered: generated OpenAPI bindings or Dio. The API surface is currently four simple read endpoints, so generated code and interceptor infrastructure would be disproportionate.

### Persist only the normalized API base URL

Use the asynchronous shared-preferences API to store one non-secret URL. An optional `ARION_API_BASE_URL` Dart definition may seed a development or CI build, but a saved owner value takes precedence. Validate that the URI is absolute, uses HTTP or HTTPS, contains a host, and has no query or fragment; normalize trailing slashes.

The base URL is configuration, not a credential. Authentication tokens must use an appropriate secure-storage design if authentication is added later.

Alternative considered: compile-time-only configuration. That makes every server-address change require rebuilding the APK and is awkward for a learning/home-network deployment.

### Give ranged audio URLs to `just_audio`

Wrap one `just_audio` player in a narrow adapter exposing source selection, play/pause/seek, processing state, position, duration, and errors. The plugin supports Android and web URL playback and seeking, and expects correct content type, length, and byte-range server headers—behavior the backend now provides. Do not fetch or buffer the whole object through `package:http`.

Use the catalog's `duration_ms` as an initial display bound and prefer a valid player-reported duration when available. Clamp seek requests. Treat completed playback as replayable from zero. Dispose all stream subscriptions and the player.

Alternative considered: `audioplayers`. `just_audio` exposes a state model and streaming/seek behavior that maps more directly to this client, while background features remain optional rather than bundled.

### Use explicit, private-network browser and Android access configuration

Add an `ARION_CORS_ORIGINS` setting parsed as a list of exact origins. Install FastAPI CORS middleware only for that allow-list, allow the read methods and `Range` request header, and expose `Accept-Ranges`, `Content-Length`, and `Content-Range`. Default to an empty list so the backend never grants arbitrary cross-origin access implicitly.

Android declares Internet permission. Because the first deployment uses a private LAN address without TLS, enable cleartext traffic for this private, owner-configured client and document that public or remote exposure should use HTTPS/Tailscale rather than broad Internet exposure.

Alternative considered: allow all origins. It would simplify development but conflicts with an explicit private-access posture and makes accidental exposure harder to reason about.

### Model asynchronous library requests with generations

The library controller owns the current query, loaded items, pagination offset/total, initial-load and load-more flags, and error. Each reset/search increments a request generation. Results update state only if their generation and query still match, preventing slow obsolete responses from replacing newer results. A load-more guard prevents duplicate concurrent page requests.

Alternative considered: cancelable HTTP requests. Generation checks are simpler, work with the standard HTTP abstraction, and still guarantee correct visible state.

### Make verification part of the client package

Commit `pubspec.lock` for the application. Add model/API/settings/controller unit tests, widget tests for initial configuration and library states, responsive smoke tests at phone and desktop sizes, and backend tests for CORS defaults and allow-listed origins. CI installs a pinned stable Flutter SDK, runs formatting verification, static analysis, tests, and a web release build. Local Android build instructions verify the APK when an Android toolchain is available.

## Risks / Trade-offs

- [Private LAN HTTP is unencrypted] → Keep the API bound privately, require an explicit server URL, document HTTPS/Tailscale for later remote access, and send no credentials in this change.
- [Browser media support varies by codec] → Preserve original content type and range headers, show a recoverable playback error, and avoid promising transcoding or universal codec support.
- [A browser may enforce CORS differently for media requests] → Test catalog, cover, and audio from an allowed development origin and explicitly configure request/exposed headers.
- [Plugin streams can update after widgets are disposed] → Centralize subscriptions in the player controller and cancel them before disposing the player.
- [Pagination can race with search] → Guard load-more calls and ignore responses whose generation no longer matches current state.
- [Flutter is absent locally] → Install a pinned stable SDK before scaffolding; keep the generated lockfile and run the same checks locally and in CI.
- [Built-in observable state may become verbose] → Keep controller interfaces narrow and reconsider a state-management package only when later features demonstrate a concrete need.

## Migration Plan

1. Install and verify a stable Flutter SDK and Android/web toolchains.
2. Generate `client/` for Android and web, add locked dependencies, and establish the testable composition root.
3. Add backend CORS configuration with an empty default and tests; operators opt in through `.env`.
4. Implement configuration, API models/client, library/search UI, and player UI in that order.
5. Add client CI checks and document local web/Android commands and private-network URL examples.
6. Deploy the API with only the intended web origin, then serve the web build or install the APK and run playback smoke tests.

Rollback removes the client artifact and clears `ARION_CORS_ORIGINS`; existing backend catalog and audio behavior remains unchanged.
