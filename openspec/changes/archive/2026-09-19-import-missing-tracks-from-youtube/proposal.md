## Why

Arion can find and play tracks that are already stored, but a missing catalog result currently leaves the owner without an in-app acquisition path. For this private learning deployment, an explicitly enabled experimental YouTube importer would let the owner review a candidate, approve a bounded background download, and then use the existing catalog and streaming experience.

## What Changes

- Add an operator-controlled, disabled-by-default YouTube acquisition feature backed by `yt-dlp` and FFmpeg.
- Let the owner explicitly request a YouTube search after a local catalog search has no results, rather than sending every catalog query to an external service automatically.
- Present several video candidates with source identity, title, channel, duration, thumbnail, and a link for review; never choose or download a result automatically.
- Require explicit candidate selection and acknowledgement that the owner is authorized to acquire the content. This acknowledgement records intent but does not override copyright law or YouTube's terms.
- Run acquisition as a durable, bounded background job with visible progress and failure information.
- Feed acquired audio through the existing technical inspection, content-deduplication, metadata, staging, and atomic-promotion workflow before creating a playable track.
- Restrict the experimental importer to individual public videos, fixed server-side downloader options, and configured duration, size, time, disk, and concurrency limits. Playlists, live streams, authentication cookies, DRM/circumvention, and arbitrary downloader arguments are excluded.
- Preserve the source audio without lossy transcoding when its codec can be placed in a supported container; transcode only when client compatibility requires it.

## Capabilities

### New Capabilities

- `youtube-track-acquisition`: Explicit YouTube candidate discovery, owner approval, durable acquisition jobs, bounded downloader execution, provenance, and failure reporting.

### Modified Capabilities

- `audio-import`: Allow a validated file produced by an approved acquisition job to enter the same atomic import pipeline as an uploaded file.
- `flutter-client`: Extend the empty local-search experience with opt-in YouTube discovery, candidate review, approval, job progress, and playback after import.

## Impact

- Backend API routes, schemas, database models and migrations, storage staging, import services, structured logging, and startup/readiness behavior.
- Flutter catalog API, library state management, candidate UI, confirmation UI, job polling, and tests.
- Docker image and Compose deployment gain a pinned `yt-dlp` dependency and a single worker process sharing PostgreSQL and media storage with the API.
- New operator configuration includes a feature flag, search/downloader timeouts, maximum duration and output size, job concurrency, and retention limits.
- The feature creates an external dependency on YouTube behavior and `yt-dlp` extractor maintenance. YouTube restricts automated access and downloading; this experimental feature is therefore disabled by default and must not be represented as a generally authorized YouTube download facility.
