"""Safe domain errors that can be mapped to public API responses."""

from uuid import UUID


class ArionError(Exception):
    status_code = 500
    code = "internal_error"
    public_message = "The request could not be completed."


class ImportTooLargeError(ArionError):
    status_code = 413
    code = "upload_too_large"
    public_message = "The uploaded file exceeds the configured size limit."


class UnsupportedMediaError(ArionError):
    status_code = 415
    code = "unsupported_media"
    public_message = "The uploaded content is not a supported audio format."


class UnreadableMediaError(ArionError):
    status_code = 422
    code = "unreadable_media"
    public_message = "The uploaded audio could not be inspected."


class DuplicateTrackError(ArionError):
    status_code = 409
    code = "duplicate_track"
    public_message = "This audio file has already been imported."

    def __init__(self, existing_track_id: UUID) -> None:
        super().__init__(self.public_message)
        self.existing_track_id = existing_track_id


class TrackNotFoundError(ArionError):
    status_code = 404
    code = "track_not_found"
    public_message = "Track not found."


class CoverNotFoundError(ArionError):
    status_code = 404
    code = "cover_not_found"
    public_message = "Cover art not found."


class AudioNotFoundError(ArionError):
    status_code = 404
    code = "audio_not_found"
    public_message = "Track audio not found."


class YouTubeAcquisitionDisabledError(ArionError):
    status_code = 503
    code = "youtube_acquisition_disabled"
    public_message = "YouTube acquisition is disabled on this server."


class YouTubeProviderUnavailableError(ArionError):
    status_code = 502
    code = "youtube_provider_unavailable"
    public_message = "YouTube discovery is temporarily unavailable."


class InvalidCandidateError(ArionError):
    status_code = 409
    code = "invalid_candidate"
    public_message = "The selected candidate is invalid or has expired."


class AcquisitionJobNotFoundError(ArionError):
    status_code = 404
    code = "acquisition_job_not_found"
    public_message = "Acquisition job not found."


class AcquisitionFailure(Exception):
    """Internal worker failure with a safe public classification."""

    def __init__(self, code: str, public_message: str) -> None:
        super().__init__(public_message)
        self.code = code[:64]
        self.public_message = public_message[:512]
