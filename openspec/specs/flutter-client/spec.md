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

### Requirement: Opt-in fallback after an empty local search
When a submitted non-blank local catalog search returns no tracks, the client SHALL display an explicit action to search YouTube using that query. The client SHALL NOT contact YouTube discovery automatically, while the owner types, or when local results exist.

#### Scenario: Offer external discovery after a local miss
- **WHEN** the latest submitted local search completes successfully with zero tracks
- **THEN** the client offers an explicit YouTube search action containing the submitted query

#### Scenario: Keep local results local
- **WHEN** a local search returns one or more tracks
- **THEN** the client displays those tracks without initiating or prompting an automatic external search

### Requirement: Candidate review
The client SHALL display returned candidates as distinguishable choices containing title, channel, duration when available, thumbnail, and an action that opens the canonical YouTube page for review. The client SHALL not label a candidate as the correct song or select one automatically.

#### Scenario: Review several candidates
- **WHEN** YouTube discovery returns candidates
- **THEN** the client displays each candidate's identifying information and requires the owner to select one explicitly

#### Scenario: Discovery returns no candidates
- **WHEN** YouTube discovery completes with no eligible candidates
- **THEN** the client shows a no-candidates state and allows the owner to revise the query without changing the local catalog

### Requirement: Confirm experimental acquisition
Before creating a job, the client SHALL identify the selected candidate, explain that acquisition is experimental and may be restricted by provider terms, and require an unchecked-by-default authorization acknowledgement plus a separate confirmation action.

#### Scenario: Confirm an acquisition
- **WHEN** the owner selects a candidate, checks the authorization acknowledgement, and confirms
- **THEN** the client creates one acquisition job and displays its progress

#### Scenario: Prevent accidental confirmation
- **WHEN** the acknowledgement is not checked
- **THEN** the client does not enable the final acquisition action

### Requirement: Acquisition progress and completion
The client SHALL poll the durable job representation while it is active, render its current phase, stop polling at a terminal state, and prevent duplicate submissions while the selected candidate has an active job. On completion it SHALL refresh the local catalog, reveal the resulting track, and offer normal playback without automatically starting audio.

#### Scenario: Complete and play an acquired track
- **WHEN** the observed job reaches `completed`
- **THEN** the client refreshes the catalog and provides the normal play action for the resulting track

#### Scenario: Show a sanitized failure
- **WHEN** the observed job reaches `failed`
- **THEN** the client displays the stable failure message and offers a safe retry or return-to-search action without exposing command output or server paths

#### Scenario: Resume observing a durable job
- **WHEN** the client is restarted or temporarily disconnected while a remembered job remains active
- **THEN** the client retrieves the persisted job and resumes progress display without creating another job

### Requirement: Disabled feature experience
The client SHALL treat the disabled acquisition response as an unavailable optional feature and SHALL keep local library, search, settings, and playback usable.

#### Scenario: Operator has disabled acquisition
- **WHEN** the owner attempts external discovery and the API reports that acquisition is disabled
- **THEN** the client explains that the server feature is unavailable and retains the current local search state

### Requirement: Music-first external discovery mode selection
The client SHALL display two mutually exclusive external-discovery controls, `Music` and `All`, beside the library search control. `Music` SHALL be selected when the client starts and the selected mode SHALL remain active for subsequent searches during that client session unless the owner changes it. The selector SHALL affect only explicit external discovery and SHALL NOT filter the local catalog, contact an external provider while typing, or start discovery merely because the selection changed.

#### Scenario: Start with music selected
- **WHEN** the owner starts the client and submits a local catalog search
- **THEN** `Music` is selected while the local catalog request remains an ordinary unfiltered-by-mode search

#### Scenario: Choose broad discovery
- **WHEN** the owner selects `All` and explicitly starts external discovery after an empty local result
- **THEN** the client requests `all` discovery for the latest submitted query

#### Scenario: Change mode without searching
- **WHEN** the owner changes between `Music` and `All`
- **THEN** the client makes no external request until the owner activates the discovery action

