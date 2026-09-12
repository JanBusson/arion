## ADDED Requirements

### Requirement: Persistent Android playback caching
On Android, the client SHALL stream a selected network track without waiting for its complete audio object while concurrently building an app-private persistent cache entry for that server and track. It SHALL mark an entry reusable only after the complete audio object has been stored successfully, SHALL retain complete entries across normal app restarts, and SHALL prefer a complete valid entry over the audio endpoint whenever that track is selected again. A partially stored object SHALL NOT be treated as a complete cache hit or as guaranteed offline media.

#### Scenario: Stream while populating the cache
- **WHEN** the owner starts an uncached track while its audio endpoint is reachable
- **THEN** playback can begin before the complete object is stored and the client concurrently builds a persistent cache entry

#### Scenario: Replay a completely cached track during an outage
- **WHEN** a track finishes caching and the audio endpoint becomes unreachable before repeat-current or manual replay starts it from the beginning
- **THEN** the client replays the track from local media without requesting its audio bytes from the server

#### Scenario: Seek within a completely cached track during an outage
- **WHEN** the owner seeks to any valid position in a completely cached selected track while the audio endpoint is unreachable
- **THEN** playback continues from the requested position using local media

#### Scenario: Reuse a cache entry after an app restart
- **WHEN** a corresponding catalog track is selected in a later app session and its complete cache entry is still valid
- **THEN** the client loads the audio from app-private storage without requiring the audio endpoint

#### Scenario: Encounter an incomplete cache entry offline
- **WHEN** required audio bytes are not present in a complete cache entry and the audio endpoint is unreachable
- **THEN** the client uses its existing buffering, bounded recovery, and retryable-error behavior without claiming that the track is available offline

### Requirement: Bounded and isolated playback-cache lifecycle
The Android client SHALL identify cached audio by both configured server identity and track identity, SHALL store it only in app-private storage, and SHALL enforce a finite cache-size limit using least-recently-used removal of inactive complete entries. It SHALL NOT remove the currently active entry while that entry is being loaded, cached, or played, and it SHALL NOT reuse bytes belonging to a different configured server or track.

#### Scenario: Select the same track identity from another server
- **WHEN** the configured server changes and its catalog contains a track identifier equal to one from the previous server
- **THEN** the client does not reuse the previous server's cached audio for the new server

#### Scenario: Evict old entries at the cache limit
- **WHEN** committing a complete entry would leave the cache above its configured size limit
- **THEN** the client removes least-recently-used inactive complete entries until the limit is restored or only protected active data remains

#### Scenario: Protect the active entry from eviction
- **WHEN** cache cleanup runs while an entry is being loaded, cached, or played
- **THEN** cleanup preserves that active entry even if storage temporarily remains above the configured limit

### Requirement: Cache failure degradation and platform scope
Cache inspection, writing, validation, cleanup, or local-source loading failures SHALL NOT crash playback or expose device paths. When the configured server remains reachable, the Android client SHALL fall back to the existing network playback path and surface only the existing non-sensitive playback failure behavior if neither local nor network media can be loaded. Browser playback SHALL retain its existing browser-managed buffering and source behavior without persistent audio caching.

#### Scenario: Cache storage is unavailable
- **WHEN** Android cannot create or update a cache entry but the audio endpoint remains reachable
- **THEN** the selected track continues through network playback without exposing the storage failure or device path

#### Scenario: A complete cache entry is unusable
- **WHEN** a nominally complete entry is missing, corrupt, or cannot be decoded
- **THEN** the client invalidates or bypasses that entry and attempts the track through the existing network playback path

#### Scenario: Run the browser client
- **WHEN** playback runs in a web browser
- **THEN** the client does not attempt app-private persistent audio caching and retains its existing browser playback behavior
