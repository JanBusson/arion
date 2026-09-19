## ADDED Requirements

### Requirement: Acquisition import parity
The system SHALL route audio produced by an approved acquisition job through the same technical inspection, supported-format validation, metadata fallback, SHA-256 duplicate protection, cover handling, durable storage promotion, and catalog persistence guarantees as a multipart upload. It SHALL expose neither temporary paths nor durable storage references through the acquisition API.

#### Scenario: Import acquired supported audio
- **WHEN** an approved acquisition job produces valid supported audio within configured limits
- **THEN** the system creates a normal catalog track with the same validation and durability guarantees as an uploaded file

#### Scenario: Reject acquired invalid media
- **WHEN** an acquisition produces missing, unreadable, or unsupported audio
- **THEN** the job fails, no catalog entry is created, and staged and unreferenced output is removed

### Requirement: Compatibility-preserving media normalization
Before normal import validation, the acquisition workflow SHALL select an audio-only source and place it in a container supported by Arion's Android and browser clients. It SHALL preserve the original audio stream without lossy transcoding when compatible remuxing is possible and SHALL transcode at most once only when required for supported playback.

#### Scenario: Remux compatible source audio
- **WHEN** acquired audio uses a supported codec in an unsupported source container and can be remuxed into a supported container
- **THEN** the system remuxes without re-encoding and imports the normalized audio

#### Scenario: Transcode incompatible source audio
- **WHEN** no compatible audio-only stream can be imported or remuxed for supported playback
- **THEN** the system performs one bounded transcode to the configured fallback format and submits that result to normal import validation

### Requirement: Acquisition metadata provenance
The system SHALL preserve the provider name, YouTube video identifier, canonical source page, candidate title, candidate channel, and acquisition time as internal provenance linked to the resulting track. Provider metadata SHALL be treated as untrusted input, SHALL be length-bounded and normalized, and SHALL not override later owner metadata corrections.

#### Scenario: Preserve provenance after successful import
- **WHEN** an acquisition job creates a new track
- **THEN** its source provenance remains linked to that track across service restarts without exposing internal storage locations
