## Why

The Android client currently reuses audio only after opportunistic playback caching and still needs the server to rebuild its catalog after a cold start. The owner needs a deliberate automatic-download mode that can prepare the small private library at home and make browsing, playback, seeking, replay, queue, and repeat dependable while away from the server.

## What Changes

- Add an Android-only “Keep library offline” preference that the owner enables once; while enabled, each successful full catalog refresh automatically reconciles and downloads the complete library.
- Persist a server-scoped catalog snapshot and complete audio files in app-private durable storage, distinct from the evictable bounded playback cache.
- Resume interrupted downloads when possible, limit concurrent work, publish per-track and aggregate progress, and clearly identify when the library is fully ready offline or needs attention.
- Prefer verified offline files for Android playback and fall back to the existing cached/network source and bounded recovery behavior when a file is absent or invalid.
- Restore the saved catalog on Android when the configured server is unreachable so downloaded tracks remain searchable, queueable, seekable, replayable, and controllable through the existing media session after a cold start.
- Reconcile additions, metadata changes, and removals only from a successfully completed unfiltered server snapshot; never erase usable offline state because a request failed or returned only a partial/search result.
- Keep Flutter web behavior unchanged and make no backend, database, or Docker changes.

## Capabilities

### New Capabilities

- `offline-library`: Owner-controlled automatic synchronization, durable storage, progress, reconciliation, and integrity rules for an Android offline music library.

### Modified Capabilities

- `flutter-client`: Extend Android catalog browsing and playback to use a persisted server-scoped snapshot and verified local audio when the server is unavailable, while retaining existing online and web behavior.

## Impact

- Affects Android settings, catalog/bootstrap state, library presentation/search, playback source resolution, download coordination, app-private storage, and their Flutter tests.
- Reuses the audio endpoint’s complete and byte-range responses; no backend API or schema change is required.
- Introduces durable device-storage and network usage, bounded download concurrency, and explicit cleanup when offline mode is disabled or server identity changes.
- This is a stacked change that depends on `add-android-persistent-audio-cache`; it will reuse its stable server-and-track cache identity and local-source fallback while separating guaranteed offline files from evictable playback cache entries.
