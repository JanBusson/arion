## Context

See `proposal.md` for motivation and `specs/flutter-client/spec.md` for the behavior contract. The Android client currently gives `just_audio` an HTTP URL and configures a 90-to-180-second forward buffer. The default back buffer remains zero, so consumed encoded media can be discarded; controller seek and repeat-current both call the engine's seek operation and therefore issue a new ranged request when the requested bytes are absent.

The FastAPI audio endpoint already returns a complete `200` response for a request without `Range` and correct `206` responses for byte ranges. Imported audio is immutable for the lifetime of a track UUID, although its descriptive metadata can be edited. The Flutter web client shares the playback controller but uses a separate browser source lifecycle. This branch is deliberately stacked on `add-resilient-streaming-recovery`, which is itself based on the Android media-session work.

The pinned `just_audio` version provides the experimental `LockCachingAudioSource`. It starts a complete HTTP download while serving the player immediately, fulfills seeks from downloaded bytes where possible, stores incomplete data under a temporary filename, and atomically promotes that file when the complete response finishes. It is supported on Android but not web and uses the package's existing local HTTP proxy mechanism.

## Goals / Non-Goals

**Goals:**

- Keep one playback authority and preserve the controller's existing queue, repeat, source-generation, and recovery semantics.
- Make a fully cached track independently seekable and replayable without the audio endpoint.
- Make cache correctness and cleanup deterministic enough to unit test without a real Android decoder.
- Bound persistent cache use while allowing the active source to finish safely.
- Fail open to ordinary network playback whenever cache infrastructure is unavailable.

**Non-Goals:**

- Cold-start offline catalog browsing or restoring a queue without first obtaining catalog/session state.
- Owner-pinned downloads, download progress UI, playlist synchronization, or a promise that any cache entry will remain indefinitely.
- Background downloading that continues after the active playback source is replaced.
- Persistent caching in Flutter web.
- Changing the backend stream representation, transcoding media, or adding DRM/licence expiry.

## Decisions

### Use `LockCachingAudioSource` behind the Android adapter

For an uncached Android URL, create a `LockCachingAudioSource` with an Arion-managed destination and give it to the existing `AudioPlayer`. The player can begin as soon as its startup threshold is satisfied while the source continues the complete download. When the final cache file already exists, resolve directly to that local file and touch its last-used timestamp before loading it.

Keep the public playback controller independent of filesystem and package source types. The URL remains sufficient input because the complete normalized audio URL contains both configured server identity and track UUID. The adapter/cache layer owns whether that logical URL becomes a caching network source or a local file source. Web continues to use `setUrl` directly.

Subscribe to the caching source's completion signal for the current source generation. On successful completion, touch the final entry and run bounded cleanup. Source replacement cancels Arion's subscription and releases protection for the old key; incomplete `.part` data is never considered a cache hit and may be overwritten or removed by later maintenance.

Alternatives considered:

- Increasing `backBufferDuration` retains recent media only in RAM, consumes memory proportional to duration/bitrate, and loses everything on process death; it does not provide the requested persistent behavior.
- Native Media3 `SimpleCache` offers mature sparse-range caching and built-in LRU behavior, but `just_audio` does not expose its `DataSource.Factory`. Introducing a custom Android plugin or maintaining a plugin fork is disproportionate for this first cache iteration and can be reconsidered if the experimental source proves unreliable.
- A separate eager HTTP download followed by local playback cannot serve the first play until enough plumbing exists to read a growing file. `LockCachingAudioSource` already coordinates simultaneous playback, full download, and seeks.

### Manage an Arion-owned app-cache directory with a 1 GiB LRU limit

Place entries under an Android app-private cache directory rather than user-visible storage. Hash the normalized absolute audio URL with SHA-256 for a filesystem-safe stable key; this isolates equal track UUIDs on different servers without exposing server addresses in filenames. Store each entry in its own directory so the final media, MIME sidecar, and any partial file can be inspected and removed as one unit.

Use one gibibyte as the initial fixed cache limit. Calculate usage from files on disk and order complete inactive entries by a last-used timestamp represented by the final media file's modification time. Touch that timestamp on every complete cache hit and completion. Run cleanup during lazy initialization and after a completed entry is committed. Protect the currently selected entry and any in-flight cache write; if protected data alone exceeds the limit, allow a temporary overage and retry cleanup when protection moves to another entry.

