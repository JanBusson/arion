## 1. Recovery State and Policy

- [x] 1.1 Add an injectable Android recovery policy and separate playback-intent/reconnecting state to the controller, and verify unit tests distinguish owner pause from engine-generated `playing=false`
- [x] 1.2 Implement bounded same-entry reload, last-position seek, and intent-aware resume, and verify controller tests cover immediate and delayed successful recovery without changing queue or repeat state
- [x] 1.3 Invalidate recovery on pause, track selection, skip, manual retry, session reset, and disposal, and verify delayed or in-flight stale attempts cannot seek, play, or overwrite newer state
- [x] 1.4 Preserve terminal failure and manual retry after exhaustion or initial-load failure, and verify tests cover attempt limits, per-attempt timeouts, non-sensitive errors, and a later successful owner retry

## 2. Android Buffering and Platform Wiring

- [x] 2.1 Configure the native Android audio engine with 90-second minimum, 180-second maximum, 2.5-second startup, and 5-second rebuffer thresholds, and verify adapter construction tests assert the bounded load-control values
- [x] 2.2 Enable the recovery policy only from Android playback bootstrap while leaving web defaults unchanged, and verify platform/bootstrap tests cover both enabled and disabled configurations

## 3. Player and System-Media Presentation

- [x] 3.1 Show a reconnecting state while retaining the selected track, position, and a usable pause control, and verify widget tests cover recovery start, cancellation, success, and exhausted-error presentation
- [x] 3.2 Project recovery as pause-capable buffering through the existing Android media session, and verify media/coordinator tests cover notification and lock-screen state without creating a second playback authority

## 4. Regression and Device Verification

- [ ] 4.1 Format the affected Dart files and run `flutter analyze` plus the full Flutter test suite, verifying both commands complete without errors
- [ ] 4.2 Build the Flutter web client and smoke-test selection, play/pause, seeking, queue, repeat, and manual retry in a browser, verifying Android-only recovery introduces no web regression
- [ ] 4.3 After web verification succeeds, build the replacement Android APK and verify the artifact is produced without changing backend or database deployment
- [ ] 4.4 On the physical Android device, verify buffered playback survives a brief outage, reconnects at the last position after a longer short outage, stops retrying on pause or source change, and reaches manual retry after a prolonged outage in foreground, background, notification, and lock-screen use
