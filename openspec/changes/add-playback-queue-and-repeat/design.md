## Context

The Flutter client currently gives one `PlaybackController` authority over a single requested/active track and delegates one audio URL at a time through `AudioPlayerPort`. Source generations prevent late events from an old source from replacing newer state, and the web adapter may recreate its underlying engine during source replacement. The library screen starts tracks directly and renders a compact persistent now-playing panel. See `proposal.md` for the motivation and `specs/flutter-client/spec.md` for the observable queue contract.

This change is client-only. Track metadata and stable audio URLs already come from the catalog API, so the queue needs no backend representation or new external dependency.

## Goals / Non-Goals

**Goals:**

- Keep queue ordering, navigation, repeat policy, source transitions, and playback state under one deterministic authority.
- Preserve the generation-safe source replacement behavior on Android and web.
- Give duplicate queued tracks independent identities so editing one occurrence is unambiguous.
- Make queue behavior fully testable without a real audio engine.
- Leave a small playback entry point that future persistent playlists can use to replace the queue with an ordered track collection.

**Non-Goals:**

- Persisting or synchronizing queue position, repeat mode, or playback progress.
- Using native playlist/concatenating audio sources, preloading later tracks, or gapless playback.
- Adding shuffle, saved playlists, external imports, background playback services, lock-screen controls, or notifications.
- Changing the catalog, streaming API, database, or media storage.

## Decisions

### 1. Extend the playback controller as the single queue authority

The playback controller will own the ordered queue, current position, repeat mode, and active/requested source state. Public operations will cover play-now, play-next, append, next, previous, retry, repeat selection, upcoming-entry removal, and upcoming-entry movement.

Keeping this state together allows every action and player event to pass through one source-generation guard. A separate queue controller was considered, but it would require synchronization between queue position and asynchronous source loading and would create two competing authorities during failure or rapid navigation.

### 2. Represent occurrences with stable session-local queue entry identities

Each queue occurrence will contain a session-local entry identifier, its immutable catalog `Track`, and the resolved audio URI. The controller will retain one ordered list and a current index. Entries before the current index form navigation history; entries after it are upcoming. The queue UI exposes the current and upcoming portions, while the retained history supports previous and repeat-all behavior.

Play-now replaces the list with one entry. Play-next inserts at `currentIndex + 1`, append inserts at the end, and either action on an empty queue creates and starts the first entry. Only upcoming indices can be removed or moved, so an edit never has to replace the playing source. Entry identity rather than track ID makes duplicate tracks independently editable.

Using only a deque of upcoming entries was considered, but preserving prior entries separately would complicate repeat-all and previous navigation. A single ordered list plus index expresses all boundaries directly.

### 3. Keep one audio source loaded at a time

Queue advancement will continue to call the existing single-URL player boundary for each selected entry. The controller will not pass a concatenated playlist into `just_audio`. This retains the web engine-replacement workaround and keeps queue semantics independent of platform-specific playlist behavior.

At the start of a transition, the controller moves the requested queue position and invalidates the old source generation. Requested and successfully active entries remain distinct while loading. Only the matching generation can make the requested entry active or update its duration, position, playing, completion, or error state. If loading fails, that requested occurrence remains the current queue entry with an error and the surrounding queue remains available.

Native concatenating sources could reduce transition latency, but would couple the queue to `just_audio`, complicate the existing web replacement strategy, and make hostile rapid-selection cases harder to isolate. Preloading can be reconsidered after functional queue behavior is stable.

### 4. Resolve completion exactly once per active source generation

The controller will record whether completion has already been handled for the active source generation. The first completion event applies the selected repeat policy:

- repeat off: advance when an upcoming entry exists; otherwise remain completed;
- repeat all: advance, wrapping from the last entry to the first;
- repeat current: seek the active source to zero and resume it.

