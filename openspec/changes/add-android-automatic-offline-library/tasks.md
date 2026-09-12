## 1. Offline State and Durable Storage

- [ ] 1.1 Add lossless `Track`/catalog snapshot serialization and version validation, and verify round-trip, malformed, and unsupported-version unit tests pass
- [ ] 1.2 Define platform-neutral offline preference, snapshot, media-entry, progress, and coordinator contracts with inert web implementations, and verify contract/default-state tests preserve current web behavior
- [ ] 1.3 Implement normalized server and audio identity helpers shared with the persistent playback cache, and verify equivalent URLs collide while different servers/tracks remain isolated
- [ ] 1.4 Implement the Android application-support directory layout, atomic manifest writes, startup filesystem reconciliation, and exact server-scoped cleanup, and verify temporary-directory tests cover complete, missing, empty, mismatched, orphaned, and interrupted state
- [ ] 1.5 Extend the persistent playback cache with a safe complete-entry export operation, and verify it copies rather than moves valid content while cache misses/failures leave the destination unpublished

## 2. Automatic Synchronization and Downloads

- [ ] 2.1 Implement complete unfiltered catalog pagination at the API maximum page size with generation, offset, total, and duplicate validation, and verify incomplete, contradictory, failed, and stale generations never replace the prior snapshot
- [ ] 2.2 Implement streamed complete and byte-range-resume downloading with partial files, strict `200`/`206` and expected-length handling, atomic finalization, cancellation, and timeout behavior, and verify HTTP/fake-filesystem tests cover safe restart, compatible resume, incompatible ranges, truncated bodies, and retained resumable failures
- [ ] 2.3 Implement reconciliation for additions, metadata changes, unchanged immutable audio, deletions, partial cleanup, and playback-cache import, and verify only a successfully committed complete snapshot can schedule removals
- [ ] 2.4 Implement the session-scoped coordinator with at most two workers, automatic launch/enable/refresh triggers, retry, generation-safe cancellation, and aggregate/per-track states, and verify concurrency, no-redownload, failure, restart-resume, and disposal tests pass
- [ ] 2.5 Persist the disabled-by-default server-scoped preference and coordinate enable, confirmed disable, and server-change cleanup, and verify cancellation completes before exact offline data deletion

## 3. Offline Catalog Experience

- [ ] 3.1 Add Android snapshot fallback to initial library loading with explicit offline/stale state and retry, and verify a matching complete snapshot is used only after online failure while web/no-snapshot failures remain unchanged
- [ ] 3.2 Add local case-insensitive title, artist, and album search while a snapshot is active and restore the full snapshot when cleared, and verify stale online responses cannot replace newer local/search state
- [ ] 3.3 Connect successful unfiltered catalog activity and completed acquisitions to safe offline resynchronization without treating search or visible pagination as a deletion boundary, and verify controller/coordinator integration tests cover each trigger

## 4. Local-First Playback

- [ ] 4.1 Introduce an Android playback source resolver chain that checks verified durable offline media before persistent cache and network sources, with an inert web path, and verify offline selection performs no audio HTTP request
- [ ] 4.2 Add one-shot invalidation and cache/network fallthrough for a missing, length-invalid, unreadable, or decoder-failing offline source, and verify recovery cannot loop on the same local file or corrupt active-source generations
- [ ] 4.3 Verify local files support arbitrary seek, replay after completion, repeat-current, queue advancement, pause/resume, and rapid replacement through the unchanged playback controller semantics
- [ ] 4.4 Verify offline local-first playback continues through the existing Android background audio service, notification controls, lock-screen controls, audio focus, and noisy-headset behavior without creating a second media authority

## 5. Settings, Status, and App Lifecycle

- [ ] 5.1 Wire the Android offline store/coordinator into configured client-session creation and disposal, and verify cold-start restoration occurs before network sync while replacement sessions cannot publish old-server state
- [ ] 5.2 Add the Android "Keep library offline" setting with network/storage disclosure, destructive-disable confirmation, and retry action while leaving the web settings UI unchanged, and verify widget tests cover enable, cancel-disable, confirm-disable, and server replacement
- [ ] 5.3 Add compact aggregate readiness/progress presentation plus per-track offline-ready indicators, and verify widget tests distinguish disabled, preparing, ready, server-unavailable, failed, downloaded, and server-required states on narrow screens
- [ ] 5.4 Ensure coordinator work survives ordinary in-app navigation, stops cleanly on session disposal, and resumes after simulated process restart from valid manifest/partial state, and verify lifecycle tests have no post-dispose notifications or leaked clients

## 6. Verification and Owner APK

- [ ] 6.1 Format affected Dart files and run `flutter analyze` plus the complete Flutter test suite, verifying all checks pass without errors
- [ ] 6.2 Build the Flutter web client and verify existing catalog, search, playback, queue, repeat, cache, retry, and settings behavior compiles with no durable offline synchronization executing
- [ ] 6.3 After all automated and web gates pass, bump the Android version and build the replacement debug APK with the configured private server URL, verifying package identity, signature continuity, artifact size, and SHA-256
- [ ] 6.4 On a physical Android device, enable offline mode on the home network, wait for matching completed/total readiness, disconnect all server access, force-stop/reopen the app, and verify browse, local search, play, arbitrary seek, replay, repeat, queue, background playback, notification controls, and lock-screen controls work without audio requests
- [ ] 6.5 On the physical device, interrupt a download, restart and verify byte-range resume; then import/edit/delete server tracks and verify safe reconciliation, confirmed disable cleanup, and server-change isolation without losing unrelated app state
