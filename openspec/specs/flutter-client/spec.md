# Flutter Client Specification

## Purpose

Defines the owner-facing Android and browser experience for connecting to a private Arion server, finding catalog tracks, and playing or seeking their stored audio.

## Requirements

### Requirement: Private server configuration
The client SHALL let the owner enter an absolute HTTP or HTTPS Arion API base URL, validate it before use, persist the accepted value on the device, and let the owner change it later. The client SHALL NOT embed a production server address or credential in source code.

#### Scenario: Configure a server for the first time
- **WHEN** the owner opens the client without a saved server URL
- **THEN** the client requests a server URL and does not attempt catalog or audio requests until a valid value is saved

#### Scenario: Reject an invalid server URL
- **WHEN** the owner submits a relative URL or a URL whose scheme is neither HTTP nor HTTPS
- **THEN** the client explains that the address is invalid and leaves the saved configuration unchanged

#### Scenario: Reuse and change a saved server
- **WHEN** the owner reopens the client or edits the server setting
- **THEN** the client reuses the persisted valid URL or switches subsequent catalog, cover, and audio requests to the newly saved URL

### Requirement: Track library browsing
The client SHALL retrieve the versioned track-list API, show each track's title, artist, album, and duration, and incrementally request additional pages without duplicating or discarding already loaded tracks. It SHALL distinguish initial loading, an empty library, available results, and a retryable request failure.

#### Scenario: Browse a populated library
- **WHEN** the server returns one or more tracks
- **THEN** the client displays their identifying metadata and provides access to further pages while the reported total exceeds the loaded count

#### Scenario: Browse an empty library
- **WHEN** the server reports a total of zero tracks
- **THEN** the client displays a clear empty-library state rather than an indefinite loading indicator

#### Scenario: Retry a failed library request
- **WHEN** a catalog request fails because the server is unavailable, times out, or returns an invalid response
- **THEN** the client displays a non-sensitive error and lets the owner retry without restarting the application

### Requirement: Track search
The client SHALL let the owner submit a text search using the track-list API's `q` parameter, display only the latest submitted query's result set, and return to the unfiltered library when the search text is cleared.

#### Scenario: Search the catalog
- **WHEN** the owner submits non-blank search text
- **THEN** the client requests the first result page for that query and displays its results and empty-result state as applicable

#### Scenario: Ignore an obsolete response
- **WHEN** an older search request completes after a newer search has been submitted
- **THEN** the client retains the newer query's state and does not replace it with stale results

#### Scenario: Clear a search
- **WHEN** the owner clears the active search text
- **THEN** the client returns to the first page of the unfiltered library

### Requirement: Cover presentation
The client SHALL request cover art only for tracks that report `has_cover`, and SHALL show a stable placeholder when no cover exists or an image request cannot be displayed.

#### Scenario: Display available cover art
- **WHEN** a visible track reports embedded cover art and the cover endpoint succeeds
- **THEN** the client displays the returned cover without exposing its storage location

#### Scenario: Fall back from missing or failed artwork
- **WHEN** a track has no cover or its cover request fails
- **THEN** the client displays a consistent placeholder while keeping the track usable

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

### Requirement: Android and browser operation
The same client codebase SHALL provide usable layouts on narrow Android screens and wider browser windows. Android builds SHALL be able to reach explicitly configured private HTTP servers, and browser API access SHALL be limited to server origins explicitly configured by the operator.

#### Scenario: Use a narrow screen
- **WHEN** the client runs at a phone-sized width
- **THEN** library, settings, and playback controls remain visible without horizontal overflow

#### Scenario: Use a wide browser window
- **WHEN** the client runs at a desktop-browser width
- **THEN** the library uses the available space while keeping controls readable and reachable

#### Scenario: Access from an allowed browser origin
- **WHEN** the web client is served from an origin in the server's configured allow-list
- **THEN** catalog, cover, and ranged audio requests are permitted with the response headers needed for playback

#### Scenario: Reject an unconfigured browser origin
- **WHEN** a browser origin not present in the server's allow-list attempts cross-origin API access
- **THEN** the server omits permission for that origin
