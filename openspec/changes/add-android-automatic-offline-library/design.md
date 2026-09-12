## Context

See `proposal.md` for motivation and the delta specs for observable behavior. Android already has one `audio_service`/`just_audio` playback authority and a 1 GiB opportunistic cache under the temporary cache directory. That cache can persist across ordinary restarts but is evictable, is populated only by active playback, and stores no catalog. The backend already serves immutable audio for a track UUID as complete `200` responses and correct `206` byte ranges, while the catalog API is paginated with a maximum page size of 100.

The new feature must survive a cold start without network access, preserve web behavior, avoid a backend migration, and remain simple enough for one private server. This branch is deliberately stacked on `add-android-persistent-audio-cache`; it must not be merged independently of that prerequisite.

## Goals / Non-Goals

**Goals:**

- Give the Android owner a clear opt-in and a trustworthy "ready offline" result rather than inferring availability from opportunistic cache hits.
- Keep durable catalog and audio state crash-safe, server-scoped, testable with filesystem and HTTP fakes, and reusable by the existing player/media session.
- Reconcile a complete library without loading the whole audio set concurrently or repeating already verified transfers.
- Resume useful partial work and fail without damaging the last known-good offline library.
- Keep storage, catalog fallback, synchronization, and playback resolution behind small interfaces so web can receive inert implementations.

**Non-Goals:**

- Android OS-scheduled downloads that are guaranteed to finish after the app process is killed; incomplete work resumes next time the app runs.
- User-selected individual tracks, playlists, storage quotas, Wi-Fi-only scheduling, SD-card/shared-media export, or encrypted/DRM downloads in this first iteration.
- Offline YouTube discovery/import, offline metadata editing, offline cover-art guarantees, or synchronization from Flutter web.
- Changing track immutability, adding checksums to the API, transcoding, or changing Docker/backend deployment.

## Decisions

### Store the offline library separately in application-support storage

Create an Android `OfflineLibraryStore` rooted below `getApplicationSupportDirectory()`, not the temporary/cache directory. Derive a server directory key from the SHA-256 hash of the normalized base URL and derive track keys with the same normalized absolute-audio-URL identity used by the playback cache. Store a versioned catalog manifest plus one directory per track containing `audio.bin`, `audio.bin.part`, and small transfer metadata when required.

Write catalog/transfer metadata to a sibling temporary file, flush it, and rename it over the published file. Only a non-empty final media file whose recorded expected byte count matches its filesystem length is verified. On startup, reconcile the manifest against filesystem truth and downgrade missing, empty, or mismatched entries before publishing state. App uninstall is the platform-supported final cleanup boundary.

The opportunistic playback cache remains quota-bound and evictable; durable offline media is not included in its LRU calculation. Extend the cache through a narrow export operation so a known-complete cached file can be copied into an offline partial destination and verified/promoted without another full download. The durable store never adopts or moves the cache's only copy.

Alternatives considered:

- Reclassifying the existing cache as offline storage would break its 1 GiB eviction contract and could make the UI promise files Android is allowed to reclaim.
- Shared external/media storage would require broader permissions and expose private files to other apps without helping in-app playback.
- SQLite is unnecessary for a small immutable catalog; a versioned atomic JSON manifest plus filesystem verification provides adequate crash recovery and keeps the dependency surface small.

### Use a session-scoped synchronization coordinator with two workers

Create an Android `OfflineLibraryCoordinator` per configured server session. It loads saved state immediately, observes the persisted opt-in, and on enable, app launch, retry, and successful online refresh obtains an unfiltered snapshot by paging the API at 100 items until the reported total is satisfied. It rejects duplicate/contradictory pagination and never commits partial results. A monotonically increasing generation prevents work from an old server or refresh from publishing into a replacement session.

After atomically committing a complete catalog snapshot, calculate a reconciliation plan: remove identities absent from the new snapshot, retain verified immutable audio for identities still present, import an eligible complete playback-cache entry, and queue missing entries. Run at most two streamed audio requests concurrently to limit load on the phone and home server. The coordinator owns cancellation, aggregate/per-track state, and disposal; the UI never downloads files directly.

Downloads use a dedicated HTTP client rather than the audio player's local proxy. Starting with an existing partial length, send `Range: bytes=<length>-`. Accept a `206` only when `Content-Range` begins at that exact offset and supplies a consistent total. If the server returns a full `200`, truncate the partial destination and treat it as a clean restart. Reject other success shapes, length overflow, empty completion, and inconsistent totals. Flush the completed expected length and atomically rename `.part` to `audio.bin`; retain a compatible partial after transient I/O/network failure and retry it during the next run.

The coordinator runs while its Flutter/Android process remains alive, including ordinary navigation away from the library screen. It does not add WorkManager or a second Android foreground service. The status explicitly remains incomplete if Android suspends or kills the process, and startup resumes the plan. This is a deliberate first step: for the current small catalog the owner can keep the app open until it reports ready, without introducing background-scheduling and battery-policy complexity.

Alternatives considered:

- Unbounded parallel GETs would finish a tiny library quickly but can saturate server disk/network and make cancellation/error state noisy.
- Android DownloadManager or WorkManager could survive process death but adds native lifecycle, notification, retry, and cleartext/private-destination behavior before there is a demonstrated need. It can replace the executor later without changing the coordinator/store contract.
- Waiting for playback to populate the cache cannot prepare unplayed songs and gives no complete-library readiness signal.

