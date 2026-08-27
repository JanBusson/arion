## Purpose

Defines an explicitly enabled experimental workflow for finding a YouTube candidate, approving its acquisition, and tracking a bounded background job until it becomes a normal Arion track.

## ADDED Requirements

### Requirement: Operator-controlled experimental feature
The system SHALL disable YouTube discovery and acquisition by default. When disabled, it SHALL reject discovery and job-creation requests with status `503` and a stable `youtube_acquisition_disabled` error without affecting local catalog, upload, or streaming behavior.

#### Scenario: Use local Arion while acquisition is disabled
- **WHEN** the operator has not enabled YouTube acquisition
- **THEN** local search, upload import, and audio streaming remain available while YouTube acquisition requests report that the feature is disabled

### Requirement: Explicit YouTube candidate discovery
The system SHALL expose an authenticated-by-network-boundary owner operation that accepts a trimmed, non-empty search query and returns at most five individual, non-live YouTube video candidates. Each candidate SHALL include an opaque candidate identifier, YouTube video identifier, title, channel name, duration when available, thumbnail URL, and canonical YouTube page URL. Discovery SHALL never create an acquisition job or store media.

#### Scenario: Discover candidates after a local miss
- **WHEN** the owner explicitly submits a non-empty YouTube search query while the feature is enabled
- **THEN** the system returns up to five reviewable video candidates without downloading their media

#### Scenario: Reject an invalid discovery query
- **WHEN** the owner submits an empty or whitespace-only YouTube search query
- **THEN** the system returns status `422` and does not contact the external provider

#### Scenario: Discovery provider is unavailable
- **WHEN** YouTube discovery times out or returns an unusable response
- **THEN** the system returns a stable provider-unavailable error without changing the catalog or creating a job

### Requirement: Explicit approval and authorization acknowledgement
The system SHALL create an acquisition job only after the owner selects a candidate returned by discovery and affirmatively acknowledges responsibility for having permission to acquire it. The system SHALL record the acknowledgement time and candidate provenance with the job. The acknowledgement SHALL NOT be represented as granting rights or overriding provider terms.

#### Scenario: Approve a discovered candidate
- **WHEN** the owner submits a valid candidate identifier with affirmative authorization acknowledgement
- **THEN** the system returns status `202` with a durable queued job representation

#### Scenario: Reject missing acknowledgement
- **WHEN** the owner requests acquisition without affirmative authorization acknowledgement
- **THEN** the system returns status `422` and creates no job

#### Scenario: Reject an expired or altered candidate
- **WHEN** the owner submits a candidate identifier that is expired, unknown, or fails integrity validation
- **THEN** the system returns status `409` and creates no job

### Requirement: Durable acquisition job lifecycle
The system SHALL persist each acquisition job before work starts and expose its identifier, current state, phase progress, timestamps, selected candidate summary, nullable resulting track identifier, and a stable sanitized failure code and message. Job states SHALL be `queued`, `downloading`, `processing`, `completed`, `failed`, or `cancelled`. A server or worker restart SHALL not lose a queued job, and interrupted active work SHALL be safely retried or failed without creating a partial catalog entry.

#### Scenario: Poll an active job
- **WHEN** the owner retrieves a queued, downloading, or processing job
- **THEN** the system returns its current persisted state and phase progress

#### Scenario: Complete an acquisition job
- **WHEN** acquisition and the normal import workflow succeed
- **THEN** the job enters `completed` with the created track identifier and that track is available through the normal catalog and audio endpoints

#### Scenario: Recover after worker interruption
- **WHEN** a worker stops while a job is downloading or processing
- **THEN** the system reclaims or fails the expired work deterministically, removes abandoned staged output, and creates at most one catalog track

### Requirement: Bounded and restricted acquisition
The system SHALL accept only the selected individual public YouTube video identifier and SHALL construct the provider target server-side. It SHALL use fixed operator-controlled acquisition behavior and enforce configured limits for search time, download time, media duration, output bytes, free disk space, retry count, and concurrent jobs. It SHALL reject playlists, live or upcoming streams, private or authentication-gated media, cookies, arbitrary URLs, user-provided downloader options, and attempts to bypass access controls.

#### Scenario: Reject an ineligible candidate
- **WHEN** the selected candidate is a playlist, live stream, exceeds a configured bound, requires authentication, or is otherwise outside the allowed acquisition profile
- **THEN** the job fails with a stable eligibility error and leaves no durable media or catalog entry

#### Scenario: Stop an oversized acquisition
- **WHEN** downloaded output exceeds the configured maximum or required free-space reserve
- **THEN** acquisition stops, the job fails with a stable resource-limit error, and staged output is removed

#### Scenario: Prevent command injection
- **WHEN** a query or candidate metadata contains shell metacharacters or downloader-looking options
- **THEN** the values are treated only as data and cannot alter the fixed acquisition command or write outside staging storage

### Requirement: Duplicate acquisition handling
The system SHALL identify YouTube provenance by video identifier and retain content-based duplicate protection. If the selected video has already produced a catalog track, the system SHALL return that existing track rather than download another copy. Concurrent jobs that resolve to identical audio SHALL create at most one durable audio object and catalog track.

#### Scenario: Select an already imported YouTube video
- **WHEN** the owner approves a candidate whose YouTube video identifier already maps to a catalog track
- **THEN** the system completes without downloading and returns the existing track identifier

#### Scenario: Different videos contain identical audio
- **WHEN** two acquisition jobs produce byte-identical supported audio
- **THEN** content-based duplicate protection retains one catalog track and both jobs resolve deterministically without orphaned durable objects

### Requirement: Sanitized observability and retention
The system SHALL emit structured phase, duration, output-size, retry, and failure-code events keyed by job identifier. It SHALL NOT log downloader URLs containing credentials, cookies, raw command lines, secrets, filesystem paths, or unbounded external error output. It SHALL retain completed and failed job records for an operator-configurable period and remove expired candidate and staging data.

#### Scenario: Diagnose a failed job
- **WHEN** acquisition fails
- **THEN** operators can correlate sanitized structured events by job identifier while API clients receive a stable non-sensitive error