### Requirement: Mode-consistent candidate review
The client SHALL label the explicit discovery action for the selected mode, send that mode in the candidate request, and display only candidates returned for the current query and mode. Changing the mode after candidates have loaded SHALL clear those candidates and require another explicit discovery action. Music candidates SHALL present their artist display text as the creator identity while retaining the existing title, duration, thumbnail, canonical-page review, selection, and authorization controls.

#### Scenario: Review music candidates
- **WHEN** `Music` discovery returns song candidates
- **THEN** the client identifies the action and result state as music discovery and shows each song title and artist without preselecting a candidate

#### Scenario: Switch away from displayed candidates
- **WHEN** candidates are visible and the owner changes the discovery mode
- **THEN** the client removes the old-mode candidates and does not search the newly selected mode automatically

#### Scenario: Fit the selector on supported layouts
- **WHEN** the mode selector is shown on a narrow Android layout or a wider browser layout
- **THEN** both choices and the search control remain readable and operable without horizontal overflow

### Requirement: Session playback queue
The client SHALL maintain an ordered playback queue for the current configured-server session, with at most one current entry and zero or more upcoming entries. Each queued occurrence SHALL retain its own identity so the same track can appear more than once. The default play action for a catalog track SHALL replace the existing queue with that track and start it, while separate actions SHALL let the owner insert a track immediately after the current entry or append it to the end.

#### Scenario: Play a track immediately
- **WHEN** the owner uses the default play action for a catalog track while another queue exists
- **THEN** the client replaces the queue with one entry for the selected track and starts that entry

#### Scenario: Insert a track to play next
- **WHEN** the owner chooses to play a catalog track next while another track is current
- **THEN** the client inserts a new entry directly before every previously upcoming entry without interrupting the current track

#### Scenario: Append a track
- **WHEN** the owner adds a catalog track to a non-empty queue
- **THEN** the client appends a new entry after all existing upcoming entries without interrupting the current track

#### Scenario: Queue a track with no current entry
- **WHEN** the owner chooses play-next or append while the queue is empty
- **THEN** the client makes that track current and starts it

#### Scenario: Queue the same track more than once
- **WHEN** the owner adds a track that is already represented in the queue
- **THEN** the client retains both occurrences as independently ordered entries

### Requirement: Manual queue navigation
The client SHALL expose previous and next controls whose availability reflects the queue boundary. Next SHALL select the following entry and previous SHALL restart the current entry when playback has progressed beyond three seconds, otherwise previous SHALL select the preceding entry when one exists. Repeat-current SHALL NOT intercept manual navigation; repeat-all SHALL allow manual navigation to wrap between the first and last entries.

#### Scenario: Advance manually
- **WHEN** an upcoming entry exists and the owner activates next
- **THEN** the client selects and starts the first upcoming entry

#### Scenario: Restart the current track
- **WHEN** the current track has progressed beyond three seconds and the owner activates previous
- **THEN** the client seeks the current entry to its beginning without changing the queue position

#### Scenario: Return to the preceding track
- **WHEN** the current track is at or before three seconds, a preceding entry exists, and the owner activates previous
- **THEN** the client selects and starts the preceding entry from its beginning

#### Scenario: Reach a boundary without repeat-all
- **WHEN** the owner is at a queue boundary and the corresponding previous or next action has no target while repeat-all is not active
- **THEN** the client disables that navigation action and leaves the current entry unchanged

#### Scenario: Navigate a repeat-current queue manually
- **WHEN** repeat-current is active and the owner activates an available previous or next action
- **THEN** the client follows the queue order rather than replaying the current entry

#### Scenario: Wrap manual navigation with repeat-all
- **WHEN** repeat-all is active and the owner activates next on the final entry or previous on the first entry at or before three seconds
- **THEN** the client selects and starts the entry at the opposite boundary

### Requirement: Automatic queue advancement and repeat modes
The client SHALL automatically resolve natural track completion according to one of three visibly selectable modes: repeat off, repeat all, or repeat current. Repeat SHALL default to off for a new client session, and changing the mode SHALL NOT interrupt or restart the current track.

#### Scenario: Advance after completion with repeat off
- **WHEN** repeat is off and the current track completes with an upcoming entry available
- **THEN** the client selects and starts the next entry

