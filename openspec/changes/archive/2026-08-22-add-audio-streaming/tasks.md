## 1. Range Semantics

- [x] 1.1 Add a pure single-byte-range parser covering bounded, open-ended, suffix, capped-end, malformed, multiple, reversed, zero-suffix, and unsatisfiable inputs; verify focused unit tests pass.

## 2. Storage Streaming

- [x] 2.1 Extend the media-storage contract and local adapter with safe object size/media-type metadata for every supported canonical audio suffix; verify storage tests cover all mappings and missing objects.
- [x] 2.2 Add inclusive bounded byte iteration with a fixed default chunk size and correct file-handle lifetime; verify storage tests demonstrate multi-chunk complete and partial reads without reading past the requested end.

## 3. Audio API

- [x] 3.1 Add `GET /api/v1/tracks/{track_id}/audio` complete-object streaming with safe missing-track/object handling; verify PostgreSQL-backed API tests assert status, bytes, media type, `Content-Length`, `Accept-Ranges`, and absence of storage details.
- [x] 3.2 Add `206` responses for bounded, open-ended, suffix, and oversized-end requests; verify API tests assert exact bodies and `Content-Range`/`Content-Length` headers.
- [x] 3.3 Add empty `416` responses for malformed, unsupported, multiple, reversed, zero-suffix, and non-overlapping ranges; verify API tests assert `Content-Range: bytes */<length>` and `Accept-Ranges: bytes`.

## 4. Documentation and Validation

- [x] 4.1 Document complete playback and seeking requests in the README, including the endpoint contract and current no-transcoding limitation; verify documented commands match the implemented route.
- [x] 4.2 Run the backend test suite and strict OpenSpec validation, then verify the change has no uncompleted tasks and no validation errors.
