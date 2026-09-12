## Context

See `proposal.md` for motivation and `specs/flutter-client/spec.md` for the behavior contract. Playback currently has one long-lived `PlaybackController` authority per configured session. It receives untyped engine errors through `AudioPlayerPort`, immediately converts every accepted error into a terminal state, and already uses source-generation checks to reject stale source transitions. Android and web share that controller, while `JustAudioAdapter` keeps a single engine on Android and recreates the engine between sources on web.

The backend already supports ranged audio responses, so reloading a source and seeking can resume without a new API. The pinned `just_audio` stack supports an Android-specific load-control configuration. The recovery design must also cooperate with the Android media session added by the stacked `add-android-background-playback-controls` change.

## Goals / Non-Goals

**Goals:**

- Let Android prefetch substantially more audio than the engine default without delaying initial playback by the same amount.
- Recover a previously active queue entry from its last confirmed position after a short interruption.
- Preserve explicit owner intent across engine state changes and prevent stale recovery work from affecting a newer source or session.
- Make timing deterministic and dependency-free in controller tests.

**Non-Goals:**

- Guarantee uninterrupted playback for an outage longer than the media already buffered.
- Classify failures using a connectivity plugin or retry only particular network exception types.
- Persist audio bytes across process restarts or make tracks available offline.
- Change browser recovery behavior, server endpoints, storage, or authentication.

## Decisions

### Use a larger bounded Android load-control window

Construct the Android `just_audio` engine with a 90-second minimum buffer and a 180-second maximum buffer. Keep the initial playback threshold at 2.5 seconds and the post-rebuffer threshold at 5 seconds, and prioritize time thresholds over byte thresholds. This separates quick startup from a larger steady-state safety margin while bounding memory and network use.

The configuration is applied only to the native Android engine. Web keeps its browser-managed buffering because browser media stacks do not expose the same load control and already require separate source-lifecycle handling.

Alternatives considered:

- The default engine buffer is simpler but does not deliberately improve tolerance of short outages.
- Downloading the entire track would bridge longer outages but has unbounded data/memory impact and starts to overlap persistent offline-cache policy.
- A disk cache would provide stronger resilience but introduces eviction, storage, privacy, and offline-product decisions that belong in a later change.

### Track playback intent separately from engine output

Add explicit controller state for whether playback is requested and whether a recovery is in progress. Engine `playing=false` is not sufficient to infer a pause: it can also occur while buffering or after a transport error. Owner play/pause actions, normal completion, session replacement, and source selection update playback intent deliberately.

The in-app controls and system-media snapshot project an active playback request as playing while recovery is buffering, which keeps a pause action available. The reconnecting state maps to buffering for the Android media session and also exposes a specific status in the in-app now-playing UI. Actual position remains the last confirmed engine position until fresh events arrive.

Alternative considered: retaining the current single `isPlaying` flag would be a smaller state model, but an error-generated `false` event would erase the information needed to decide whether recovery may auto-resume.

### Recover in the controller with an injectable bounded policy

Enable automatic recovery through an explicit controller policy supplied only by the Android bootstrap. The policy uses five attempts with delays of 0, 1, 2, 4, and 8 seconds and a 5-second timeout for each reload attempt. The durations and delay function are injectable so unit tests use immediate, deterministic scheduling rather than wall-clock waits.

Only unexpected errors from a source that had loaded successfully enter automatic recovery. Initial load failures and source-transition timeouts retain the existing terminal/manual-retry behavior. Because the current player port exposes errors as `Object`, all post-load errors are provisionally recoverable; the attempt and timeout bounds prevent permanent codec, authorization, or missing-file failures from looping indefinitely.

Each attempt reloads the current entry's URL, seeks to the last confirmed position, and calls play only when playback intent is still active. The queue, current index, repeat mode, visible metadata, and known duration remain stable throughout recovery. A successful reload clears reconnecting state and resumes normal event acceptance. Exhaustion converts the state to the existing non-sensitive terminal error with manual retry.

Alternatives considered:

- Recovering inside the adapter would hide queue identity and owner intent, making stale-source protection and media-state projection harder.
- Waiting for an external connectivity signal adds a dependency and can still misreport whether the actual audio endpoint is reachable. Attempting the real ranged source is the authoritative health check.
- Infinite retries resemble offline playback but can consume battery indefinitely and leave the UI permanently busy.

### Use a recovery token in addition to the source generation

Retain the existing source generation for track/source replacement and add a monotonically increasing recovery token for operations that cancel recovery without necessarily discarding the selected entry. Every delay, reload completion, seek, and play continuation verifies both the source identity and recovery token before changing state.

Pause invalidates the recovery token, clears playback intent, and leaves the current entry selected so a later play action can start a fresh reload. Selecting or skipping a track, manual retry, server/session replacement, stop, and dispose invalidate both relevant generations. Any non-cancellable engine future may finish, but its result is ignored and it cannot auto-play or publish stale state.

Alternative considered: incrementing only the source generation on pause would incorrectly make the still-selected queue entry look like a new source and would complicate later manual resume.

### Keep the player port small and project recovery through existing media states

No connectivity API or cache API is added to `AudioPlayerPort`. Android buffer configuration remains an adapter construction concern; retry orchestration uses the existing `setUrl`, `seek`, `play`, `pause`, and `stop` methods. The controller exposes reconnecting/playback-intent state needed by UI and `PlaybackSessionCoordinator`, while the system adapter continues to receive the existing `buffering` processing state.

Tests cover the policy at three layers: controller tests for timing, position restoration, intent, exhaustion, and stale-operation rejection; adapter construction/forwarding tests for platform-specific engine configuration without real network audio; and widget/media-projection tests for reconnecting status and pause-capable buffering state. Existing web source-replacement tests remain regression coverage.

## Risks / Trade-offs

- [A larger forward buffer increases Android memory and mobile-data use] → Bound the window at 180 seconds, avoid disk persistence, and verify playback startup is still governed by the small initial threshold.
- [Untyped permanent playback errors are retried] → Restrict automatic retry to previously active sources and cap both attempt count and per-attempt duration.
- [Position events can lag slightly behind audible playback] → Restore the latest confirmed position; a small replay is preferable to skipping audio, and restored positions remain clamped to the known duration.
- [An engine operation may not be physically cancellable] → Gate every asynchronous continuation with source and recovery generations, then best-effort stop stale work.
- [Android vendors may impose background-network or battery restrictions] → Keep recovery bounded and validate foreground, notification, lock-screen, and app-background cases on the physical device.
- [The branch depends on unmerged media-session work] → Keep it explicitly stacked, avoid duplicating playback ownership, and merge or rebase the prerequisite before this change.

## Migration Plan

1. Implement and verify the controller, adapter, UI, and system-media changes on the stacked feature branch.
2. Run the full Flutter test and analysis suites and build the web client to confirm compilation and automated browser-neutral behavior are unchanged. An interactive browser smoke test is not required for this Android-specific change.
3. After automated regression verification is complete, build a replacement Android APK and test short and prolonged outages in foreground, background, lock-screen, and notification-control scenarios.
4. Deploy with no backend or database migration. Roll back by reinstalling the previous APK; server and stored data remain compatible.
