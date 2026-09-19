## Context

See `proposal.md` for motivation and the change specs for required behavior. This change is stacked on `import-missing-tracks-from-youtube`, whose backend currently discovers candidates with `ytsearch`, signs a short-lived candidate snapshot, and uses pinned `yt-dlp` again for fresh eligibility checks and download.

NewPipe's current extractor does not approximate a music query with keywords. Its `music_songs` filter calls the YouTube Music `youtubei/v1/search` endpoint as the `WEB_REMIX` client with a Songs-category parameter and parses song title, artist, duration, thumbnail, and video ID from the music result rows. The pinned Arion `yt-dlp` also supports `https://music.youtube.com/search?...#songs`; however, flat extraction exposes only ID and title, while resolving five full entries on the Dell server took about 49 seconds and defeats the existing short discovery timeout.

The integration remains experimental, private, disabled by default, and subject to the legal/provider limitations documented by the prerequisite change.

## Goals / Non-Goals

**Goals:**

- Make the common external search return YouTube Music song results with artist-quality metadata.
- Retain the existing broad video search as an explicit escape hatch for unofficial remixes and video-only releases.
- Preserve one approval, revalidation, download, import, provenance, and duplicate-protection path regardless of discovery mode.
- Keep external calls bounded, unauthenticated, replaceable, and observable with sanitized events.
- Prevent stale query or old-mode results from appearing after the owner changes mode.

**Non-Goals:**

- Ranking or claiming that a candidate is the correct recording.
- Automatically falling back between modes, merging result sets, or searching both modes concurrently.
- YouTube Music authentication, library access, cookies, playlists, albums, artists, Premium media, or access-control bypasses.
- A general visual redesign, persistent search-mode preferences, playback queues, or repeat modes.
- Replacing `yt-dlp` for selected-video eligibility checks or media acquisition.

## Decisions

### 1. Add an explicit API enum and default omitted mode to music

`GET /api/v1/acquisition/youtube/candidates` gains an allow-listed `mode` query parameter with values `music` and `all`; omission maps to `music`. The Flutter client always sends its current selection, but the server default makes music-first behavior consistent for older or alternative clients. Validation occurs before provider dispatch.

The route and response envelope remain stable. Candidate responses add the discovery mode so client state and tests can reject mixed-mode results. There is no automatic fallback: an empty music response remains empty.

Appending words such as "official audio" to a normal YouTube query was rejected because it is ranking advice rather than a type filter and would still return music videos and unrelated uploads.

### 2. Use a pinned unauthenticated YouTube Music search adapter for music discovery

Add a narrowly wrapped and exactly pinned `ytmusicapi` dependency. Construct it without authentication, cookies, user files, or account state and inject a dedicated HTTP session whose connect/read timeout is derived from the existing discovery limit. Call only public search with `filter="songs"`.

The adapter treats every returned value as untrusted. It accepts only `resultType == "song"`, a valid eleven-character YouTube video ID, a bounded non-empty title, a bounded artist list, and an optional non-negative bounded duration. It locally caps output to the configured maximum even if the upstream library returns its normal larger first page. It constructs the canonical page and `i.ytimg.com` thumbnail URLs from the validated video ID rather than trusting arbitrary returned URLs. Malformed entries are skipped; timeout, protocol, and unusable-response failures map to the existing sanitized provider-unavailable response.

Calling the YouTube Music internal endpoint by hand, as NewPipe does, would avoid a dependency but would duplicate client-version discovery, headers, parsing, and continuation behavior. Embedding NewPipe would add a JVM runtime and a second-language service boundary. A public Piped instance would disclose searches to another operator and add an unnecessary availability dependency. The pinned Python adapter is the smallest maintainable boundary for Arion.

### 3. Keep broad discovery and all acquisition work on the existing yt-dlp path

