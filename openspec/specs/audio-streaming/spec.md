# audio-streaming Specification

## Purpose

Defines standards-compatible, bounded-memory delivery of stored track audio so private Android and browser clients can play and seek without access to storage internals.

## Requirements

### Requirement: Track audio retrieval
The system SHALL expose `GET /api/v1/tracks/{track_id}/audio` for the original stored audio of a catalog track. A request without a `Range` header SHALL return status `200`, the complete object, its supported audio media type, `Accept-Ranges: bytes`, and an exact `Content-Length`. The response SHALL NOT expose a storage key or server filesystem path.

#### Scenario: Retrieve complete audio
- **WHEN** the owner requests audio for an existing track without a `Range` header
- **THEN** the system returns status `200`, the complete stored bytes, the correct audio media type, byte-range support, and the complete byte length

#### Scenario: Retrieve audio for a missing track
- **WHEN** the owner requests audio for an unknown track UUID
- **THEN** the system returns status `404` without exposing storage details

#### Scenario: Stored audio is unavailable
- **WHEN** a catalog track exists but its referenced audio object cannot be read
- **THEN** the system returns status `404` without exposing the storage key, filesystem path, or underlying storage error

### Requirement: Single byte-range playback
The audio endpoint SHALL support exactly one `bytes` range per request in bounded `start-end`, open-ended `start-`, or suffix `-length` form. It SHALL interpret byte positions inclusively, cap an end beyond the object length at the final byte, and return status `206` with exactly the selected bytes, `Content-Range`, `Content-Length`, `Accept-Ranges: bytes`, and the track's audio media type.

#### Scenario: Retrieve a bounded range
- **WHEN** the owner requests a satisfiable `bytes=start-end` range
- **THEN** the system returns status `206` with bytes from `start` through the inclusive effective end and matching range headers

#### Scenario: Retrieve an open-ended range
- **WHEN** the owner requests a satisfiable `bytes=start-` range
- **THEN** the system returns status `206` with bytes from `start` through the final byte

#### Scenario: Retrieve a suffix range
- **WHEN** the owner requests a positive `bytes=-length` range
- **THEN** the system returns status `206` with the requested number of trailing bytes, or the complete object when the requested suffix is larger than the object

#### Scenario: Cap an oversized range end
- **WHEN** the owner requests a range whose start is satisfiable and whose end exceeds the final byte
- **THEN** the system returns status `206` from the requested start through the final byte

### Requirement: Invalid range handling
The system SHALL reject malformed ranges, unsupported range units, multiple ranges, ranges whose start follows their end, zero-length suffix ranges, and ranges that cannot overlap the stored object. It SHALL return status `416`, `Content-Range: bytes */<complete-length>`, `Accept-Ranges: bytes`, and no audio bytes.

#### Scenario: Reject an unsatisfiable start
- **WHEN** the owner requests a range beginning at or beyond the complete object length
- **THEN** the system returns status `416` with the complete length and no audio bytes

#### Scenario: Reject malformed or unsupported range syntax
- **WHEN** the owner supplies a malformed range, a non-byte range unit, a reversed range, or a zero-length suffix
- **THEN** the system returns status `416` with the complete length and no audio bytes

#### Scenario: Reject multiple ranges
- **WHEN** the owner requests more than one byte range
- **THEN** the system returns status `416` rather than constructing a multipart response

### Requirement: Bounded-memory delivery
The system SHALL read and yield stored audio in bounded chunks for both complete and partial responses. It SHALL NOT load the complete audio object or complete requested range into application memory before beginning the response.

#### Scenario: Stream a large complete object
- **WHEN** the owner retrieves a complete audio object larger than the configured read chunk
- **THEN** the system yields multiple bounded chunks whose concatenation exactly matches the stored object

#### Scenario: Stream a large partial object
- **WHEN** the owner retrieves a byte range larger than the configured read chunk
- **THEN** the system yields multiple bounded chunks and never reads beyond the selected inclusive range
