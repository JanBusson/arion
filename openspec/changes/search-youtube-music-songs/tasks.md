## 1. Dependency and Discovery Contract

- [x] 1.1 Add an exactly pinned `ytmusicapi` runtime dependency, regenerate the backend lockfile, and verify the production backend image imports it and reports the expected version without credentials or runtime self-update.
- [x] 1.2 Add the allow-listed `music`/`all` discovery-mode model with server-side `music` default and response serialization; verify schema tests reject unsupported, oversized, and extra values.
- [x] 1.3 Extend the signed candidate representation with its discovery mode while preserving YouTube video-ID provenance; verify token tests cover both modes, expiry, tampering, missing fields, and provider mismatch.

## 2. Music and Broad Provider Routing

- [x] 2.1 Preserve the current fixed-argument yt-dlp discovery behavior as the `all` adapter; verify existing broad-search, hostile-input, timeout, eligibility, and result-limit tests remain green.
- [x] 2.2 Implement an unauthenticated YouTube Music adapter that calls only Songs search with the configured timeout, strictly validates untrusted song rows, constructs canonical page/thumbnail URLs from valid IDs, and locally caps results; verify fixtures cover artists, optional duration, malformed rows, excessive upstream results, timeout, protocol failure, and absence of credentials.
- [x] 2.3 Route discovery by validated mode without automatic fallback and emit sanitized mode/count/duration/failure events; verify tests prove an empty or failed music search never calls the broad adapter and logs contain neither query text nor raw provider output.
- [x] 2.4 Keep approval, revalidation, download, duplicate handling, metadata fallback, and provenance common to both discovery modes; verify integration tests resolve the same video ID from either mode to one provenance identity and require no database migration.

## 3. API and Operational Support

- [x] 3.1 Extend the candidate endpoint with the optional mode parameter and stable default/error behavior; verify API tests cover omitted, explicit music, explicit all, invalid, disabled, empty, and provider-unavailable requests without creating jobs.
- [x] 3.2 Extend the inspection-only acquisition smoke command to report the pinned music-search dependency and exercise either discovery mode without importing; verify command tests cover both modes and reject unsupported input.
- [x] 3.3 Document the music-first default, broad remix escape hatch, no-fallback behavior, dependency update procedure, sanitized diagnostics, and rollback; verify examples match the API and Compose configuration and contain no credentials.

## 4. Flutter Mode Selection

- [x] 4.1 Add the discovery-mode enum and mode-aware catalog API serialization/response validation; verify HTTP contract tests send `music` or `all`, default client state uses music, and mismatched result modes are rejected safely.
- [x] 4.2 Extend library controller state with session-scoped mode selection, candidate/error clearing, and query-plus-mode stale-response protection; verify controller tests make no external call on typing or selection, discard late old-mode results, and preserve active acquisition jobs.
- [x] 4.3 Add mutually exclusive `Music` and `All` radio controls associated with the search field plus mode-specific action/result labels and artist presentation; verify widget tests cover default selection, switching, explicit discovery, candidate clearing, no preselection, and narrow Android/wide browser layouts without overflow.

## 5. Regression and End-to-End Verification

- [x] 5.1 Run the complete backend unit, PostgreSQL integration, API, provider, worker, security, cleanup, and migration suites; verify all tests pass in the backend test image.
- [x] 5.2 Run Flutter formatting, static analysis, unit tests, and widget tests; verify every command succeeds for the shared Android/web client.
- [x] 5.3 Build production API, worker, and web images and run Compose checks with acquisition disabled; verify existing upload, local search, broad acquisition compatibility, catalog playback, and web serving remain operational.
- [x] 5.4 Enable acquisition only in an isolated private deployment, verify real music and all discovery for the same query, switch modes without mixed results, and complete one authorized acquisition with catalog refresh and ranged playback; verify provenance, sanitized logs, limits, and staging cleanup before any live rollout.
