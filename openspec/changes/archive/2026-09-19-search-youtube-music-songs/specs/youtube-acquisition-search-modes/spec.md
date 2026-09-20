## Purpose

Defines explicit music-only and broad YouTube discovery modes so normal song searches are focused without hiding unofficial remixes or video-only releases.

## ADDED Requirements

### Requirement: Explicit discovery mode contract
The candidate-discovery operation SHALL accept exactly the modes `music` and `all`. When the mode is omitted, the server SHALL use `music`; an unsupported mode SHALL return status `422` without contacting an external provider. Both modes SHALL preserve the configured result limit of at most five candidates.

#### Scenario: Omit the discovery mode
- **WHEN** the owner requests candidate discovery without a mode
- **THEN** the system performs `music` discovery

#### Scenario: Reject an unsupported discovery mode
- **WHEN** the owner requests candidate discovery with a mode other than `music` or `all`
- **THEN** the system returns status `422` and makes no external discovery request

### Requirement: Music-mode song discovery
For `music` mode, the system SHALL query the YouTube Music Songs category and SHALL return only results classified by that source as songs. Each eligible result SHALL carry a validated YouTube video identifier, bounded title, artist display text, duration when available, generated or allow-listed thumbnail URL, canonical YouTube page URL, and an integrity-protected candidate identifier. The system SHALL NOT silently supplement empty or failed music results with broad video results.

#### Scenario: Find music-first candidates
- **WHEN** the owner explicitly requests `music` discovery for a valid query
- **THEN** the system returns up to the configured limit of YouTube Music song results without downloading media

#### Scenario: Music search has no song results
- **WHEN** `music` discovery succeeds but returns no eligible songs
- **THEN** the system returns an empty candidate list and does not run an `all` search

#### Scenario: Music provider is unavailable
- **WHEN** the YouTube Music song query times out or returns malformed or unusable data
- **THEN** the system returns a stable sanitized provider-unavailable error without changing the catalog or creating a job

### Requirement: Broad-video discovery remains available
For `all` mode, the system SHALL use the existing broad YouTube video discovery behavior so individual public video releases, including unofficial remixes, can be reviewed. It SHALL continue to exclude playlists, live or upcoming streams, malformed results, and candidates outside configured eligibility limits.

#### Scenario: Find a video-only release
- **WHEN** the owner explicitly requests `all` discovery for a valid query
- **THEN** the system returns up to the configured limit of eligible broad YouTube video candidates without downloading media

#### Scenario: Broad search excludes ineligible items
- **WHEN** broad discovery contains playlists, live items, malformed entries, or over-duration videos
- **THEN** the system omits those entries from the returned candidates

### Requirement: Mode-bound approval and common acquisition
The system SHALL bind the selected discovery mode into the integrity-protected candidate representation and SHALL not trust a client-supplied mode during job creation. Candidates from both modes SHALL be freshly revalidated by YouTube video identifier and SHALL use the same authorization acknowledgement, bounded download, normalization, import, duplicate protection, provenance, cleanup, and playback workflow.

#### Scenario: Approve a music result
- **WHEN** the owner approves a valid candidate produced by `music` discovery and acknowledges authorization
- **THEN** the system revalidates and processes that candidate through the existing acquisition workflow

#### Scenario: Alter a candidate mode
- **WHEN** a candidate identifier is altered to change its discovery mode or identity
- **THEN** the system rejects it as invalid and creates no acquisition job