`all` dispatches to the current fixed-argument `ytsearch` implementation unchanged. Both discovery adapters produce the same internal candidate type. Job processing continues to construct a canonical YouTube watch target from the validated video ID and uses the existing pinned `yt-dlp`/FFmpeg path for fresh metadata, eligibility, audio selection, download, normalization, and import.

Music discovery's artist display text becomes the candidate creator value and therefore improves filename metadata fallback. Fresh revalidation remains authoritative for duration, availability, live status, and access restrictions; a YouTube Music classification does not bypass any acquisition rule.

### 4. Bind discovery mode into signed candidate state without a database migration

The internal candidate and signed token gain a `discovery_mode` field. Job creation obtains it only from the verified token; the client cannot separately override it. Existing job rows already persist the candidate title and creator needed by the worker, so no schema migration is required. Provider/external-ID provenance remains `youtube` plus video ID, ensuring the same video discovered in either mode resolves to the same existing track.

Tokens issued before deployment may fail verification after the schema change. They expire within the configured short TTL and discovery has no durable side effect, so the client handles this as an invalid candidate and asks the owner to search again. Already-created queued or active jobs are unaffected.

### 5. Model mode as session state and invalidate stale discovery responses

The Flutter library controller owns a two-value discovery-mode state initialized to `music`. It is not persisted. Changing mode clears displayed candidates and discovery errors and increments the same request-generation guard used for submitted searches, so a late result for the previous query or mode is ignored. It does not cancel or alter an already-created acquisition job.

The library screen presents compact mutually exclusive radio controls associated with the search field. They can wrap below the text field on narrow screens while remaining visually grouped with it. The external action text reflects the selection, such as `Search YouTube Music` and `Search all YouTube`; local result wording and local API requests do not change.

### 6. Verify each adapter independently and together at the API/UI boundaries

Unit tests use fake adapters and hostile result fixtures to cover mode validation, local result caps, field normalization, timeouts, malformed results, token tampering, and absence of automatic fallback. API tests assert omitted-mode behavior and dispatch. Flutter controller and widget tests cover the default, explicit `all`, no request on selection, stale-response suppression, candidate clearing, and narrow layouts.

The operator smoke test reports the pinned music-search dependency and can run discovery-only checks for both modes without creating a job. Isolated deployment verification exercises both modes, then reuses one explicitly authorized candidate for the existing acquisition/range-streaming check; production remains disabled until that succeeds.

## Risks / Trade-offs

- [YouTube Music changes its undocumented response] → Pin the adapter, validate its output strictly, keep stable errors, and cover it in the existing operator smoke/release process.
- [The upstream search call returns more than requested] → Parse only eligible rows and stop after Arion's configured maximum of five; never request continuations for the initial bounded use case.
- [Music metadata is incomplete or wrong] → Show several candidates, retain canonical-page review, require explicit selection, and revalidate the selected video before work starts.
- [The same video appears in both modes] → Keep provenance identity based on YouTube video ID rather than discovery mode.
- [A mode switch races an in-flight request] → Key client acceptance on both submitted query generation and discovery mode, and discard stale responses.
- [Two controls crowd the phone layout] → Use a compact grouped control that wraps as a unit and verify phone-width widget layouts.
- [Provider terms or authorization do not permit acquisition] → Preserve disabled-by-default operation, warning, acknowledgement, and all restrictions from the prerequisite change.

## Migration Plan

1. Integrate the prerequisite `import-missing-tracks-from-youtube` change first; keep this branch stacked until then.
2. Add and lock the reviewed music-search dependency, provider adapter, mode contract, token field, and tests without changing the database.
3. Build API/worker/web images and run existing regression suites with acquisition disabled.
4. In an isolated private deployment, enable acquisition and verify music discovery, broad discovery, mode switching, an authorized acquisition, and ranged playback.
5. Deploy the paired API and web images. Existing tracks and jobs remain intact; owners with a pre-deployment candidate token may need to search again.

Rollback restores the previous paired API and web images. No schema downgrade or volume change is needed; existing imported media and provenance remain valid.
