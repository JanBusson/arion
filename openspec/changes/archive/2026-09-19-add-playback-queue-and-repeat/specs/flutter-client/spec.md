## ADDED Requirements

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
