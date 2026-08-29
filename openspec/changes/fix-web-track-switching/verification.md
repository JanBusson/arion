# Verification Evidence

Verification performed on 2026-08-27 and 2026-08-29.

## Automated client checks

- `dart format lib test`: 28 files checked, no formatting changes required.
- `flutter analyze`: completed with no issues.
- `flutter test`: all 62 Dart VM and widget tests passed.
- `sh scripts/verify_web_track_switching.sh`: all three Chrome tests passed. The fixture observed distinct `Range: bytes=0-1023` requests for both synthetic sources while replacing a playing source, replacing a paused source, and superseding a delayed source rapidly.

## Build and container checks

- `flutter build web --release --no-web-resources-cdn`: completed successfully with Flutter 3.44.7.
- Production image `arion-web-track-fix:20260827` built successfully with digest `sha256:9381e46aa79e2a5cf6f3592d3260441d3403ee94c0f0c7528e1146661dffa2e4`.
- The image started successfully in isolated Compose project `arion-web-fix-verify`, served `/index.html`, and the temporary project was removed afterward.
- A version-matched Android toolchain was prepared and `flutter doctor -v` confirmed Flutter 3.44.7, Dart 3.12.2, Android SDK 36, and accepted licenses. The release APK build was stopped at the owner's request so the web version could be completed first; tasks 2.3 and 5.2 therefore remain open.

## Private deployment checks

- The previous live web image is retained as `arion-web-track-fix-rollback:20260829`.
- Only the `web` service was recreated. It is healthy at `192.168.178.110:8080` and runs image digest `sha256:9381e46aa79e2a5cf6f3592d3260441d3403ee94c0f0c7528e1146661dffa2e4`.
- Live API Range checks returned `206 Partial Content` and `Content-Length: 1024` for two authorized tracks:
  - Rocket Man: `Content-Range: bytes 0-1023/4556218`
  - I Don't Like: `Content-Range: bytes 0-1023/4766196`
- The synchronized server source has a pre-deployment backup at `/home/deploy/arion/.deployment-backups/20260829-fix-web-track-switching`.
- API access logging is disabled, so no per-request access-log lines were available. Automated Chrome verification captured both ranged request identities instead.
- No controllable browser was connected to the Codex session. The final audible live A-to-B, B-to-A, and paused replacement check remains pending owner confirmation; task 5.3 remains open until then.
