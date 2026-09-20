## MODIFIED Requirements

### Requirement: Single-track playback and seeking
The client SHALL start the selected track from its audio endpoint, expose play, pause, replay, elapsed time, total time, buffering state, and seeking controls, and keep the visible now-playing metadata, duration, position, and playback state synchronized with the audio source that successfully loaded. Selecting a different track SHALL replace the current audio source on Android and supported browsers. A pending source replacement SHALL NOT present the requested track as actively playing until its source has loaded, and only the newest pending selection SHALL be allowed to become active.

#### Scenario: Start a track
- **WHEN** the owner selects play for a catalog track
- **THEN** the client loads that track's audio URL and identifies it as now playing when the source is ready before beginning playback

#### Scenario: Pause and resume
- **WHEN** the owner pauses and then resumes the selected track
- **THEN** playback stops at and continues from the current position while the controls reflect the player state

#### Scenario: Seek within a track
- **WHEN** the owner chooses a valid position within the selected track's duration
- **THEN** the client requests playback from that position and updates the elapsed-time display as playback state changes

#### Scenario: Replay completed audio
- **WHEN** playback reaches the end and the owner activates the playback control
- **THEN** the client seeks to the beginning and plays the selected track again

#### Scenario: Replace the selected track
- **WHEN** the owner starts a different track while one is selected
- **THEN** the client stops presenting or playing the old source as the new selection, resets source-specific position and duration state, requests the different track's audio URL, and synchronizes now-playing state with that source after it loads

#### Scenario: Replace a paused track
- **WHEN** the owner starts a different track while the current track is paused
- **THEN** the client replaces the paused source and begins the different track without resuming audio from the old source

#### Scenario: Resolve rapid selections
- **WHEN** the owner selects multiple tracks before earlier source transitions finish
- **THEN** only the most recently selected track can become active and events or completions from older transitions cannot overwrite its state

### Requirement: Playback failure recovery
The client SHALL surface audio load and playback failures without crashing, bound the time spent waiting for a source transition, keep now-playing state consistent with the source that is actually active, and let the owner retry the requested track. It SHALL NOT continue presenting old audio as though a failed or stalled replacement had succeeded.

#### Scenario: Audio cannot be loaded
- **WHEN** the audio endpoint is unavailable, rejects the request, or returns media the platform cannot decode
- **THEN** the client stops its busy state, displays a non-sensitive playback error for the requested track, keeps active-source state coherent, and offers a retry action

#### Scenario: Source replacement stalls
- **WHEN** loading a requested replacement source does not complete within the configured transition timeout
- **THEN** the client stops waiting, displays a non-sensitive retryable error, and does not identify the requested track as the source of any audio that remains active

#### Scenario: Retry a failed replacement
- **WHEN** the owner retries the most recently requested track after its source failed or timed out
- **THEN** the client attempts a fresh source transition and makes that track active only if the new attempt succeeds
