## ADDED Requirements

### Requirement: Android background playback lifetime
The Android client SHALL keep the active playback session running through an Android media playback service while audio is playing and the owner backgrounds the activity or locks the display. Backgrounding or dismissing the activity SHALL NOT by itself clear the session queue, current entry, position, or repeat mode, while a terminated playback service or client process SHALL retain the existing fresh-session behavior on the next launch.

#### Scenario: Continue after switching apps
- **WHEN** audio is playing and the owner switches from Arion to another application
- **THEN** the selected audio continues and the current queue entry and position remain active

#### Scenario: Continue with the display locked
- **WHEN** audio is playing and the owner locks the Android display
- **THEN** playback continues through the media service without requiring the Flutter activity to remain visible

#### Scenario: Preserve a paused background session
- **WHEN** the owner pauses playback from an Android system media surface while the Arion activity is not visible
- **THEN** the current entry, position, queue, and repeat mode remain available for a later resume in the same live playback session

#### Scenario: Start fresh after process termination
- **WHEN** Android or the owner fully terminates the Arion playback process and later launches the client again
- **THEN** the client starts with an empty session queue and repeat off while preserving the configured server setting

### Requirement: Android system media presentation
The Android client SHALL publish the active track's title, artist, album, duration, available cover art, queue position, playback position, processing state, play-or-pause state, and repeat mode through its media session. Android notification, lock-screen, headset, Bluetooth, wearable, or automotive surfaces MAY choose which published fields and controls they render.

#### Scenario: Present an active track
- **WHEN** a queue entry becomes the successfully loaded active source
- **THEN** Android receives metadata and playback state for that same queue occurrence without exposing its private storage reference or server credential

#### Scenario: Update playback progress
- **WHEN** the active source plays, pauses, buffers, seeks, completes, fails, or changes
- **THEN** the Android media session reflects the authoritative controller state and does not continue presenting a superseded source as active

#### Scenario: Present missing artwork safely
- **WHEN** the active track has no cover or its cover cannot be loaded
- **THEN** system media controls remain usable with a stable fallback presentation

#### Scenario: Report repeat mode without a dedicated button
- **WHEN** Arion's repeat mode changes
- **THEN** the media session publishes the new mode even when the current Android system surface does not render a repeat control

### Requirement: Unified in-app and system media commands
The Android client SHALL route system play, pause, seek, seek-forward, seek-backward, previous, next, and supported repeat-mode commands through the same queue-aware playback authority used by the in-app controls. Command availability and outcomes SHALL preserve the existing queue boundaries, three-second previous behavior, repeat behavior, failure handling, and source-generation safety.

#### Scenario: Pause and resume outside the app
- **WHEN** the owner activates pause and then play from an Android system media surface
- **THEN** the same active source pauses and resumes from its current position and both system and in-app state remain synchronized

#### Scenario: Seek outside the app
- **WHEN** the owner seeks or activates a supported forward or backward seek action from Android system controls
- **THEN** Arion clamps the target to the active track duration, seeks the active source, and publishes the resulting position

#### Scenario: Navigate the queue outside the app
- **WHEN** the owner activates previous or next from Android system controls
- **THEN** Arion applies the same enabled state, queue target, restart threshold, and repeat-all wrapping rules as the corresponding in-app action

#### Scenario: Change repeat mode through a supported system action
- **WHEN** an Android controller supplies a supported repeat-mode command
- **THEN** Arion updates the session repeat mode without restarting or replacing the current source

#### Scenario: Reject an unavailable system action
- **WHEN** an external media command has no valid target because playback is loading, failed, empty, or at a disabled queue boundary
- **THEN** Arion leaves the authoritative playback and queue state unchanged and publishes the currently valid controls

### Requirement: Android audio interruption safety
The Android client SHALL participate in the platform audio session and SHALL prevent audio from continuing unexpectedly after focus loss or an output route becomes noisy. Automatic resume after a transient interruption SHALL occur only when playback was active before the interruption and Android grants focus again; disconnecting a private output SHALL require an explicit owner resume.

#### Scenario: Handle a transient interruption
- **WHEN** a phone call or another transient audio-focus event interrupts active playback
- **THEN** Arion pauses or follows the platform-requested focus behavior and resumes only after focus returns when playback had been active before the interruption

#### Scenario: Preserve an owner pause during interruption
- **WHEN** playback was already paused before a transient interruption
- **THEN** focus restoration does not start playback

#### Scenario: Disconnect headphones or Bluetooth output
- **WHEN** a private audio output disconnects while Arion is playing
- **THEN** Arion pauses and does not automatically continue through the device speaker

### Requirement: Platform-isolated background integration
Android background integration SHALL NOT change browser playback behavior, require a new backend endpoint, or weaken private-server configuration. Replacing the configured Arion server SHALL stop the prior Android playback session before the client creates a fresh empty session for the replacement server.

#### Scenario: Use the browser client
- **WHEN** Arion runs as a web client
- **THEN** existing browser playback, queue, repeat, source replacement, and session-lifetime behavior remains available without an Android service

#### Scenario: Replace the configured server on Android
- **WHEN** the owner saves a different Arion server while an Android playback session exists
- **THEN** the client stops the old source and media session state before starting an empty queue with repeat off for the replacement server
