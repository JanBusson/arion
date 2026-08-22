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
