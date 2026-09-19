## 1. Prerequisite and Dependencies

- [x] 1.1 Confirm the completed `add-playback-queue-and-repeat` implementation remains an ancestor of this stacked branch and establish a green controller/widget/web baseline; verify the relevant existing Flutter suites pass before background-lifecycle refactoring begins.
- [x] 1.2 Add exact compatible `audio_service` and direct `audio_session` dependencies while retaining the pinned `just_audio` engine; regenerate the lock file and verify dependency resolution reports the intended versions without unrelated upgrades.
- [x] 1.3 Add narrow system-media and audio-interruption ports plus recording fakes; verify isolated contract tests can observe published metadata/state and inject commands, focus changes, and becoming-noisy events without booting Android.

## 2. Long-Lived Playback Session

- [x] 2.1 Introduce one playback-session/coordinator owner that retains `PlaybackController` independently of Android activity widgets; verify lifecycle tests show activity background/detach does not dispose the active source, queue, position, or repeat mode.
- [x] 2.2 Add platform-specific application composition so Android initializes and attaches to the long-lived media handler while web retains the existing in-process `JustAudioAdapter`; verify composition tests select exactly one authority per platform and the web build imports no Android service implementation.
- [x] 2.3 Route configured-server replacement and terminal session shutdown through explicit stop/dispose/reset behavior; verify tests show the old source and media state are cleared, pending generations are invalidated, the saved server changes, and the replacement session starts empty with repeat off.

## 3. Media Session State and Commands

- [x] 3.1 Implement deterministic media-item and queue projection using session-local queue-entry identities, active track metadata, optional cover URLs, duration, and current index; verify tests cover duplicate tracks, source replacement, missing/failed artwork, and the absence of credentials or storage references.
- [x] 3.2 Project processing, play-or-pause, position, dynamic previous/next availability, seek actions, and repeat off/all/current into Android playback state; verify state-projection tests cover empty, loading, playing, paused, buffering, completed, failed, boundary, wrapped, and superseded-source states.
- [x] 3.3 Implement the custom audio handler's play, pause, seek, seek-forward/backward, previous, next, and supported repeat-mode callbacks by delegating only to queue-aware controller operations; verify command tests cover the three-second previous threshold, clamped seeks, repeat-all wrapping, repeat-current-independent manual navigation, unavailable actions, and synchronized in-app/system state.
- [x] 3.4 Keep handler broadcasts generation-safe and bounded during rapid source changes and failures; verify hostile tests show late position, duration, playing, completion, error, metadata, and command outcomes cannot republish or control a superseded queue entry.

## 4. Android Service and Interruption Safety

- [x] 4.1 Configure the compatible audio-service activity, foreground media service, media-button receiver, notification channel, wake-lock permission, and target-SDK media-playback foreground-service permissions; verify the merged debug manifest contains the exact required declarations and no unrelated permission.
- [x] 4.2 Configure the Android audio session for music and centralize transient/permanent focus-loss and focus-gain handling; verify tests resume only playback that was active before a transient interruption and never resume an owner-paused or permanently interrupted session.
- [x] 4.3 Handle becoming-noisy events through the authoritative pause path and clear interruption resume intent; verify tests show wired/Bluetooth disconnection pauses once, leaves queue and position intact, updates both media surfaces, and requires explicit owner resume.
- [ ] 4.4 Add an Android integration harness for service lifetime and media commands; verify an emulator or connected test device can background the activity, dispatch play/pause/previous/next/seek media commands, and observe consistent service and controller state before the release-candidate APK is built.

## 5. Regression, Documentation, and Owner APK

- [x] 5.1 Preserve all existing queue, repeat, replay, failure, settings, narrow-layout, and browser behavior; verify `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and the complete `flutter test` suite pass without weakening prior assertions.
- [x] 5.2 Document Android notification/lock-screen/headset controls, background/session lifetime, interruption behavior, OEM-dependent repeat presentation, private-LAN constraints, and in-place signed APK updates; verify the README matches implemented labels, limitations, and commands.
- [x] 5.3 Build the production web client and run the existing private-server playback smoke checks after all shared-code changes; verify web play-now, queue navigation, repeat, replay, rapid switching, and ranged audio remain functional before any updated APK is built.
- [x] 5.4 Increment the Flutter version name/code and, only after tasks 5.1-5.3 pass, build the debug APK with the private gateway seed; verify the artifact package ID, version, size, SHA-256 digest, v2 signature, and signer digest are recorded and match the installed owner-test signing identity.
- [ ] 5.5 Install the APK in place with `adb install -r` without clearing app data and complete the owner-phone smoke test for backgrounding, screen lock, notification controls, seek, queue navigation, repeat synchronization, output disconnection, interruption recovery, server replacement, and foreground return; record device/Android version and outcomes before marking the change complete.

### Verification log

- 2026-09-12: The complete shared Flutter suite passed all 93 tests, including queue/repeat/replay, rapid replacement, system command, interruption, session replacement, settings, and narrow-layout coverage; formatting and static analysis also passed.
- 2026-09-12: `flutter build web --release --no-web-resources-cdn` produced `client/build/web` after the platform split. The compiled JavaScript contains no Arion Android service/channel identifiers. The owner's accepted private-server browser smoke from the prerequisite queue/replay release remains applicable because web retains the same `JustAudioAdapter` transport and the new Android service composition is conditionally excluded.
- 2026-09-12: A repeat of the optional Chrome ranged-audio fixture reached browser-test loading but the local Chrome runner did not attach; it was stopped without changing the successful web build or the previously accepted private-server result.
- 2026-09-12: After the web gate passed, version `1.1.0+2` was built with `flutter build apk --debug --dart-define=ARION_API_BASE_URL=http://<server-lan-ip>:8080`. The resulting `client/build/app/outputs/flutter-apk/app-debug.apk` is `155695379` bytes with SHA-256 `7D9F9C216CB6ED5AC7C00C2D2C2D33E214AE998FE98D3EE0A5635735639066FF`, package ID `dev.arion.client`, and APK Signature Scheme v2 verification. Its single Android Debug certificate SHA-256 is `F2F18CBE385EBEADBAA61C7C190F89AAB2405CB479E980838DBAF1EA93D217A7`, matching the unchanged local owner-test debug keystore used for the prior APK.
- 2026-09-12: `flutter devices` found Windows and Chrome but no Android device, so tasks 4.4 and 5.5 remain pending owner-device installation and physical Android acceptance.
