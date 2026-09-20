## Why

Arion playback can currently be controlled only while the Flutter activity is visible, which makes listening inconvenient whenever the owner switches apps or locks the phone. Android background playback and system media controls should keep the active session usable from the notification shade, lock screen, and connected media buttons.

## What Changes

- Add an Android media playback service and media session that can continue the active Arion playback session while the app is backgrounded or the display is locked.
- Publish current track metadata, duration, position, playback state, queue position, and repeat mode to Android system media surfaces.
- Route system play, pause, seek, seek-forward/backward, previous, and next commands through the existing queue-aware playback authority so in-app and system controls stay synchronized.
- Support compatible headset, Bluetooth, lock-screen, and notification media buttons using the same command path.
- Handle Android audio focus and becoming-noisy events so calls, competing media, and disconnected output devices do not leave playback in an unsafe or misleading state.
- Preserve current web behavior by keeping Android service integration behind the client playback boundary.
- Keep queue and repeat state session-local: backgrounding or dismissing the activity does not clear it, while an ended service/process or configured-server replacement starts a fresh session under the existing lifecycle rules.
- Limit the first system surface to platform-supported media actions; report repeat mode to Android without requiring every Android/OEM media panel to render a dedicated repeat button.
- Exclude automatic APK updates, app-store distribution, production signing, media downloads, persistent queues, cross-device synchronization, and new backend APIs.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-client`: Extend Android playback with background lifetime, system media-session metadata and controls, audio-interruption handling, and synchronization with the existing session queue and repeat behavior.

## Impact

- Depends on the completed `add-playback-queue-and-repeat` change because Android media commands must reuse its queue-entry identity, navigation, completion, and repeat semantics.
- Affects Flutter application initialization, playback/controller boundaries, Android manifest and activity/service configuration, lifecycle handling, and Android-focused tests.
- Adds reviewed Flutter dependencies for media-session/background-audio integration while retaining `just_audio` as the playback engine.
- Requires a newly built and installed APK; it does not change FastAPI, PostgreSQL, audio storage, ranged streaming, the private web deployment, or browser playback behavior.
