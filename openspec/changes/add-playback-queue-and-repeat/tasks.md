## 1. Queue State and Editing

- [x] 1.1 Add session-local queue-entry identity, ordered queue/current-index state, repeat-mode state, and immutable controller projections; verify controller tests cover the empty defaults, repeat-off default, current/upcoming projections, and duplicate occurrences.
- [x] 1.2 Implement play-now, play-next, and append operations with resolved track audio URIs; verify focused controller tests cover queue replacement, insertion order, appending, empty-queue startup, non-interruption of the current source, and repeated tracks.
- [x] 1.3 Implement upcoming-entry removal and movement by queue-entry identity; verify focused controller tests cover first/last moves, removal, navigation availability updates, duplicate identities, rejected current/history edits, and preservation of active playback state.

## 2. Navigation, Completion, and Recovery

- [x] 2.1 Implement manual next and previous navigation, the three-second restart threshold, repeat-all boundary wrapping, and repeat-current-independent manual navigation; verify controller tests cover positions below, at, and above the threshold plus every enabled/disabled boundary.
- [x] 2.2 Implement repeat-mode selection and exactly-once natural-completion handling for repeat off, repeat all, and repeat current; verify controller tests cover intermediate advancement, final completion, one-entry queues, wrapping, replay from zero, paused mode changes, and duplicate completion events.
- [x] 2.3 Integrate queue transitions with requested-versus-active source generations and the existing bounded source-load path; verify hostile controller tests cover rapid play-now/next/previous actions and late duration, position, playing, error, and completion events from superseded sources.
- [x] 2.4 Preserve queue and repeat state through current-entry load/playback failures while supporting retry and manual skip; verify tests cover a failing initial entry, a failure reached by automatic advancement, retry success/failure, skip-to-next, and unchanged surrounding queue order.
- [x] 2.5 Keep queue and repeat lifecycle scoped to the configured-server client session; verify app/controller tests demonstrate that a replacement or disposed session invalidates pending work and a fresh session starts empty with repeat off while the saved server setting remains available.

## 3. Flutter Player and Queue Experience

- [x] 3.1 Keep catalog-row play as play-now and add explicit play-next and append actions using the catalog API's audio URI resolver; verify library widget tests invoke the correct controller operation and keep actions usable for duplicate selections and phone-width rows.
- [x] 3.2 Expand the now-playing panel with previous, next, repeat-mode, and queue controls whose labels, icons, and enabled states come from controller state; verify widget tests cover all repeat modes, navigation boundaries, loading, completion, failure/retry, and no horizontal overflow at narrow width.
- [x] 3.3 Add a responsive queue surface that identifies the current entry and lists, removes, and reorders upcoming occurrences by entry identity; verify widget tests cover empty/single/multi-entry queues, duplicate tracks, revised playback order, narrow bottom-sheet presentation, and constrained wide-browser presentation.
- [x] 3.4 Preserve the existing play/pause/replay, seeking, metadata, duration, and buffering behavior while adding queue controls; verify the existing playback and library widget suites pass without weakening their source-consistency assertions.

## 4. Documentation and End-to-End Verification

- [x] 4.1 Document the session-only queue actions, repeat-off/all/current behavior, three-second previous action, and explicit exclusions of shuffle and saved playlists in the client-facing README section; verify the documented labels and behavior match the implemented UI and spec.
- [x] 4.2 Run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and `flutter test` from `client`; verify all formatting, static analysis, controller, adapter, and widget checks pass.
- [ ] 4.3 After all planned web functionality and automated checks are complete, build the production web client and smoke-test play-now, play-next, append, automatic advancement, previous/next, all repeat modes, queue reordering/removal, rapid switching, and failed-entry retry/skip against the private Arion server; record the exact commands and outcomes.
- [ ] 4.4 Only after the web version is fully complete and verified, build the debug Android APK as the final implementation step and record the exact command and outcome before marking the change complete.

### Verification log

- 2026-08-29: `dart format --output=none --set-exit-if-changed lib test` passed (`31` files, `0` changed).
- 2026-08-29: `flutter analyze` passed with no issues.
- 2026-08-29: `flutter test` passed all `80` tests.
- 2026-08-29: `openspec.cmd validate add-playback-queue-and-repeat --strict` passed.
- 2026-08-29: `flutter build web --release --no-web-resources-cdn` produced `client/build/web`. Flutter emitted its existing Cupertino-icons font expectation warning; no Cupertino icon references exist in `client/lib` or `client/pubspec.yaml`.
- 2026-09-12: Strengthened the manual-replay and repeat-current regression tests to emulate `just_audio` retaining its playing flag after natural completion; both focused playback suites passed (`22` tests).
- 2026-09-12: After synchronizing the completed transport with `pause -> seek(0) -> play`, `dart format --output=none --set-exit-if-changed lib test` passed (`31` files, `0` changed), `flutter analyze` passed with no issues, and `flutter test` passed all `80` tests.
- 2026-09-12: `flutter build web --release --no-web-resources-cdn` produced the corrected `client/build/web`. Flutter emitted only the previously documented Cupertino-icons font expectation warning.
- Private-server browser smoke test is pending an accessible Arion server and test catalog; task 4.3 therefore remains open.
- Android APK build was deliberately not run and remains the final task after 4.3.
