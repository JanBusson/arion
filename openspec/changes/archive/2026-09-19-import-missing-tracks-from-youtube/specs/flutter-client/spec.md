## ADDED Requirements

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
