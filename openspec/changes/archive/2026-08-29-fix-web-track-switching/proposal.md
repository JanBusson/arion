## Why

After the Flutter web client starts one track, selecting another changes the visible title but can leave the first track playing indefinitely. This breaks the core playback contract and needs a focused fix before further player features are added.

## What Changes

- Make consecutive track selections reliably replace the active audio source in supported browsers while preserving Android playback behavior.
- Keep now-playing metadata, duration, position, loading state, and audible media synchronized with the source that actually loaded.
- Make only the newest selection authoritative during rapid or overlapping source transitions.
- Bound source loading, surface a retryable error when replacement fails or stalls, and prevent the old source from appearing as the newly selected track.
- Add deterministic controller, widget, browser, and live regression coverage for switching between distinct tracks.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-client`: Strengthen single-track playback and failure-recovery requirements so source replacement is atomic, stale transitions cannot overwrite current state, and stalled replacements fail coherently.

## Impact

- Affects the Flutter playback controller, the `just_audio` adapter lifecycle, now-playing presentation, and their tests.
- Adds browser-focused regression verification for two distinct ranged audio endpoints; the FastAPI and storage contracts remain unchanged.
- May change how the web adapter replaces or recreates its underlying player, but does not add a new service, database migration, or public API.
- The branch is stacked on the completed YouTube search change to preserve the currently tested repository state; the playback fix has no runtime dependency on YouTube discovery.
