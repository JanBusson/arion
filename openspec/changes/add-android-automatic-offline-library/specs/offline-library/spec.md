## Purpose

Defines how the Android client prepares, validates, presents, and reconciles a durable owner-controlled copy of the private music library for use without the Arion server.

## ADDED Requirements

### Requirement: Owner-controlled automatic offline synchronization
The Android client SHALL provide a persistent "Keep library offline" setting that is disabled until the owner enables it. Enabling it SHALL start an automatic full-library synchronization whenever the configured server can provide a complete unfiltered catalog, and disabling it SHALL cancel pending work and remove the durable offline catalog and audio after owner confirmation. The setting SHALL disclose that synchronization can use the device's current network connection and storage.

#### Scenario: Enable automatic synchronization
- **WHEN** the owner enables "Keep library offline" for the configured server
- **THEN** the client starts fetching the complete unfiltered catalog and schedules every track without a verified offline file for download

#### Scenario: Synchronize again after launch
- **WHEN** the setting remains enabled and the Android client later completes an unfiltered catalog refresh
- **THEN** the client automatically reconciles the durable offline library without requiring each track to be selected or played

#### Scenario: Disable and remove the offline library
- **WHEN** the owner confirms disabling "Keep library offline"
- **THEN** the client stops queued synchronization work, removes partial and complete offline-library data for that server, and continues to support ordinary cached or network playback

### Requirement: Durable and server-scoped offline state
The client SHALL store the offline catalog and complete audio in app-private durable storage, scope every item to the normalized configured server identity and track identity, and retain verified items across normal app restarts. Offline state from one server SHALL NOT be displayed or played as the state of another configured server.

#### Scenario: Reopen with the same configured server
- **WHEN** the owner restarts the Android client with offline mode enabled for the same server
- **THEN** the client restores the matching durable catalog and verified download state before network synchronization completes

#### Scenario: Change configured server
- **WHEN** the owner saves a different server URL
- **THEN** the client cancels synchronization for the previous identity, does not expose its offline tracks under the new server, and removes the previous server's durable offline data

#### Scenario: Preserve app-private media
- **WHEN** the client stores a complete offline track
- **THEN** the media is unavailable to unrelated apps through shared media storage and remains available until the owner disables offline mode, changes server, removes the app, or a successful catalog reconciliation removes that track

### Requirement: Complete and resumable audio downloads
The client SHALL download audio with bounded concurrency, write incomplete transfers separately from playable files, resume a compatible interrupted transfer with a byte-range request, and atomically publish a track as offline only after the expected complete byte length is present. A partial, empty, mismatched, or unreadable file SHALL NOT be reported or selected as offline media.

#### Scenario: Complete a download
- **WHEN** all expected bytes for a scheduled track have been received and durably finalized
- **THEN** the client marks that track offline-ready and makes its local file eligible for playback

#### Scenario: Resume an interrupted download
- **WHEN** a partial transfer exists and the server accepts a compatible request for its remaining byte range
- **THEN** the client appends the remaining bytes and publishes the track only after the complete expected length is present

#### Scenario: Reject an incompatible resume response
- **WHEN** the server ignores or contradicts the requested range or reports an incompatible total length
- **THEN** the client discards or replaces the partial transfer and restarts a safe complete download rather than combining incompatible bytes

#### Scenario: Continue after a failed transfer
- **WHEN** a download is interrupted, times out, or the app process stops
- **THEN** the client retains only valid resumable state, reports that the library is not fully ready, and retries on a later automatic synchronization or explicit retry

### Requirement: Offline readiness and progress
The Android client SHALL show whether synchronization is disabled, preparing, fully ready, paused by unavailable server, or failed, and SHALL expose aggregate completed, total, and in-progress state. Per-track presentation SHALL distinguish verified offline tracks from tracks that still require the server. The client SHALL NOT promise background completion after Android stops its process.

#### Scenario: Report a fully prepared library
- **WHEN** every track in the last successful complete catalog snapshot has a verified offline audio file and no reconciliation is pending
- **THEN** the client reports that the library is ready offline with matching completed and total counts

#### Scenario: Leave the app during synchronization
- **WHEN** Android suspends or terminates the client before synchronization completes
- **THEN** the client does not report false completion and resumes remaining work when it next runs and can reach the server

#### Scenario: Retry failed work
- **WHEN** one or more tracks failed and the owner activates retry while the server is reachable
- **THEN** the client retries missing or invalid tracks without redownloading already verified files

### Requirement: Safe catalog reconciliation
The client SHALL replace its durable catalog snapshot and reconcile stored media only after every page of an unfiltered catalog refresh has completed successfully. A failed request, incomplete pagination, search result, or stale response SHALL NOT delete verified offline tracks or replace the last complete snapshot. A successful snapshot SHALL schedule new tracks, retain immutable audio for unchanged track identities, update descriptive metadata, and remove media for tracks no longer present.

#### Scenario: Add a newly imported track
- **WHEN** a complete catalog refresh contains a track absent from the prior snapshot
- **THEN** the client publishes the new metadata and schedules its audio for automatic download

#### Scenario: Update metadata without redownloading immutable audio
- **WHEN** a complete catalog refresh changes descriptive metadata for an existing track identity whose verified audio remains valid
- **THEN** the client updates the saved metadata and retains the verified audio file

#### Scenario: Remove a deleted track
- **WHEN** a successfully completed catalog snapshot no longer contains a previously saved track
- **THEN** the client removes that track from the offline catalog and deletes its offline audio and partial transfer

#### Scenario: Preserve state after incomplete refresh
- **WHEN** any page of an unfiltered refresh fails or a response becomes obsolete
- **THEN** the client retains the prior complete snapshot and verified audio without interpreting missing page results as deletions

### Requirement: Local-first offline playback
For a track with a verified offline file, Android playback SHALL prefer the local file and support start, arbitrary seek, replay, queue transitions, repeat, background playback, notification controls, and lock-screen controls without contacting the audio endpoint. If local validation or decoding fails, the client SHALL invalidate that file and use the existing cached or network recovery path without looping on the invalid local source.

#### Scenario: Play and seek without a network
- **WHEN** the owner starts, seeks, or replays a verified offline track while the server is unreachable
- **THEN** the existing player and media session perform the action from the local file without an audio request

#### Scenario: Advance through an offline queue
- **WHEN** a queued or repeated track is verified offline and playback advances while the server is unreachable
- **THEN** the client loads that local source while preserving the existing queue and repeat semantics

#### Scenario: Recover from invalid local audio
- **WHEN** a nominally offline file is missing, unreadable, has an invalid length, or fails to decode
- **THEN** the client removes its offline-ready status, invalidates the file, and attempts the existing non-offline source path at most once for that playback transition
