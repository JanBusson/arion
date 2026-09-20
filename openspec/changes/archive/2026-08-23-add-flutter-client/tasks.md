## 1. Flutter Foundation

- [x] 1.1 Make a pinned stable Flutter SDK available, record the version in project documentation/CI, and verify `flutter doctor -v` recognizes the web toolchain and reports the Android toolchain state.
- [x] 1.2 Generate the `client/` application for Android and web only, set the Arion package identity and lints, update repository ignores, and verify `flutter pub get` succeeds with a committed application lockfile.
- [x] 1.3 Add the HTTP, audio-player, and asynchronous preferences dependencies plus a feature-oriented `lib/` structure and verify the package resolves without unused scaffold code or example tests.

## 2. Private API Access

- [x] 2.1 Add validated `ARION_CORS_ORIGINS` backend configuration with an empty default, document it in `.env.example`, wire it through Compose, and verify configuration tests cover empty, single, and multiple exact origins.
- [x] 2.2 Add FastAPI CORS middleware for configured origins, read methods, the `Range` header, and audio response headers, and verify backend API tests cover allowed, preflight, unconfigured, and default-denied origins.
- [x] 2.3 Implement normalized base-URL validation and asynchronous persistence behind a settings-store interface, including optional Dart-definition seeding, and verify unit tests cover valid HTTP/HTTPS URLs, normalization, invalid input, precedence, save, and reload.

## 3. Catalog Data and State

- [x] 3.1 Implement immutable track/page models with strict API JSON parsing and duration formatting, and verify unit tests cover complete values plus missing or incorrectly typed fields.
- [x] 3.2 Implement an injectable Arion API client for paginated/search catalog requests and cover/audio URI construction with bounded timeouts and safe failures, and verify mock-client tests cover query encoding, pagination, success, non-2xx, malformed JSON, and timeout behavior.
- [x] 3.3 Implement the library controller with initial load, retry, incremental pagination, search reset, load-more guarding, and stale-response generations, and verify controller tests cover populated, empty, error/retry, pagination, clear-search, and out-of-order responses.

## 4. Playback

- [x] 4.1 Define the audio-player boundary and implement its `just_audio` adapter for URL loading, play, pause, seek, processing state, position, duration, completion, errors, and disposal; verify adapter-facing tests use a fake boundary without fetching complete audio in Dart.
- [x] 4.2 Implement the playback controller for track replacement, buffering, position/duration clamping, pause/resume, completed-track replay, retry, and safe errors, and verify unit tests cover every playback and failure scenario from the spec.

## 5. Android and Web UI

- [x] 5.1 Build the first-run/settings flow with URL validation feedback and server switching, and verify widget tests cover missing configuration, invalid submission, persisted configuration, and edit/save behavior.
- [x] 5.2 Build the responsive library/search interface with metadata, duration, lazy cover images, placeholders, paging, loading, empty, failure, and retry states, and verify widget tests at phone and desktop widths have no overflow and exercise each state.
- [x] 5.3 Build a persistent now-playing panel with selected metadata, play/pause/replay, buffering/error/retry indicators, elapsed/total time, and seek controls, and verify widget tests drive a fake player through selection, playback, seeking, replacement, completion, and error recovery.
- [x] 5.4 Configure Android Internet/private-LAN HTTP access and web application metadata, then verify a web release build completes and an Android debug APK builds when the Android SDK is available.

## 6. Quality and Handoff

- [x] 6.1 Add a Flutter CI job that uses the pinned SDK, enforces formatting, runs static analysis and tests, and builds the web release; verify the workflow syntax and run the same commands locally.
- [x] 6.2 Update the repository README with the new structure, Flutter prerequisites, API URL configuration, CORS allow-list examples, web run/build commands, Android APK build/install steps, and private-network security constraints; verify every documented configuration name matches code and `.env.example`.
- [x] 6.3 Run strict OpenSpec validation, the full available backend suite, all Flutter tests/analyzer checks, and web/Android build checks, then record any environment-dependent verification explicitly before marking the change complete.

## Verification record (2026-08-23)

- Flutter 3.44.7 stable / Dart 3.12.2 installed from the official Windows archive; SHA-256 matched `327B89C2FF612418C1D756EFC9636D7811C50E4B50A916D07BC3BDC317BA25E5`.
- `flutter doctor -v`: Chrome/web and network checks passed. Android SDK 35.0.1 was detected, but Android command-line tools are missing and license status is unknown.
- `flutter pub get --enforce-lockfile`: passed.
- `dart format --output=none --set-exit-if-changed .`: passed for 23 Dart files.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub`: 34 tests passed.
- `flutter build web --release --no-pub`: passed; output created at `client/build/web`.
- `flutter build apk --debug --no-pub`: attempted, but no APK was produced before the 10-minute verification limit on this incomplete Android toolchain. Re-run after installing Android command-line tools and accepting SDK licenses.
- Full available backend suite: 77 passed, 17 PostgreSQL-dependent tests skipped because `ARION_TEST_DATABASE_URL` was not configured.
- GitHub Actions workflow YAML parsed successfully and contains `backend-tests`, `flutter-client`, and `backend-image` jobs.
- `openspec validate add-flutter-client --type change --strict --no-interactive`: passed.
