## Purpose

Defines the persistent track catalog API used to inspect imported music, find tracks predictably, correct textual metadata, and retrieve extracted cover art without exposing storage internals.

## ADDED Requirements

### Requirement: Track representation
The API SHALL represent each track with an opaque UUID `id`, `title`, `artist`, `album`, `duration_ms`, `codec`, nullable `bitrate_kbps`, `sample_rate_hz`, `original_filename`, `has_cover`, `created_at`, and `updated_at`. It SHALL NOT expose database identifiers other than the public UUID, content digests, credentials, or server filesystem paths.

#### Scenario: Return an imported track
- **WHEN** the API returns a successfully imported track
- **THEN** the response contains every public track field and contains no internal storage path or digest

### Requirement: Track detail
The system SHALL expose `GET /api/v1/tracks/{track_id}` for a single catalog entry.

#### Scenario: Retrieve an existing track
- **WHEN** the owner requests a known track UUID
- **THEN** the system returns status `200` with its current track representation

#### Scenario: Retrieve a missing track
- **WHEN** the owner requests an unknown track UUID
- **THEN** the system returns status `404`

### Requirement: Paginated track listing
The system SHALL expose `GET /api/v1/tracks` with `limit` and `offset` parameters, default `limit` 50, maximum `limit` 100, and default `offset` 0. The response SHALL contain `items`, `total`, `limit`, and `offset`, ordered by newest creation time and then UUID for deterministic ties.

#### Scenario: List the first page
- **WHEN** the owner requests the track collection without pagination parameters
- **THEN** the system returns at most 50 newest tracks with the total matching all catalog tracks

#### Scenario: Reject invalid pagination
- **WHEN** `limit` or `offset` falls outside the documented bounds
- **THEN** the system returns status `422`

### Requirement: Case-insensitive catalog search
The collection endpoint SHALL accept an optional trimmed `q` parameter and SHALL perform case-insensitive substring matching across title, artist, and album. Search results SHALL use the same pagination envelope and deterministic order as an unfiltered listing.

#### Scenario: Search across catalog fields
- **WHEN** the owner supplies a non-empty query matching any part of a track's title, artist, or album with different letter casing
- **THEN** the matching track is included in the paginated result

#### Scenario: Treat a blank query as no filter
- **WHEN** `q` is absent, empty, or whitespace-only
- **THEN** the collection endpoint returns the normal unfiltered listing

### Requirement: Manual textual metadata correction
The system SHALL expose `PATCH /api/v1/tracks/{track_id}` for partial updates to title, artist, and album. Supplied values SHALL be trimmed and non-empty; technical properties, original filename, content identity, and storage references SHALL remain read-only.

#### Scenario: Correct one metadata field
- **WHEN** the owner supplies a valid new title for an existing track
- **THEN** the system returns status `200`, persists the title, advances `updated_at`, and leaves all unspecified fields unchanged

#### Scenario: Reject an empty correction
- **WHEN** the owner supplies an empty or whitespace-only title, artist, or album
- **THEN** the system returns status `422` and leaves the track unchanged

#### Scenario: Correct a missing track
- **WHEN** the owner patches an unknown track UUID
- **THEN** the system returns status `404`

### Requirement: Extracted cover retrieval
The system SHALL expose `GET /api/v1/tracks/{track_id}/cover` and return the stored cover bytes with their correct JPEG or PNG media type. The endpoint SHALL resolve cover content through storage references without exposing the reference itself.

#### Scenario: Retrieve an existing cover
- **WHEN** the owner requests the cover for a track with extracted cover art
- **THEN** the system returns status `200`, the exact stored bytes, and the correct image media type

#### Scenario: Retrieve a missing cover
- **WHEN** the track exists but has no cover art
- **THEN** the system returns status `404`

#### Scenario: Retrieve a cover for a missing track
- **WHEN** the owner requests a cover for an unknown track UUID
- **THEN** the system returns status `404`

### Requirement: Catalog durability
Catalog entries and manual corrections SHALL persist across API and database restarts and SHALL continue to reference the same durable audio and cover objects.

#### Scenario: Restart after catalog changes
- **WHEN** the services restart after a track import or metadata correction has completed successfully
- **THEN** detail, list, search, and cover endpoints return the persisted state
