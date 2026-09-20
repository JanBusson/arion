## Context

See `proposal.md` for motivation. Arion is a single-user FastAPI/PostgreSQL modular monolith deployed with Docker Compose. It already supports substring catalog search, staged file upload, FFprobe/Mutagen inspection, SHA-256 duplicate protection, atomic local-storage promotion, and range-based streaming. FFmpeg is already present in the backend image. The new flow crosses the Flutter client, API, database, external process execution, and media storage, and `yt-dlp` depends on undocumented provider behavior that can break between releases.

The feature is a private experiment rather than a claim that arbitrary YouTube downloading is authorized. YouTube's service terms and API policies restrict automated access, downloading, and audio separation. The design therefore makes the operator opt in, requires per-job acknowledgement, excludes access-control bypasses, and keeps the provider behind a replaceable boundary; these controls communicate and limit risk but do not change provider terms.

## Goals / Non-Goals

**Goals:**

- Reuse one validated import and storage path for uploads and downloaded files.
- Keep downloads durable across API and worker restarts without adding an external queue system.
- Bound network, CPU, memory, disk, and subprocess risk on the small home server.
- Make every external search and acquisition an explicit owner action.
- Preserve enough provenance and structured state to diagnose failures and prevent duplicates.
- Keep the acquisition provider replaceable as a learning-oriented integration boundary.

**Non-Goals:**

- Public, multi-user, or unattended bulk downloading.
- Playlists, channel imports, live streams, Premium/private/age-gated media, cookies, login flows, geo-bypass, DRM, or other circumvention.
- Guaranteeing that a candidate is the intended recording or that its metadata is authoritative.
- Making YouTube search or acquisition part of API readiness for normal Arion operation.
- Redis, Celery, Kubernetes, WebSockets, or a new independently deployed codebase.
- Automatic playback after import or automatic acquisition based on match confidence.

## Decisions

### 1. Keep local search first and make external discovery explicit

The existing `GET /api/v1/tracks?q=...` remains authoritative for the library. Only an explicit client action after an empty result calls `GET /api/v1/acquisition/youtube/candidates?q=...`. The API returns at most five candidates and does not persist media.

This avoids external query disclosure on every catalog search, makes the boundary visible, and leaves current local behavior unchanged. Automatically falling through was rejected because transient local search mistakes would silently contact an external provider.

### 2. Use a provider interface with an experimental yt-dlp implementation

Backend application code depends on a narrow `AcquisitionProvider` contract for candidate discovery, eligibility revalidation, and download-to-staging. The first provider invokes a pinned `yt-dlp` executable using subprocess argument arrays, no shell, fixed flags, and `--`-style end-of-options separation. Search uses a bounded provider query and download accepts only a strictly validated YouTube video identifier; the provider constructs the canonical target.

The CLI boundary is preferred over embedding the Python library because it isolates global downloader behavior and makes stdout, stderr, timeouts, and termination explicit. The official YouTube Data API was rejected for this experimental flow because its policies prohibit using API clients to offer audio extraction/download, and it would add credentials while not authorizing the subsequent acquisition. A provider interface allows a compliant downloadable-media source to replace YouTube later.

Candidate identifiers are short-lived integrity-protected tokens containing the minimum provider identity and expiry needed for selection. Before starting work, the worker fetches fresh metadata and repeats all eligibility checks so an old candidate cannot bypass current bounds.

### 3. Persist jobs in PostgreSQL and run one worker from the same image

Add an `acquisition_jobs` table containing UUID, provider, external ID, candidate snapshot, acknowledgement timestamp, state, phase/progress, attempt count, lease timestamps, sanitized failure fields, resulting track ID, and audit timestamps. Add track-linked source provenance in a separate `track_sources` table with a unique `(provider, external_id)` constraint.

`POST /api/v1/acquisition/jobs` validates the candidate and acknowledgement, commits a `queued` row, and returns `202`. `GET /api/v1/acquisition/jobs/{id}` exposes an allow-listed job schema. The Flutter client polls this resource with a modest interval and stops on a terminal state.

A `worker` Compose service runs a command from the same backend package and image, shares the media volume, and claims PostgreSQL rows using transactional row locking with a lease. Initial concurrency is one. Expired leases make interrupted jobs reclaimable with a bounded attempt count. This provides durable work without Redis. FastAPI in-process background tasks were rejected because API restarts would lose execution and multiple API workers could duplicate it.

### 4. Separate acquisition staging from catalog commitment

Each claimed job receives a storage-owned staging workspace with a generated path. yt-dlp and FFmpeg may write only inside that workspace. Partial files are never visible through catalog or streaming endpoints. The worker enforces duration before download when metadata permits, monitors output size and free-space reserve during work, and applies an overall timeout and graceful-then-forced termination.

