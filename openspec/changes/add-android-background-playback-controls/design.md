## Context

The completed queue/repeat change leaves `PlaybackController` as the authority for queue identity, navigation, repeat policy, completion, source generations, and playback failures. It currently owns an `AudioPlayerPort` created inside the configured-server Flutter widget session; Android has only internet and private-cleartext configuration and no foreground media service, media session, or audio-focus integration. See `proposal.md` for motivation and `specs/flutter-client/spec.md` for observable behavior.

This change is stacked on `add-playback-queue-and-repeat`. That prerequisite must be preserved when the changes are synced, merged, or archived because the system command path depends on its controller semantics.

## Goals / Non-Goals

**Goals:**

- Keep exactly one queue/playback authority while allowing both Flutter widgets and Android system surfaces to observe and command it.
- Keep the playback owner alive independently of the Android activity while the service/process remains alive.
- Map queue entries, metadata, position, processing, controls, and repeat mode deterministically into an Android media session.
- Handle audio focus, output disconnection, client-session replacement, and service shutdown without unexpected playback or stale notification state.
- Preserve the existing web adapter and browser lifecycle.
- Make Android integration testable through ports and state projections before physical-device acceptance.

**Non-Goals:**

- Restoring a queue or position after process death, reboot, force-stop, or a newly created client session.
- Moving Arion's queue into a native concatenating audio source or delegating queue policy to Android.
- Guaranteeing a custom repeat button on every notification shade, lock screen, wearable, car, or OEM skin.
- Production signing, automatic update delivery, Play Store packaging, Android Auto browsing catalogs, downloads, or offline playback.

## Decisions

### 1. Use `audio_service` with a custom Arion audio handler

Add pinned `audio_service` and direct `audio_session` dependencies while retaining `just_audio` as the renderer. A custom Arion audio handler will own or retain the long-lived playback session, delegate commands to the queue-aware controller, and broadcast Android media state.

`just_audio_background` was considered because it provides a smaller setup for simple players. It assumes media controls can follow the `AudioPlayer` source model, while Arion intentionally keeps an application-owned queue and loads one URL at a time. A custom `audio_service` handler can route previous, next, repeat, and failure-aware commands through Arion's existing semantics instead of creating a second queue authority.

### 2. Move playback-session ownership out of the Android widget lifecycle

Introduce a playback-session/coordinator boundary created during application bootstrap. On Android, the initialized audio handler will retain the active controller and engine while the activity backgrounds or is dismissed. The configured-server UI will attach to that session rather than constructing an activity-owned player authority. Replacing the configured server will explicitly stop and dispose the prior source, reset queue/repeat state, and attach the UI to a fresh controller before new requests are allowed.

The web build will continue to use an in-process session with the existing `JustAudioAdapter`; conditional platform composition will prevent Android service setup from changing browser behavior. Keeping the current controller solely inside the widget was considered, but it makes service lifetime depend on Flutter activity ownership and risks losing commands or disposing audio while the system notification is still active.

### 3. Keep `PlaybackController` authoritative and make media-session output a projection

The handler will translate controller state into `MediaItem`, media queue, and playback-state broadcasts:

- a session-local queue-entry ID becomes the media item identity, so duplicate tracks remain distinct;
- title, artist, album, duration, and an eligible cover endpoint become system metadata without storage paths or credentials;
- controller position and processing state determine the media progress and buffering/ready/completed projection;
- dynamic previous/play-or-pause/next controls come from controller capability state;
- seek, seek-forward/backward, and repeat-mode support are advertised as system actions;
- repeat off/all/current map to the platform's none/all/one values;
- current index and ordered queue mirror the controller queue without allowing Android to reorder it implicitly.

System callbacks will call controller operations and wait for their bounded outcomes where available. They will never manipulate `just_audio` directly. A separate platform queue/controller was considered, but synchronizing duplicate identities, source generations, completion, and failed entries across two authorities would recreate race conditions already solved in the controller.

### 4. Use platform-standard controls and treat repeat UI as capability-dependent

The Android compact media presentation will prioritize previous, play/pause, and next. Position seeking and supported forward/backward actions will be advertised for expanded system surfaces. Repeat state and repeat-mode commands will be supported at the media-session level, but Arion will not require a custom repeat notification button because available buttons and layout vary across Android versions, device form factors, and OEM surfaces.

