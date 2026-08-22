## Purpose

Defines a reliable single-file ingestion contract that validates an uploaded audio file, derives useful metadata, and creates exactly one durable catalog entry without leaving partial data.

## ADDED Requirements

### Requirement: Single-file import endpoint
The system SHALL expose `POST /api/v1/tracks/import` as a multipart endpoint accepting exactly one file in the `file` field. It SHALL accept valid MP3, FLAC, MP4/M4A containing AAC or ALAC, Ogg Vorbis, Ogg Opus, and PCM WAV content, based on technical inspection rather than trusting only the filename or declared media type.

#### Scenario: Import a supported audio file
- **WHEN** the owner uploads one valid supported audio file within the configured size limit
- **THEN** the system returns status `201` with the created track representation

#### Scenario: Reject an unsupported format
- **WHEN** the owner uploads content that is not one of the supported audio formats
- **THEN** the system returns status `415` and creates no stored object or catalog entry

#### Scenario: Reject unreadable audio
- **WHEN** the uploaded content claims or appears to be supported audio but cannot be parsed or technically probed
- **THEN** the system returns status `422` and creates no stored object or catalog entry

### Requirement: Bounded streaming upload
The system SHALL stream uploads through staging storage rather than loading the complete file into application memory. The default maximum upload size SHALL be 500 MiB, SHALL be operator-configurable, and SHALL be enforced while bytes are received.

#### Scenario: Reject an oversized upload
- **WHEN** an upload exceeds the configured maximum size
- **THEN** the system stops accepting additional content, returns status `413`, and removes the staged bytes

### Requirement: Content-based duplicate protection
The system SHALL calculate a SHA-256 digest while receiving the file and SHALL allow at most one catalog track for a given audio digest.

#### Scenario: Reject a previously imported file
- **WHEN** an uploaded file has the same SHA-256 digest as an existing track
- **THEN** the system returns status `409`, identifies the existing track, and creates no duplicate catalog entry or durable audio object

#### Scenario: Handle concurrent duplicate imports
- **WHEN** two imports with identical content complete concurrently
- **THEN** exactly one import succeeds and every losing import returns status `409` without leaving an extra durable object

### Requirement: Embedded and technical metadata extraction
The system SHALL extract non-empty embedded title, artist, and album values and the first valid embedded JPEG or PNG cover. It SHALL extract duration in milliseconds, codec, bitrate when available, and sample rate through technical inspection.

#### Scenario: Import a fully tagged file
- **WHEN** a supported file contains valid title, artist, album, cover art, and technical properties
- **THEN** the created track contains those normalized textual values, technical properties, and `has_cover` set to `true`

#### Scenario: Import without cover art
- **WHEN** a supported file has no valid embedded JPEG or PNG cover
- **THEN** the import succeeds and the created track has `has_cover` set to `false`

#### Scenario: Ignore malformed optional cover art
- **WHEN** the audio is valid but its embedded cover art is malformed or unsupported
- **THEN** the audio import succeeds without a cover and does not store the malformed image

### Requirement: Deterministic metadata fallback
When required textual tags are missing, the system SHALL first parse a filename stem matching `Artist - Title`, then use the remaining filename stem as the title, `Unknown Artist` as the artist, and `Unknown Album` as the album. Embedded non-empty values SHALL take precedence over fallback values.

#### Scenario: Derive artist and title from filename
- **WHEN** title and artist tags are missing and the filename is `Example Artist - Example Title.flac`
- **THEN** the created track uses `Example Artist` and `Example Title` while applying the album fallback only if its tag is also missing

#### Scenario: Apply placeholder fallbacks
- **WHEN** required tags are missing and the filename does not match the artist-title pattern
- **THEN** the created track uses the filename stem as title, `Unknown Artist` as artist, and `Unknown Album` as album

### Requirement: Atomic durable import
The system SHALL promote the audio file and optional cover from staging to durable storage and commit the catalog record as one recoverable workflow. It SHALL expose neither staging paths nor server filesystem paths in API responses.

#### Scenario: Persist a successful import
- **WHEN** validation, extraction, durable storage, and catalog persistence all succeed
- **THEN** the track and its referenced objects remain available after application and database restarts

#### Scenario: Clean up a failed import
- **WHEN** any import step fails before the track is committed
- **THEN** the system removes staged and newly created unreferenced objects and leaves no catalog record for that import
