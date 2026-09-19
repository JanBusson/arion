## Why

Arion can currently play only the explicitly selected track, so listening beyond one track requires repeated manual selection and there is no way to prepare or inspect what plays next. A session-scoped playback queue and explicit repeat behavior provide the first practical multi-track listening flow while keeping persistence and playlist management for a later change.

## What Changes

- Replace isolated single-track selection with a client-owned playback queue containing one current entry and ordered upcoming entries.
- Let the owner play a track immediately, play it next, or append it to the queue.
- Add previous and next controls, automatic advancement after successful completion, and a queue view that supports removal and reordering.
- Add three repeat modes: off, repeat the full queue, and repeat the current track.
- Keep the queue intact when an individual source fails, expose a retryable error for that entry, and allow the owner to continue with another queued track.
- Keep queue and repeat state in the current Flutter client session only, and clear them when the configured Arion server changes or the client session ends.
- Preserve generation-safe source replacement so stale player events cannot select, advance, or overwrite a newer queue entry.
- Exclude shuffle, persistent playlists, queue synchronization, background media controls, and external playlist import from this change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-client`: Extend client playback from one explicitly selected source to an owner-managed session queue with previous/next navigation, automatic advancement, queue editing, repeat modes, and responsive queue controls.

## Impact

- Affects the Flutter playback controller and its audio-player boundary, library track actions, now-playing controls, and a new queue presentation in the Android/web client.
- Expands controller, adapter-boundary, and widget tests for queue ordering, repeat boundaries, failures, rapid source changes, and narrow/wide layouts.
- Does not change FastAPI endpoints, PostgreSQL models, audio storage, ranged streaming behavior, or deployment topology.
