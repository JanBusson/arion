## Why

Arion currently turns a temporary loss of connectivity into a terminal playback error, so even a short mobile-network, Wi-Fi, or Tailscale interruption stops the active song and requires owner intervention. The Android client should absorb brief outages with a larger forward buffer and recover the same queue entry at its last known position when the connection returns.

## What Changes

- Configure the Android `just_audio` engine with an explicit, bounded forward-buffer policy while preserving quick initial playback.
- Distinguish a recoverable playback interruption from a terminal failure and expose a non-terminal reconnecting state to the in-app player and Android media session.
- Retry the current source with bounded backoff, restore the last known position, and resume only when playback was active before the interruption.
- Cancel obsolete recovery attempts when the owner pauses, chooses another queue entry, changes server, or terminates the session.
- Keep browser playback behavior unchanged and preserve the existing manual retry path after automatic recovery is exhausted.
- Do not add persistent media caching, automatic song downloads, offline availability, or backend/API changes in this change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-client`: Add buffered Android streaming and generation-safe automatic recovery of temporarily interrupted playback.

## Impact

- Affects the Flutter playback controller, `JustAudioAdapter` engine construction, Android/system-media state projection, now-playing status text, and playback tests.
- Retains the pinned `just_audio`, `audio_service`, and `audio_session` stack; no new service, database, backend endpoint, permission, or storage dependency is expected.
- This branch is intentionally stacked on `add-android-background-playback-controls`; recovery must use its single long-lived playback authority and media-session projection.
- A new APK will be required after web regression verification. Existing backend ranged streaming and deployed web behavior remain compatible.
