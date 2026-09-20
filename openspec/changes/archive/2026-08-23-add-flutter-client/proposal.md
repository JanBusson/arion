## Why

Arion can now catalog and stream audio, but the owner still needs command-line requests to use it. A focused Flutter client is the next useful increment because it turns the backend into a playable product on both Android and the browser while keeping the first UI small enough to test and learn from.

## What Changes

- Add a Flutter application targeting Android and web from one codebase.
- Let the owner configure the private Arion API base URL without embedding a server address in source code.
- Present the track catalog with pagination, search, metadata, and cover-art fallbacks.
- Provide single-track playback controls with play/pause, elapsed and total time, seeking, and clear current-track state.
- Add explicit loading, empty, retryable error, and unreachable-server states.
- Permit configured private browser origins to call the API during web development and private deployment.
- Add deterministic client tests, formatting/static-analysis commands, and setup/run documentation.
- Keep importing, metadata editing, playlists, authentication, background playback, downloads, and transcoding outside this change.

## Capabilities

### New Capabilities

- `flutter-client`: Covers private-server configuration, library browsing and search, cover presentation, audio playback and seeking, responsive Android/web behavior, and user-visible failure states.

### Modified Capabilities

- None.

## Impact

- Adds a new `client/` Flutter package and its Android/web platform projects.
- Adds Flutter packages for HTTP access, audio playback, persisted settings, and testable state management.
- Extends FastAPI configuration and middleware for an explicit allow-list of browser origins; no public exposure or authentication model is introduced.
- Extends CI and repository documentation with Flutter setup, analysis, tests, web execution, Android builds, and API URL examples.
- Requires a Flutter SDK for client generation, dependency resolution, testing, and builds; it is not installed in the current workstation environment and must be installed before implementation can be fully verified.