Adding a custom notification implementation was considered, but it would add Android-specific UI maintenance without making repeat consistently available across all system surfaces. The in-app repeat control remains the guaranteed owner interface.

### 5. Centralize audio-focus and becoming-noisy policy

Configure the platform audio session for music. The coordinator will track whether playback was active immediately before a transient interruption, pause through the authoritative controller, and resume only after focus returns when that precondition still holds. Permanent focus loss pauses without automatic resume. A becoming-noisy event, such as wired-headset or Bluetooth disconnection, pauses and clears automatic-resume intent so audio cannot unexpectedly continue through the speaker.

Allowing both the playback engine and the coordinator to react independently was considered, but duplicate pause/resume paths can make controller and notification state disagree. One interruption policy will own the state transition and publish its result.

### 6. Configure the Android foreground media service explicitly

Update Android configuration with the wake-lock and foreground-service permissions required by the selected target SDK, including media-playback foreground-service permission, plus the audio service, media-button receiver, foreground-service type, and compatible activity base. The service notification channel will be stable and owner-readable. No notification content will contain credentials or raw storage references.

The implementation will verify exact manifest merging against the pinned plugin and Android target rather than copying unreviewed example configuration. Requesting unrelated Android permissions is out of scope.

### 7. Keep state mapping and commands behind testable ports

Separate media-session publishing and audio-interruption events from Android plugin calls behind narrow interfaces. Unit tests will feed controller states into a recording system-media sink and send system commands through the handler without booting Android. Existing controller, adapter, widget, and browser tests must continue to pass. A final emulator or physical-device smoke test will verify behavior the Dart test boundary cannot prove: foreground service lifetime, notification rendering, lock-screen controls, media buttons, audio focus, and output disconnection.

Mocking only `just_audio` was considered insufficient because the highest-risk behavior is synchronization between controller, service, and system state rather than decoding audio.

### 8. Deliver Android changes as an in-place APK update

Increment the Flutter version name/code for the feature APK and build it with the same application ID and existing debug signer for owner testing. `adb install -r` or Android's package installer can then replace the prior test build while preserving saved app data when the signing certificate matches. Record artifact size, digest, signer, and the configured private-server seed used for the build.

Long-term release signing and update distribution require a separately secured release key and delivery design. They are intentionally deferred rather than mixing credential lifecycle into background-playback behavior.

## Risks / Trade-offs

- [The activity and service create separate playback authorities] -> Initialize one audio handler/session at bootstrap and make UI and system controls attach to it.
- [Late player events publish stale notification metadata] -> Preserve source-generation guards and project only the controller's successfully active queue entry.
- [Android commands bypass queue/repeat rules] -> Delegate every system command to existing controller operations and derive enabled actions from controller capability state.
- [A paused or completed notification cannot resume reliably on newer Android versions] -> Follow the pinned plugin's foreground-service guidance and verify pause/resume after backgrounding on the target phone.
- [Audio resumes unexpectedly after a call or output disconnect] -> Track transient-focus resume intent centrally and clear it on owner pause, permanent loss, or becoming-noisy events.
- [Cover retrieval delays or breaks the media notification] -> Publish metadata immediately and treat artwork as optional with a stable fallback.
- [Android integration accidentally affects web playback] -> Use platform composition and run the complete existing web/controller/widget suites unchanged.
- [A new local debug keystore prevents in-place installation] -> Verify the signer digest before installation and stop rather than uninstalling the existing app automatically.
- [The stacked branch obscures its prerequisite] -> Keep the dependency recorded and integrate/archive the queue change before this change is finalized independently.

## Migration Plan

1. Integrate the completed queue/repeat change into the target branch while preserving its tests and web deployment evidence.
2. Add and pin the media-session/audio-session dependencies, platform composition, and Android manifest/service configuration.
3. Introduce the long-lived playback coordinator and media-session projection without changing queue semantics or web composition.
4. Add system command delegation and interruption/noisy-event handling with focused unit and lifecycle tests.
5. Run formatting, analysis, all Flutter tests, Android manifest inspection, and a web release regression build.
6. Increment the client version and build a signed debug APK with the private gateway as a non-secret seed.
7. Verify the signer matches the installed owner test build, install as an update, and smoke-test background, locked-screen, notification, headset/Bluetooth, queue navigation, seeking, repeat synchronization, interruptions, server replacement, and foreground return.

Rollback reinstalls the previous APK signed by the same key. Backend, database, media, and the deployed web client require no rollback.
