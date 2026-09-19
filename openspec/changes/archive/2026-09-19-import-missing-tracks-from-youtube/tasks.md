## 1. Configuration, Dependencies, and Persistence

- [x] 1.1 Add disabled-by-default acquisition settings and conservative validated limits for discovery, duration, bytes, free space, timeouts, retries, leases, concurrency, and retention; verify configuration tests cover defaults, environment overrides, and invalid combinations.
- [x] 1.2 Pin the required `yt-dlp` and JavaScript-support/runtime components in reproducible backend dependencies and image layers; verify the production image reports the expected tool versions without performing a runtime self-update.
- [x] 1.3 Add Alembic models and migration for durable acquisition jobs and track-source provenance, including state constraints, leases, relationships, and unique provider/external-ID identity; verify migration upgrade tests and repository schema tests pass on PostgreSQL.
- [x] 1.4 Add allow-listed API schemas and stable sanitized acquisition error types; verify schema tests reject extra, oversized, malformed, and sensitive fields.

## 2. Shared Storage and Import Pipeline

- [x] 2.1 Extend the storage abstraction with generated per-job staging workspaces, bounded file inspection, and idempotent cleanup while preventing path escape; verify storage tests cover creation, permitted writes, escape attempts, and recursive workspace cleanup.
- [x] 2.2 Refactor upload import so staged-file finalization is shared by uploads and acquisition jobs without changing existing upload behavior; verify all current import, duplicate, cleanup, and reconciliation tests remain green.
- [x] 2.3 Implement audio-output selection and compatibility normalization that prefers stream copy/remux and uses one configured fallback transcode only when required; verify fixture-based tests cover M4A/AAC, WebM Opus remuxing, incompatible input, timeout, and failed FFmpeg cleanup.
- [x] 2.4 Link normalized acquisition provenance transactionally to a new or content-duplicate track; verify tests cover new tracks, repeated video IDs, different video IDs with identical bytes, and provenance conflicts.

## 3. Experimental YouTube Provider

- [x] 3.1 Define the provider contract and short-lived integrity-protected candidate token format; verify tests cover valid round trips, expiry, tampering, provider mismatch, and key rotation behavior.
- [x] 3.2 Implement bounded yt-dlp candidate discovery with fixed subprocess arguments and strict structured-output parsing; verify unit tests return at most five eligible candidates and safely handle empty results, malformed output, hostile metadata, timeout, and provider failure.
- [x] 3.3 Implement fresh candidate revalidation and reject playlists, live/upcoming, authentication-gated, over-duration, and otherwise ineligible media; verify each eligibility rule has a deterministic failure-code test.
- [x] 3.4 Implement download-to-workspace with fixed server-side targets, an allow-listed environment, no shell, output/free-space monitoring, timeout termination, bounded stderr, and no cookie or arbitrary-option support; verify adversarial tests cannot inject flags, escape staging, exceed resource limits, or leak raw process data.
- [x] 3.5 Add sanitized structured provider and media-processing events keyed by job ID; verify log-capture tests contain phases, timings, bytes, retries, and stable errors but exclude raw commands, paths, secrets, and unbounded external output.

## 4. Durable Job Worker

- [x] 4.1 Implement job repository operations for enqueue, retrieval, row-locked claim, lease renewal, state transitions, completion, failure, cancellation, and expired-lease recovery; verify transition-table and concurrent-claim tests enforce the state machine and single ownership.
- [x] 4.2 Implement job creation idempotency using candidate identity and existing track provenance; verify repeated and concurrent requests resolve to one active job or the existing track without duplicate downloads.
- [x] 4.3 Implement the single-concurrency worker loop that revalidates, downloads, normalizes, imports, records provenance, and reaches a terminal state; verify integration tests cover success, content duplicate, provider error, process crash, retry exhaustion, and worker restart.
- [x] 4.4 Implement retention and abandoned-workspace cleanup without deleting referenced track media; verify time-controlled tests remove only expired jobs, candidate state, and staging artifacts.

## 5. Acquisition API

- [x] 5.1 Add candidate discovery, job creation, and job retrieval endpoints with feature-flag enforcement, trimmed inputs, stable status codes, and allow-listed responses; verify API tests cover enabled, disabled, invalid, expired, successful, empty, and provider-unavailable cases.
- [x] 5.2 Permit only the additional browser methods and headers required by the acquisition endpoints for configured origins; verify CORS tests allow the intended GET/POST requests and continue rejecting unconfigured origins.
- [x] 5.3 Keep acquisition dependencies outside normal API readiness while exposing their failures through acquisition responses and job state; verify health/readiness tests stay green when the feature is disabled or the provider is unavailable.

## 6. Flutter Discovery and Job Experience

- [x] 6.1 Add candidate, acquisition-job, and stable-error models plus catalog API methods for discovery, creation, and polling; verify HTTP contract tests cover serialization, URL handling, timeouts, and sanitized errors.
- [x] 6.2 Extend library state management to offer YouTube discovery only after the latest submitted local search returns empty and only after explicit owner action; verify controller tests prevent calls while typing, for stale searches, and when local results exist.
- [x] 6.3 Build candidate loading, empty, error, and review states with title, channel, duration, thumbnail, and canonical-page action; verify widget tests distinguish multiple candidates and never preselect or label one as correct.
- [x] 6.4 Add the experimental-warning confirmation dialog with an unchecked authorization acknowledgement and separate final action; verify widget tests cannot create a job before both explicit selection and acknowledgement.
- [x] 6.5 Add active-job polling, duplicate-submission prevention, remembered-job resume, terminal failure handling, catalog refresh, resulting-track reveal, and manual play action; verify controller and widget tests cover reconnect, restart, success, failure, retry, and no automatic playback.
- [x] 6.6 Preserve the normal local library experience when acquisition is disabled or unavailable; verify existing Flutter library, settings, search, pagination, and playback tests remain green.

## 7. Deployment and Operations

- [x] 7.1 Add a one-concurrency worker service using the backend image, PostgreSQL, and media volume with the existing unprivileged user and bounded container resources; verify `docker compose config` and a Compose integration test show correct dependencies, mounts, user, and restart behavior.
- [x] 7.2 Add placeholder acquisition settings to `.env.example` and document enablement, legal/provider warning, supported scope, limits, logs, failure recovery, dependency updates, disablement, and rollback; verify documentation contains no credentials and commands match the Compose configuration.
- [x] 7.3 Add a disabled-by-default operator smoke-test command using an authorized small public test asset; verify it reports discovery/toolchain health without importing when run in inspection-only mode.

## 8. End-to-End Validation

- [x] 8.1 Run the complete backend unit, PostgreSQL integration, migration, API, worker, security, and cleanup suites; verify all tests pass in the backend test image.
- [x] 8.2 Run Flutter formatting, static analysis, unit tests, and widget tests; verify every command completes successfully for the shared Android/web client.
- [x] 8.3 Build the production API, worker, and web images and run Compose health checks with acquisition disabled; verify existing upload, catalog search, range streaming, and web serving remain operational.
- [x] 8.4 Enable the feature only in an isolated private test deployment and complete one authorized end-to-end candidate search, approval, download, catalog refresh, and ranged playback; verify the job/provenance records, structured logs, limits, and staging cleanup match the specifications.
