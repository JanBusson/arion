## MODIFIED Requirements

### Requirement: Playback failure recovery
The client SHALL surface audio load and playback failures without crashing, bound the time spent waiting for a source transition, keep now-playing state consistent with the source that is actually active, and let the owner retry the requested track. On Android, the client SHALL maintain a bounded forward buffer and SHALL automatically make a bounded series of recovery attempts after an unexpected playback interruption. Automatic recovery SHALL retain the same queue entry, restore the last confirmed playback position, expose a non-terminal reconnecting state, and resume only if playback was active when the interruption occurred. The client SHALL cancel recovery for an obsolete source when the owner pauses, selects another queue entry, changes the configured server, or ends the playback session. It SHALL NOT continue presenting old audio as though a failed or stalled replacement had succeeded.

#### Scenario: Buffered Android playback bridges a brief outage
- **WHEN** Android playback has buffered audio ahead and network connectivity is interrupted for less time than the available buffer
- **THEN** the selected track continues playing from buffered media without owner action

#### Scenario: Active Android playback reconnects after an interruption
- **WHEN** active Android playback encounters an unexpected recoverable error and the source becomes reachable within the bounded recovery window
- **THEN** the client reports that playback is reconnecting, reloads the same queue entry, restores the last confirmed position, and resumes playback without owner action

#### Scenario: Paused playback does not auto-resume
- **WHEN** an interruption or recovery attempt occurs while the selected track is paused or the owner pauses during recovery
- **THEN** the client cancels automatic recovery and does not start playback without a later owner action

#### Scenario: Obsolete recovery cannot replace a newer source
- **WHEN** the owner selects another queue entry, changes the configured server, or ends the playback session while recovery is pending
- **THEN** pending work for the interrupted source is cancelled or ignored and cannot change the new playback state

#### Scenario: Automatic recovery is exhausted
- **WHEN** the interrupted source remains unavailable through all bounded recovery attempts
- **THEN** the client leaves the busy and reconnecting states, displays a non-sensitive playback error for the selected track, keeps active-source state coherent, and offers a manual retry action

#### Scenario: Audio cannot be loaded
- **WHEN** the audio endpoint is unavailable, rejects the request, or returns media the platform cannot decode before playback has become active
- **THEN** the client stops its busy state, displays a non-sensitive playback error for the requested track, keeps active-source state coherent, and offers a retry action

#### Scenario: Source replacement stalls
- **WHEN** loading a requested replacement source does not complete within the configured transition timeout
- **THEN** the client stops waiting, displays a non-sensitive retryable error, and does not identify the requested track as the source of any audio that remains active

#### Scenario: Retry a failed replacement
- **WHEN** the owner retries the most recently requested track after its source failed, timed out, or exhausted automatic recovery
- **THEN** the client attempts a fresh source transition and makes that track active only if the new attempt succeeds

#### Scenario: Browser playback behavior remains unchanged
- **WHEN** playback runs in a web browser
- **THEN** the client retains the existing browser buffering and manual failure-retry behavior without Android-specific automatic recovery
