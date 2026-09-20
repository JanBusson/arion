## Why

Android playback currently survives a short outage only while the requested bytes remain in the forward RAM buffer. Seeking to discarded or not-yet-buffered media, and replaying a completed track from position zero, requires a fresh server request even though the track was already streamed; a bounded persistent playback cache should make completed media reusable without treating it as an owner-managed offline download.

## What Changes

- Cache Android track audio into app-private persistent storage while it is streamed, without delaying normal playback until the complete file has downloaded.
- Prefer a complete valid cached file for later playback so seeking and replay remain usable when the audio server is temporarily unreachable.
- Isolate cache entries by configured server and track identity, retain them across normal app restarts, and bound total storage with least-recently-used eviction that never removes the active entry.
- Treat partial, stale, corrupt, or unwritable cache state as a recoverable cache miss and preserve the existing network playback and bounded reconnect behavior.
- Keep browser playback unchanged.
- Do not add download buttons, guaranteed offline availability, offline catalog browsing, user-pinned files, or playlist downloads; those remain a separate future offline-download capability.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-client`: Add transparent, bounded, persistent Android playback caching and local reuse for seek and replay while preserving existing player state, queue/repeat behavior, and web behavior.

## Impact

- Affects the Flutter audio-player port and Android `just_audio` adapter, Android playback bootstrap, cache storage/index lifecycle, and playback/cache tests.
- Uses app-private device storage and introduces bounded disk and network usage while a track is being cached.
- Does not require a backend API or database change because the existing complete-response and byte-range audio endpoint already supplies the original immutable track media.
- This change is stacked on `add-resilient-streaming-recovery` and therefore depends on its Android load-control, recovery-state, and source-generation behavior. It also preserves the media-session behavior from `add-android-background-playback-controls`.