The operating system may clear app-cache storage under device pressure. Missing files are therefore ordinary cache misses, not data loss errors. The cache manager serializes initialization, touches, completion cleanup, invalidation, and disposal-sensitive callbacks so rapid selection cannot delete or publish state for a newer source.

Alternatives considered:

- The `just_audio` default cache destination is convenient but gives Arion no stable ownership boundary for quota enforcement, server isolation tests, or grouped cleanup.
- A database or preferences index would duplicate filesystem truth and require crash reconciliation. Atomic final-file existence plus filesystem metadata is sufficient for a bounded opportunistic cache.
- Unbounded caching maximizes hits but can silently consume the phone's storage. A fixed initial limit is simpler than adding cache settings before there is evidence that owner configurability is needed.

### Treat only an atomically completed file as reusable

Pass a deterministic final destination to the caching source and rely on its `.part`-then-rename completion behavior. Cache discovery accepts only the expected final file; partial files and MIME sidecars without a final file do not establish availability. A later online load can overwrite stale partial state and maintenance removes orphan companions.

The imported audio object is immutable for a track UUID, so no backend validator is required for this iteration. Editing title, artist, album, or cover does not invalidate audio. Deleting and reimporting creates a different track URL. If future APIs allow replacing audio under one UUID or add expiring/credential-bearing URLs, the cache identity must be extended with an immutable content version rather than hashing the request URL directly.

Alternatives considered:

- Exposing the backend SHA-256 digest or adding `ETag` would provide explicit validation but changes API/backend scope without solving a current mutability problem.
- Reusing partial bytes after a process restart would require resumable-download bookkeeping and integrity validation. Restarting an opportunistic download is safer and keeps incomplete media outside the offline guarantee.

### Invalidate a failing local entry once, then preserve network recovery

Track whether the active engine source resolved from a complete local entry. If initial local loading or later decoding fails, invalidate that entry, mark the current source generation to bypass it once, and allow the controller's existing bounded reload to construct a network caching source for the same URL. A cache-directory, hashing, inspection, write, or cleanup failure also bypasses caching and calls ordinary network `setUrl`; cache errors do not replace playback errors or expose paths to the UI.

If the network is also unavailable, the existing reconnecting/exhausted/manual-retry states remain authoritative. A later owner retry may attempt cache setup again after transient device-storage failure, while a corrupt entry already removed cannot trap recovery in a local failure loop.

Alternatives considered:

- Reporting cache failures directly would turn an optional performance layer into a new playback failure mode.
- Retrying a nominally complete local file indefinitely can loop without ever consulting the reachable server.

### Keep caching coupled to the active media session

Caching continues only as part of active source playback, including when the existing Android audio service keeps playback alive in the background or under lock screen. Do not introduce a second download service or playback authority. System media controls continue to address the same controller, and changing source/session uses existing generation invalidation before the old cache entry loses protection.

Explicit offline downloads need different retention rules, persisted download state, progress, constraints, and background scheduling. They should later use a dedicated download manager and may promote/reuse compatible complete playback-cache files, but are not simulated by pinning entries in this cache.

## Risks / Trade-offs

- [`LockCachingAudioSource` is experimental and uses a local HTTP proxy] → Keep it isolated behind the existing adapter boundary, preserve direct-network fallback, and require real-device seek/replay/background tests before accepting the APK.
- [Starting a track starts downloading its complete file, increasing data use when the owner skips quickly] → Keep caching Android-only, cancel/release replaced sources where the package permits, bound disk use, and document that explicit Wi-Fi/download policy belongs to the later offline feature.
- [The OS can evict app-cache files at any time] → Treat every use as a fresh existence check and never label this feature guaranteed offline availability.
- [A single long lossless track can exceed the cache limit] → Protect it while active, allow temporary overage, and make it eligible for eviction after source replacement.
- [Filesystem cleanup can race with source replacement or completion] → Serialize cache mutations and pass the protected key captured for the current source generation into cleanup.
- [A valid local file could be discarded after an unrelated decoder error] → Invalidate only when the active source was local, do it once per generation, and favor safe network recovery over retaining a questionable opportunistic entry.

## Migration Plan

1. Add the cache manager and Android adapter wiring behind dependency-injected factories while retaining direct URL behavior as fallback and on web.
2. Release a replacement APK after automated checks and physical-device verification; no backend, database, or Docker deployment is required.
3. The cache directory is created lazily, so existing installations need no data migration. Rolling back to the previous APK leaves only disposable app-cache files, which Android or a later cleanup can remove without affecting server media.
