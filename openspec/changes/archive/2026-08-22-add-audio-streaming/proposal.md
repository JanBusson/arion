## Why

Arion can durably import and catalog music, but clients cannot play the stored audio. A standards-compatible streaming endpoint is the next required backend capability before the Flutter Android and web clients can provide playback and seeking.

## What Changes

- Add a versioned endpoint for retrieving a track's stored audio without exposing storage keys or filesystem paths.
- Support complete audio responses and one HTTP byte range per request, including bounded, open-ended, and suffix ranges.
- Return the media type, byte length, range capability, and standards-compatible partial-content headers needed by browser and Android players.
- Reject malformed, multiple, and unsatisfiable ranges safely without returning audio bytes.
- Stream from storage in bounded chunks rather than loading an entire track into application memory.
- Add focused unit and PostgreSQL-backed API tests plus API documentation for playback and seeking behavior.
- Continue to defer transcoding, adaptive streaming, download-specific behavior, authorization, playlists, and Flutter client implementation.

## Capabilities

### New Capabilities

- `audio-streaming`: Provides private full-file and single-range audio delivery for catalog tracks, including seeking semantics, safe errors, media types, and bounded-memory reads.

### Modified Capabilities

None.

## Impact

- Extends the FastAPI API below `/api/v1/tracks/{track_id}` with an audio endpoint.
- Extends the media-storage contract with metadata and ranged-read operations suitable for the current local filesystem adapter and a later object-storage adapter.
- Adds no database columns, migration, external service, or runtime dependency.
- Establishes the playback contract that the future Flutter Android and web clients will consume.
