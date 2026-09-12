## 1. Cache Storage Foundation

- [x] 1.1 Add the direct Flutter dependencies needed for an app-private cache root and stable SHA-256 cache keys, and verify dependency resolution succeeds without changing backend packages
- [x] 1.2 Implement an injectable Android playback-cache manager that maps normalized audio URLs to isolated entry directories and distinguishes atomic complete files from partial/orphan state, and verify unit tests cover stable keys, different-server isolation, cache hits, and incomplete entries
- [x] 1.3 Implement serialized touch, invalidation, orphan cleanup, and 1 GiB least-recently-used pruning with an active-entry exclusion, and verify filesystem tests cover eviction order, grouped companion cleanup, temporary overage for protected data, and later cleanup after protection moves
- [x] 1.4 Make cache initialization and filesystem operations fail open without exposing local paths, and verify injected directory, inspection, mutation, and cleanup failures produce a cache miss/fallback result rather than an uncaught error

## 2. Android Audio-Source Integration

- [x] 2.1 Extend the internal just_audio engine seam to load either a direct URL or an audio source without leaking package-specific types into the playback controller, and verify adapter forwarding and source-generation tests pass
- [x] 2.2 On Android, load a complete cache hit from its local file and load a miss through `LockCachingAudioSource` at the manager-provided destination, and verify adapter tests distinguish local reuse from simultaneous network playback/cache population
- [x] 2.3 Track caching completion and active-entry protection for the current source generation, cancel stale completion subscriptions on replacement/disposal, and verify rapid selections cannot touch, protect, prune, or publish completion for an obsolete source
- [x] 2.4 Invalidate a failing active local cache entry once and bypass cache on its recovery reload while preserving ordinary network errors, and verify tests cover corrupt local load fallback, cache-infrastructure fallback, successful network recovery, and terminal behavior when both sources are unavailable
- [x] 2.5 Enable the cache only from Android playback bootstrap while preserving the existing forward-buffer/recovery configuration and direct browser source path, and verify bootstrap plus web adapter tests cover both platform configurations

## 3. Playback and Media-Session Regression Coverage

- [x] 3.1 Verify controller tests show manual replay and repeat-current reuse the still-selected cached source without changing queue identity, repeat mode, completion arming, or position synchronization
- [x] 3.2 Verify seek, pause/resume, next/previous, manual retry, server/session replacement, and disposal tests retain their existing generation-safe behavior with cached and uncached source outcomes
- [x] 3.3 Verify background and system-media projection tests retain one playback authority and unchanged notification/lock-screen metadata, controls, buffering, recovery, and completion behavior while Android caching is active

## 4. Automated and Device Verification

- [x] 4.1 Format affected Dart files and run `flutter analyze` plus the full Flutter test suite, verifying both complete without errors
- [x] 4.2 Build the Flutter web client and verify its existing selection, playback, seeking, queue, repeat, and manual-retry behavior compiles and passes without persistent-cache code executing
- [x] 4.3 After all automated regression checks pass, build the replacement Android APK as the final build step and verify the artifact is produced without a backend, database, or Docker change
- [ ] 4.4 On a physical Android device, stream an uncached track until caching completes, disconnect Wi-Fi/mobile data, and verify arbitrary seek, manual replay, repeat-current, background playback, notification controls, and lock-screen controls continue without an audio request
- [ ] 4.5 On the physical device, verify a complete entry is reused after a normal app restart once catalog/session state is available, while an interrupted partial cache still follows bounded reconnect/manual-retry behavior and is never presented as guaranteed offline media

### Verification log

- 2026-09-12: `dart format --output=none --set-exit-if-changed lib test` checked 48 files without changes, `flutter analyze --no-pub` reported no issues, and the complete Flutter suite passed all 123 tests.
- 2026-09-12: `flutter build web --no-pub` produced `client/build/web`; Android cache implementation remains behind the native conditional bootstrap, while shared selection, playback, seeking, queue, repeat, and retry regressions passed in the complete suite.
- 2026-09-12: Only after the automated and web gates passed, version `1.3.0+4` was built with `flutter build apk --debug --no-pub --dart-define=ARION_API_BASE_URL=http://192.168.178.110:8080`. The resulting `client/build/app/outputs/flutter-apk/app-debug.apk` is `155711343` bytes with SHA-256 `C558F7557A7D3EF5A412C1446630517C65D305F83157D5BA874E596CA4A2761D`, package ID `dev.arion.client`, and APK Signature Scheme v2 verification. Its Android Debug certificate SHA-256 is `F2F18CBE385EBEADBAA61C7C190F89AAB2405CB479E980838DBAF1EA93D217A7`, matching the previous owner-test APK signing identity.
