## MODIFIED Requirements

### Requirement: Track library browsing
The client SHALL retrieve the versioned track-list API, show each track's title, artist, album, and duration, and incrementally request additional pages without duplicating or discarding already loaded tracks. It SHALL distinguish initial loading, an empty library, available results, and a retryable request failure. On Android, when the server cannot provide the initial page and a complete catalog snapshot exists for the configured server, the client SHALL instead expose that snapshot with a visible offline or potentially stale indication and retain a retry action. Browser behavior SHALL remain online-only.

#### Scenario: Browse a populated library
- **WHEN** the server returns one or more tracks
- **THEN** the client displays their identifying metadata and provides access to further pages while the reported total exceeds the loaded count

#### Scenario: Browse an empty library
- **WHEN** the server reports a total of zero tracks
- **THEN** the client displays a clear empty-library state rather than an indefinite loading indicator

#### Scenario: Browse the saved Android catalog offline
- **WHEN** the initial Android catalog request fails and a complete snapshot matches the configured server
- **THEN** the client displays the saved tracks, identifies the view as offline or potentially stale, and lets the owner retry the server request

#### Scenario: Retry a failed library request
- **WHEN** a catalog request fails because the server is unavailable, times out, or returns an invalid response and no matching complete snapshot exists
- **THEN** the client displays a non-sensitive error and lets the owner retry without restarting the application

### Requirement: Track search
The client SHALL let the owner submit text search and display only the latest submitted query's result set. While online it SHALL use the track-list API's `q` parameter and return to the unfiltered library when search text is cleared. While Android is presenting a saved offline snapshot, it SHALL search that snapshot locally across title, artist, and album without requiring the server and SHALL return to the full saved snapshot when cleared.

#### Scenario: Search the catalog
- **WHEN** the owner submits non-blank search text while the server catalog is active
- **THEN** the client requests the first result page for that query and displays its results and empty-result state as applicable

#### Scenario: Search the offline catalog
- **WHEN** the owner submits non-blank search text while Android is presenting a saved snapshot
- **THEN** the client filters the saved snapshot by case-insensitive title, artist, or album match without a server request

#### Scenario: Ignore an obsolete response
- **WHEN** an older online search request completes after a newer search has been submitted
- **THEN** the client retains the newer query's state and does not replace it with stale results

#### Scenario: Clear a search
- **WHEN** the owner clears the active search text
- **THEN** the client returns to the first page of the online unfiltered library or the complete saved offline snapshot currently in use

### Requirement: Single-track playback and seeking
The client SHALL expose play, pause, replay, elapsed time, total time, buffering state, and seeking controls, and keep the visible now-playing metadata, duration, position, and playback state synchronized with the audio source that successfully loaded. On Android it SHALL prefer a verified offline file for the selected track and otherwise load the track's audio endpoint through the existing persistent-cache and network path; browser playback SHALL continue to use the audio endpoint. Selecting a different track SHALL replace the current audio source on Android and supported browsers. A pending source replacement SHALL NOT present the requested track as actively playing until its source has loaded, and only the newest pending selection SHALL be allowed to become active.

#### Scenario: Start an offline Android track
- **WHEN** the owner selects a track with a verified offline file on Android
- **THEN** the client loads that local source and identifies it as now playing when the source is ready before beginning playback

#### Scenario: Start a track
- **WHEN** the owner selects a track without a verified offline file
- **THEN** the client loads that track's audio URL through the supported cached or network path and identifies it as now playing when the source is ready before beginning playback

#### Scenario: Pause and resume
- **WHEN** the owner pauses and then resumes the selected track
- **THEN** playback stops at and continues from the current position while the controls reflect the player state

#### Scenario: Seek within a track
- **WHEN** the owner chooses a valid position within the selected track's duration
- **THEN** the client seeks the active local or remote source and updates the elapsed-time display as playback state changes

#### Scenario: Replay completed audio
- **WHEN** playback reaches the end and the owner activates the playback control
- **THEN** the client seeks to the beginning and plays the selected track again

#### Scenario: Replace the selected track
- **WHEN** the owner starts a different track while one is selected
- **THEN** the client stops presenting or playing the old source as the new selection, resets source-specific position and duration state, resolves the different track's eligible local or remote source, and synchronizes now-playing state after it loads

#### Scenario: Replace a paused track
- **WHEN** the owner starts a different track while the current track is paused
- **THEN** the client replaces the paused source and begins the different track without resuming audio from the old source

#### Scenario: Resolve rapid selections
- **WHEN** the owner selects multiple tracks before earlier source transitions finish
- **THEN** only the most recently selected track can become active and events or completions from older transitions cannot overwrite its state