After acquisition, the worker selects one audio output. It prefers M4A/AAC when available; otherwise it preserves a supported audio codec by remuxing into a supported container, such as moving Opus from WebM into Ogg/Opus. It performs one configured fallback transcode only when remuxing cannot produce client-compatible media. It does not normalize every track to MP3 because that would add avoidable lossy transcoding.

The resulting file is handed to a refactored shared import finalization service. That service performs the existing inspection, filename/tag fallback, cover handling, digest lock, duplicate lookup, storage promotion, and database transaction. Upload imports call the same finalization path. Job completion and track-source creation occur transactionally after the track is known. Cleanup removes the entire job workspace on success, failure, cancellation, or lease recovery.

### 5. Resolve duplicates by provenance first and content second

Before download, the worker checks the unique provider/external-ID provenance mapping. If it already points to a track, the job completes with that track. After download, existing SHA-256 protection remains decisive for identical bytes from different source IDs.

If finalization reports an existing content duplicate, the job completes with that existing track and records the new provenance when it does not conflict. This makes repeated user actions idempotent and preserves the stronger content-based invariant.

### 6. Treat provider data and process output as hostile input

Queries, titles, channel names, thumbnails, filenames, JSON output, and stderr are untrusted. The implementation length-bounds and normalizes persisted/displayed fields, accepts only HTTPS thumbnail/page URLs on expected hosts, never derives filesystem paths from provider strings, and parses structured output with bounded buffers. API errors use stable codes and curated messages.

The process environment is allow-listed, not inherited wholesale. User input never becomes executable flags. No cookie files or account credentials are mounted. The worker runs as the existing unprivileged container user with the smallest practical writable surface and resource limits. Structured logs contain job IDs, phases, timings, byte counts, attempts, exit category, and sanitized errors, but not raw commands, paths, secrets, or unbounded stderr.

### 7. Pin downloader components and update through normal image releases

`yt-dlp`, its required JavaScript support/runtime when needed by the pinned version, and FFmpeg are installed reproducibly in the image. Production containers never self-update. Extractor health is covered by a disabled-by-default operator smoke test and failures surface as provider-unavailable rather than making the API unready.

The pin makes builds reproducible; periodic dependency updates through CI are expected because provider changes can break old versions. This trade-off is preferable to downloading executable code at container startup.

### 8. Keep configuration conservative and disabled by default

Configuration covers enablement, candidate count capped at five, discovery timeout, maximum media duration, maximum output bytes, minimum free-space reserve, download/processing timeout, retry count, worker lease, poll interval guidance, concurrency fixed to one initially, and record/staging retention. Production validation rejects unsafe or contradictory values.

Disabling the feature prevents new searches and jobs. Existing active jobs are allowed to reach a safe terminal state during a normal rollout; an operator can stop the worker for an emergency halt.

## Risks / Trade-offs

- [YouTube terms or applicable rights do not authorize an acquisition] → Keep the feature disabled by default, show a clear warning and per-job acknowledgement, restrict it to private owner-initiated use, and document that these controls do not provide authorization.
- [Provider changes break discovery or download] → Pin dependencies, classify provider failures, provide a smoke test, and update through reviewed image releases.
- [A large or malicious source exhausts the server] → Enforce duration, bytes, time, free-space, retry, and concurrency bounds and isolate all output in removable staging.
- [A worker crashes after side effects] → Use leased durable jobs, idempotent provenance checks, existing digest locks, atomic promotion, and reconciliation cleanup.
- [Candidate metadata selects the wrong recording] → Present several candidates with source links and require explicit selection; never claim automatic correctness.
- [Polling adds API traffic] → Use a modest interval and stop at terminal state; the private single-user scale does not justify WebSockets.
- [Preserving source codecs creates format variation] → Limit final containers/codecs to the existing accepted matrix and retain a single configured compatibility transcode fallback.
- [The worker broadens container attack surface] → Run unprivileged, do not mount credentials, restrict process arguments/environment and writable paths, and update dependencies promptly.

## Migration Plan

1. Add nullable provenance and acquisition-job schema through an Alembic migration; existing tracks remain unchanged.
2. Add configuration and provider/worker code while keeping the feature flag off.
3. Build and test the pinned downloader toolchain, job state transitions, crash recovery, cleanup, media limits, duplicate cases, and the shared upload/acquisition finalizer.
4. Add the worker service and deploy it stopped or idle while the flag remains off; verify existing API, web, upload, and streaming health.
5. Deploy the Flutter UI, which continues to behave as before until the server feature is enabled.
6. Enable the feature explicitly on the private server, start one worker, and run an authorized small-file smoke test.

Rollback disables new discovery/job creation first, lets or forces active work into a terminal state, stops the worker, and rolls back application images. The additive database tables and nullable relationships can remain safely in place; removing them requires a later destructive migration after retained jobs/provenance are no longer needed.

## Open Questions

- The exact default limits can be tuned after measurement on the Dell server without changing the behavior contract; initial implementation should choose conservative documented values.
