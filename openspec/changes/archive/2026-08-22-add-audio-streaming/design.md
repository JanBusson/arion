## Context

The catalog stores an opaque audio key whose durable local object already has a canonical suffix selected from inspected content. The current storage adapter can read an entire object into memory but does not expose object size, media type, or a streaming reader. FastAPI currently returns cover bytes directly and translates missing cover objects into a safe `404`. See `proposal.md` for the motivation and `specs/audio-streaming/spec.md` for the playback contract.

HTTP byte ranges are stateful enough to deserve a small parser and focused tests: positions are inclusive, suffix forms differ from ordinary slices, an oversized end remains satisfiable, and invalid or unsupported forms must produce a header-bearing `416` response. Audio files can be hundreds of MiB, so both the storage boundary and response body must preserve bounded reads.

## Goals / Non-Goals

**Goals:**

- Keep HTTP parsing and response construction separate from filesystem path resolution.
- Make all reads bounded and keep opaque-key validation at the storage boundary.
- Produce deterministic single-range behavior that browser and Android media clients can seek against.
- Keep the storage contract implementable later by an S3-compatible adapter.

**Non-Goals:**

- Multipart responses for multiple ranges, conditional requests, caching validators, or download-specific content disposition.
- Transcoding, normalization, adaptive bitrate manifests, or codec negotiation.
- Changing catalog schemas or trusting the original uploaded filename to determine media type.

## Decisions

### 1. Add one nested audio resource

The API will add `GET /api/v1/tracks/{track_id}/audio`, parallel to the existing cover resource. The route first resolves the public UUID through the repository, then passes the opaque audio key to storage. Keeping playback beneath the track resource avoids exposing storage-oriented URLs and fits the existing versioned API.

A general `/media/{key}` endpoint was rejected because it would leak storage identity and create a second authorization surface. Returning audio from the track-detail endpoint was rejected because metadata and potentially large binary content have different caching and response behavior.

### 2. Parse one explicit byte range into an inclusive interval

A pure range parser will accept the complete object size and return an inclusive `(start, end)` interval. It will support bounded, open-ended, and suffix forms. An omitted header selects a full `200` response; a present but unsupported, malformed, multiple, reversed, zero-suffix, or non-overlapping range selects `416` with `Content-Range: bytes */size`.

The implementation deliberately will not silently ignore malformed Range headers. Supporting multipart byte ranges was rejected because audio players normally seek with one range and multipart construction adds code and test surface without value for this single-user application.

### 3. Extend storage with object metadata and bounded iteration

The storage protocol will expose a narrow read descriptor containing the object size and canonical media type, plus a bounded iterator for an inclusive byte interval. The local adapter will resolve and validate the key, derive the media type from the canonical durable suffix, open the file for each response, seek once, and yield fixed-size chunks until the requested length is exhausted. The iterator owns the file context so disconnects and generator closure release the handle.

Passing a raw filesystem path or open file from storage to the API was rejected because it leaks local-storage assumptions into application code and would be awkward for a future object-store adapter. Reusing `read_bytes` was rejected because the default import limit allows objects much larger than a sensible request-memory budget.

### 4. Use explicit streaming responses and headers

FastAPI/Starlette streaming responses will carry `Content-Type`, exact `Content-Length`, and `Accept-Ranges: bytes` for both `200` and `206`. Partial responses additionally carry `Content-Range: bytes start-end/size`. A `416` response carries the unsatisfied form and an empty body. Storage lookup failures are translated to the same safe not-found behavior as absent catalog tracks, without returning paths or keys.

Framework file responses were considered but rejected as the primary abstraction because their local-path API conflicts with the storage boundary and makes single-range policy depend on framework-version behavior.

### 5. Test parsing separately and exercise the public endpoint with real storage

Unit tests will cover every range form and boundary, including one-byte objects and chunk boundaries. PostgreSQL-backed API tests will create catalog rows and local objects, then assert complete, partial, invalid, missing-track, and missing-object responses. A storage-level test will use a chunk size smaller than its fixture to demonstrate multiple bounded reads and exact range termination.

## Risks / Trade-offs

- [A client requests multiple ranges] → Return a deterministic `416`; add multipart support only if a real client requires it.
- [A local object changes size during a response] → Treat catalog media as immutable; imports promote unique objects and no feature currently mutates them.
- [A client disconnects mid-stream] → Keep the file context inside the generator so closure releases the descriptor without buffering remaining bytes.
- [Codec and suffix media-type mappings diverge] → Derive the type from the canonical suffix assigned after content inspection and cover every supported suffix in tests.
- [A future object store has different streaming primitives] → Keep the API dependent on size plus bounded byte iteration, which maps directly to object metadata and ranged GET operations.

## Migration Plan

This is an additive API and storage-interface change with no database migration. Deploy the updated image normally; existing catalog rows already reference canonically suffixed durable audio keys. Rollback consists of restoring the prior image, after which the new endpoint disappears while stored media and catalog data remain unchanged.