#### Scenario: Stop at the final entry with repeat off
- **WHEN** repeat is off and the final queue entry completes
- **THEN** the client leaves that entry selected in a completed, non-playing state

#### Scenario: Wrap after completion with repeat all
- **WHEN** repeat-all is active and the final queue entry completes
- **THEN** the client selects and starts the first entry in the queue

#### Scenario: Continue within the queue with repeat all
- **WHEN** repeat-all is active and a non-final queue entry completes
- **THEN** the client selects and starts the following entry

#### Scenario: Replay after completion with repeat current
- **WHEN** repeat-current is active and the current track completes
- **THEN** the client restarts and plays the same queue entry from the beginning

#### Scenario: Change repeat mode during playback
- **WHEN** the owner selects a different repeat mode while a track is playing or paused
- **THEN** the client displays the new mode and preserves the current source, position, and play-or-pause state

### Requirement: Queue inspection and editing
The client SHALL provide a queue view that identifies the current track and displays upcoming entries in playback order. The owner SHALL be able to remove or reorder upcoming entries without interrupting the current source, and the client SHALL update navigation availability immediately after each edit.

#### Scenario: Inspect the queue
- **WHEN** the owner opens the queue view
- **THEN** the client identifies the current track and lists every upcoming occurrence in playback order

#### Scenario: Reorder upcoming tracks
- **WHEN** the owner moves an upcoming entry to another upcoming position
- **THEN** the client preserves the current track and uses the revised order for subsequent manual and automatic advancement

#### Scenario: Remove an upcoming track
- **WHEN** the owner removes an upcoming entry
- **THEN** the client preserves the current track, removes only the selected occurrence, and advances through the remaining order

#### Scenario: Edit duplicate entries
- **WHEN** the queue contains repeated occurrences of one track and the owner moves or removes one occurrence
- **THEN** the client changes only that selected queue entry

### Requirement: Queue-aware playback failure recovery
The client SHALL preserve queue order and repeat mode when loading or playing the current entry fails or times out. It SHALL identify the failed entry with a non-sensitive retryable error and SHALL allow the owner to retry it or navigate to another available entry. Stale events, errors, or completion signals from superseded sources SHALL NOT change the current queue position or trigger additional advancement.

#### Scenario: Current queue entry fails
- **WHEN** the current entry cannot load, times out, or encounters a playback error
- **THEN** the client keeps that entry current, preserves the queue and repeat mode, stops the busy state, and offers retry

#### Scenario: Skip a failed queue entry
- **WHEN** the current entry has failed and an upcoming entry is available
- **THEN** the owner can activate next and the client attempts to start that upcoming entry without discarding the rest of the queue

#### Scenario: Retry a failed queue entry
- **WHEN** the owner retries the failed current entry
- **THEN** the client performs a fresh source transition for the same queue occurrence and leaves the surrounding queue unchanged

#### Scenario: Ignore completion from a superseded source
- **WHEN** an older source emits completion after a newer manual action or automatic transition has selected another entry
- **THEN** the client leaves the newer queue position and source state unchanged and does not advance again

### Requirement: Queue session lifetime and supported layouts
The client SHALL keep the queue and repeat mode only in memory for the current configured-server session. Replacing the configured Arion server or ending the client session SHALL discard that state. Queue actions, navigation, repeat selection, and queue editing SHALL remain usable without horizontal overflow on supported narrow Android and wide browser layouts.

#### Scenario: Change the configured server
- **WHEN** the owner saves a different Arion server URL
- **THEN** the client discards the previous server's queue and repeat mode and starts the replacement session with an empty queue and repeat off

#### Scenario: Restart the client
- **WHEN** the owner closes and reopens the client with the same saved server URL
- **THEN** the client restores the server setting but starts with an empty queue and repeat off

#### Scenario: Use queue controls on a narrow screen
- **WHEN** the client runs at a phone-sized width and the owner opens playback or queue controls
- **THEN** all navigation, repeat, add, remove, and reorder actions remain reachable without horizontal overflow

#### Scenario: Use queue controls in a wide browser
- **WHEN** the client runs at a desktop-browser width
- **THEN** the queue and playback controls use the available width while remaining readable and reachable
