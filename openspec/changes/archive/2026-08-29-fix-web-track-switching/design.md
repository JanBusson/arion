## Context

See `proposal.md` for motivation and `specs/flutter-client/spec.md` for the behavior contract.

Live Chrome reproduction established that the first selected audio source remains active after a second track is selected: the title changes, the duration remains from the first track, and the server receives no audio request for the second track. Reversing the order makes the other first source stick, and the server files have distinct identifiers, durations, and content hashes. The failure is therefore at the reused Flutter web player/source-transition boundary rather than catalog identity, storage, or HTTP range streaming.

`PlaybackController` currently commits the requested track before `setUrl` completes. Player event subscriptions are shared across every source generation, while the generation guard protects only asynchronous method completion. A `setUrl` call that stalls can consequently leave old-source events updating state with new metadata and never expose an error. The project currently uses `just_audio` 0.10.6 with `just_audio_web` 0.4.16; upstream has addressed related interrupted-load behavior, but the observed failure remains reproducible with this version and app flow.

## Goals / Non-Goals

**Goals:**

- Make every source transition an explicit, bounded operation with one authoritative generation.
- Keep requested, loading, and active source identities distinct until loading succeeds.
- Isolate browser source replacement from a reused web player that can remain stuck on its first source.
- Preserve the shared playback interface and Android behavior.
- Provide deterministic automated regression tests plus a real-browser verification path.

**Non-Goals:**

- Loop or repeat controls.
- Queue management, gapless playback, or a playlist architecture.
- Changes to audio import, storage, catalog identity, or range-response behavior.
- Maintaining a private dependency fork unless the adapter-level solution proves insufficient.

## Decisions

### Model source replacement as an atomic transition

The controller will distinguish the requested track from the active track. A selection starts a monotonically identified transition, enters loading state, and stops the old source from being represented as the new track. The controller commits the new active track, duration, position, and playback state only after that transition's source load succeeds.

Every completion and player event must be associated with the currently authoritative player/source generation. Events from disposed or superseded generations are ignored. This extends the existing completion guard to the streams that currently mutate controller state without source identity.

Alternative considered: keep optimistically assigning the selected track and only fix `setUrl`. This would still permit title/audio mismatches during ordinary buffering and failure, so it does not satisfy the synchronization contract.

### Recreate the web player for source replacement

The playback adapter will own a replaceable player instance and its subscriptions. On web, replacing a loaded source creates and configures a fresh underlying `AudioPlayer`, switches the adapter's authoritative generation, then disposes the superseded player. The controller continues to depend on the platform-neutral adapter contract; Android may retain normal in-player source replacement when tests confirm it is reliable.

The swap ordering must prevent two sources from playing simultaneously: the old player is stopped before the new player can start, while stale callbacks are generation-filtered. Failure while preparing the fresh player leaves an explicit non-playing/error state rather than silently relabelling the old source.

Alternatives considered:

- Calling `stop()` before `setUrl()` on the same player was tested live and did not resolve the stuck transition.
- Representing the entire catalog as one `ConcatenatingAudioSource` would complicate search, pagination, and dynamic imports for a single-track player.
- Immediately upgrading or forking `just_audio_web` would enlarge dependency risk without a verified upstream release that fixes this exact reproduction. Dependency changes remain a fallback after adapter isolation is tested.

### Serialize transitions and bound loading

Source transitions will execute through a single controller path with a generation token. A newer request supersedes an older one; older futures may complete, but cannot play or publish state. Each load uses a finite timeout selected in client configuration/code and covered by tests. Timeout, adapter error, and decode failure converge on one retryable failure state.

Retry starts a new generation and a fresh web player instead of reusing the potentially stuck instance. A timeout cannot forcibly cancel every plugin future, so disposal plus generation filtering provides logical cancellation.

### Verify actual source identity, not only labels

The fake playback adapter will support delayed, failed, and never-completing loads and generation-scoped events. Controller tests will cover A-to-B replacement, paused replacement, rapid A-to-B-to-C selection, stale events, timeout, and retry. Widget tests will assert the adapter's active source and coherent duration/state in addition to visible metadata.

A Chrome regression test will use two distinct audio endpoints and verify that the second selection causes a request for the second track and publishes its duration/source state. The private live check will repeat this against two authorized server tracks and inspect access logs for the second track's ranged request. Android unit/build regression verification remains required.

## Risks / Trade-offs

- [Fresh web players add lifecycle and subscription complexity] → Centralize creation, subscription replacement, generation checks, and disposal inside the adapter and test for leaked callbacks.
- [Stopping the old player before the replacement loads creates a short silence] → Prefer truthful, bounded loading state over continuing mismatched audio; keep UI responsive and expose retry on failure.
- [A timed-out plugin future may complete later] → Dispose its player generation and reject all stale completions/events before they reach controller state.
- [Browser autoplay rules may reject playback on a newly created media element] → Create and start replacement within the user-initiated selection flow, surface platform rejection, and cover Chrome behavior in integration testing.
- [Different Android and web replacement paths can drift] → Keep one adapter contract and shared controller tests, with platform-specific behavior limited to player lifecycle policy.

## Migration Plan

1. Add failing controller and widget regressions for consecutive and overlapping source transitions.
2. Introduce generation-scoped adapter lifecycle and atomic controller state, then make the regressions pass.
3. Run Flutter analysis and tests, a production web build, and Android build/regression checks.
4. Deploy only the rebuilt web/client image to the private server and validate two distinct tracks in Chrome, including the second ranged request.
5. Roll back to the previous web/client image if the browser verification fails. No API, database, or stored-audio rollback is required.