### Treat the snapshot as the single reconciliation boundary

The synchronizer performs its own complete unfiltered pagination rather than interpreting `LibraryController`'s visible first page, search result, or incremental scrolling as the library. Only a complete generation can replace `catalog.json` and trigger removals. Metadata updates are committed without redownloading audio because track audio is immutable for a UUID. A newly imported identity is queued; a removed identity has its final and partial files deleted only after the new manifest is safely published.

Maintain the previous manifest until the replacement is durable. If a crash occurs between manifest replacement and deletion, startup cleanup removes orphaned files; if it occurs before replacement, the previous manifest remains authoritative and no valid track is lost. Search responses never enter the synchronization path.

Alternatives considered:

- Reusing whatever rows are currently visible would confuse pagination/search omissions with deletion.
- Clearing the snapshot before refresh would make a temporary server outage destroy offline cold-start usability.

### Add catalog fallback without turning the catalog API into a cache

Introduce an `OfflineCatalogSnapshotStore` port used by `LibraryController`. On Android initial load, the controller still attempts the online first page. If that fails, it reads the complete snapshot for the active server and enters an explicit offline-snapshot state; local title/artist/album filtering replaces API search only in that state. Retry always attempts to return to the live catalog. Web receives a no-snapshot implementation and preserves its existing behavior.

The full snapshot fetcher and visible catalog controller may share response models but have separately owned request lifecycles so closing/replacing a UI session cannot leave the downloader holding a closed client. Session disposal cancels both before the previous server's data is removed.

Alternatives considered:

- Returning saved rows invisibly from `CatalogApi` would hide staleness/offline state and could let search/pagination code mistake local results for authoritative server responses.
- Restoring only downloaded filenames is insufficient because the player and UI require track identity, title, artist, album, duration, and media-session metadata.

### Resolve durable offline audio before cache and network sources

Generalize Android source preparation into a local-first resolver chain. The offline resolver validates the server/track entry and returns a local file source; otherwise the existing persistent-cache resolver chooses a complete cache file or a caching network source. The playback controller continues to submit the logical audio URI and remains the sole owner of queue, repeat, recovery, and source generations.

Tag the active source origin. If a durable local source fails to load or decode, invalidate its offline-ready entry once for that transition, notify the coordinator that the track is missing, and continue through cache/network recovery. Do not retry the same local path in a loop. Successful offline playback never creates an audio HTTP request and remains controlled through the existing Android media session.

Alternatives considered:

- Teaching queue/controller code about filesystem paths would duplicate source-selection logic and risk divergence between UI, notification, and automatic queue transitions.
- Serving offline bytes through a loopback HTTP server would preserve URL-shaped inputs but creates an unnecessary server lifecycle and range implementation on the phone.

### Keep the preference and destructive cleanup explicit

Persist the opt-in against the normalized server identity. The setting is initially off, shows that current network data and durable storage are used, and exposes status/counts plus retry. Disabling requires confirmation because it removes guaranteed offline media; cancellation completes before deletion. Saving a different server URL disposes the old coordinator, clears the old preference/data, and starts the new session with offline mode off so tracks from two private servers cannot be confused.

Alternatives considered:

- Enabling downloads by default could unexpectedly consume mobile data and all remaining storage on a larger future catalog.
- Retaining hidden data for every previously configured server complicates ownership and creates storage leaks in a single-server client.

## Risks / Trade-offs

- [A library can exceed free device storage because the first version has no quota] -> Preflight with available filesystem space when available, download one bounded item at a time per worker, surface storage failures without removing verified files, and require explicit opt-in with storage disclosure.
- [The backend exposes byte length but not a cryptographic digest or content version] -> Rely on immutable track UUIDs, strict HTTP range/length validation, atomic finalization, and decode-failure invalidation; add a content digest/version API only if audio replacement under one UUID is introduced.
- [Two independent downloads can briefly duplicate an opportunistic cache entry] -> Export verified cache content first and make offline playback bypass the cache; normal LRU cleanup later reclaims the redundant cache copy.
- [Android can stop the process before foreground synchronization finishes] -> Never claim completion early, retain compatible partials, resume on next launch, and keep a future WorkManager executor possible behind the coordinator contract.
- [Server changes or disable cleanup are destructive] -> Require confirmation for disable, order cancellation before exact server-scoped deletion, and cover target-path derivation with tests.
- [A catalog can change during multi-page pagination] -> Validate offsets, duplicates, and final unique count against the reported total; if inconsistent, preserve the previous snapshot and retry rather than reconciling deletions.

## Migration Plan

1. Land and retain the prerequisite persistent-cache change, then add inert cross-platform ports and Android durable storage without changing current playback.
2. Add snapshot fallback and synchronization behind the disabled-by-default Android preference; existing installs therefore continue online/cached behavior until the owner opts in.
3. Add local-first playback resolution, progress/settings UI, and automated tests, then run formatting, analysis, the complete Flutter suite, and a web build.
4. Only after the web/regression gates pass, bump the Android application version and build the replacement APK for owner testing.
5. On-device acceptance prepares the complete library while online, force-stops/restarts without server access, and checks browse/search/play/seek/replay/queue/repeat/media controls plus interrupted-download resume.

Rollback installs the prior APK. Android application data may retain the new app-private directory but the prior version does not read it; reinstalling/clearing app data removes it. No backend or database rollback is required.
