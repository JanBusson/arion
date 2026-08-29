## 1. Regression Test Harness

- [x] 1.1 Extend the fake playback adapter to model delayed, failed, and never-completing source loads plus stale generation events; verify the fake's focused unit tests pass.
- [x] 1.2 Add controller regressions for playing and paused A-to-B replacement that assert the active audio URL, track metadata, duration, and position all switch together; verify the new tests fail against the current implementation for the reproduced bug.
- [x] 1.3 Add controller regressions for rapid A-to-B-to-C selection, stale completions/events, load timeout, and retry; verify the tests demonstrate that only C or a coherent error state can become authoritative.
- [x] 1.4 Strengthen the library widget regression to assert the playback adapter's second source and matching duration/state rather than only the second title; verify the test detects a title/audio mismatch.

## 2. Generation-Scoped Player Adapter

- [x] 2.1 Refactor the playback adapter to own replaceable player instances and generation-scoped subscriptions while preserving its platform-neutral controller contract; verify adapter lifecycle tests cover creation, replacement, and disposal.
- [x] 2.2 Implement the web replacement policy that stops the old player, prepares a fresh player for each replacement or retry, ignores callbacks from superseded players, and disposes them safely; verify consecutive-source adapter tests pass without overlapping playback.
- [ ] 2.3 Preserve the reliable native/Android source-loading path behind the same adapter contract; verify shared adapter/controller tests pass on the Dart VM and an Android build succeeds.

## 3. Atomic Playback State

- [x] 3.1 Separate requested/loading track state from the successfully loaded active track in `PlaybackController`; verify first-load and A-to-B tests never label old audio as the new track.
- [x] 3.2 Serialize source transitions with a monotonically increasing generation so only the newest selection can publish completion or stream state; verify rapid-selection and stale-event tests pass.
- [x] 3.3 Add a finite source-load timeout and route timeout, load, decode, and playback failures into one non-sensitive retryable state; verify timeout and retry tests complete without hanging.
- [x] 3.4 Update now-playing controls to render coherent loading, active, and error states without regressing pause, resume, seek, or replay; verify controller and widget playback suites pass.

## 4. Browser Regression Coverage

- [x] 4.1 Add a Chrome integration fixture with two distinct ranged audio endpoints and observable request identities; verify each endpoint can load independently in the test browser.
- [x] 4.2 Add a Chrome regression that plays track A, selects track B while playing and while paused, and asserts a request for B plus B's synchronized duration/source state; verify the test fails on the old behavior and passes with the fix.
- [x] 4.3 Add a rapid browser selection case and check that superseded media elements cannot publish state or continue playback; verify Chrome reports only the newest track as active.

## 5. Verification and Private Deployment

- [x] 5.1 Run Flutter formatting, static analysis, and the complete client unit/widget suite; verify all commands finish successfully with no new diagnostics.
- [ ] 5.2 Produce release web and Android builds and build the affected Docker image; verify each build completes and the image starts successfully in the Compose verification environment.
- [ ] 5.3 Deploy the rebuilt web/client image to the private server, select two authorized tracks in both orders in Chrome, and verify UI metadata/duration match the audible track and server logs contain the second track's ranged request.
- [x] 5.4 Record the focused test, build, and live-verification evidence in the change and confirm `openspec validate fix-web-track-switching --strict` passes before marking the change complete.