Starting a new source or successfully restarting the current source resets the completion guard. Manual next and previous use explicit queue navigation and are not treated as completion, so repeat-current cannot trap manual navigation. Repeat-all supplies the boundary target for both automatic and manual wrapping.

Handling completion directly inside the audio adapter was considered, but the adapter has no queue identity or repeat policy and would make source-generation ownership unclear.

### 5. Use conventional previous-button behavior with a fixed threshold

Previous restarts the current track when its reported position is greater than three seconds. At or before three seconds it selects the prior queue entry, or wraps to the final entry when repeat-all is active. With no prior or wrapped target, the control is disabled. Next selects the following entry and only wraps under repeat-all. The threshold will be a named controller constant and tested at both sides of the boundary.

Always selecting the previous entry was considered, but it makes restarting a partially heard track unnecessarily difficult. A time-based threshold matches common player behavior while remaining deterministic.

### 6. Preserve queue context through entry failures

A load timeout or playback error marks only the current requested occurrence as failed. Retry reloads that same entry with a fresh generation. Previous and next remain available according to queue boundaries, allowing the owner to leave a failed entry without clearing later tracks. No automatic error skipping will occur because silently omitting tracks would hide catalog or streaming problems.

When automatic advancement reaches a failing track, that track becomes the failed current occurrence under the same rule. Older errors and completion events are ignored by generation and cannot skip multiple entries.

### 7. Add compact controls and a responsive queue surface

The now-playing panel will add previous, next, repeat, and queue controls while retaining play/pause/replay, seek, loading, and retry behavior. Repeat will cycle through off, all, and current with distinct icon state, tooltip, and semantics. The queue control opens a responsive modal surface: a phone-friendly bottom sheet on narrow layouts and a constrained dialog or equivalent wide surface in browsers.

Catalog track rows keep play-now as their primary action and add explicit play-next and append actions through a compact overflow menu. The queue surface shows the current entry separately and uses an ordered, reorderable list for upcoming entries with per-occurrence removal. Controls derive enabled state from the controller rather than reproducing queue rules in widgets.

### 8. Let client-session replacement clear all playback state

Queue and repeat state remain owned by the existing configured-server client session. Replacing or disposing that session disposes its playback controller, which invalidates outstanding generations and discards the queue. A fresh controller starts empty with repeat off. No shared-preferences schema or migration is introduced.

## Risks / Trade-offs

- [A late completion event advances the queue twice] -> Handle completion once per active source generation and invalidate it before every transition.
- [Rapid manual navigation leaves queue position and loaded audio disagreeing] -> Track requested and active entries separately and accept source events only from the latest generation.
- [Reordering duplicate tracks changes the wrong occurrence] -> Address edits by stable session-local entry identity, not catalog track ID.
- [A web source replacement stalls while advancing automatically] -> Reuse the bounded transition timeout, retain the failed current occurrence, and leave retry/next available.
- [Repeat-current repeatedly reacts to one completed event] -> Mark the completion handled before seeking and clear the guard only after the restart path is established.
- [Additional controls crowd the persistent player on phones] -> Use compact icon controls, responsive wrapping, and move queue editing into a separate modal surface with narrow-layout widget tests.
- [Single-source loading introduces a short gap between tracks] -> Accept the gap for this first functional version; preloading and gapless playback remain future optimizations.

## Migration Plan

1. Add queue-entry and repeat state plus deterministic controller operations behind the existing audio-player test boundary.
2. Integrate automatic completion, manual navigation, failure preservation, and source-generation guards without changing the streaming API.
3. Add catalog actions, expanded now-playing controls, and the responsive queue surface.
4. Run focused Flutter unit and widget tests on Android-compatible and web adapter paths, followed by the full client test suite and analyzer.
5. Build and smoke-test the Flutter web client against the existing gateway, including rapid switching, queue advancement, repeat boundaries, a failed source, and narrow/wide layouts.

Deployment is a paired Flutter client image/APK update with no database or server migration. Rollback restores the previous client build; server data and media are unaffected.
