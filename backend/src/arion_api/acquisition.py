"""Owner-facing discovery and durable acquisition job services."""

from __future__ import annotations

import time
from datetime import UTC, datetime
from uuid import UUID

from arion_api.acquisition_provider import (
    AcquisitionCandidate,
    CandidateTokenSigner,
    YouTubeProvider,
)
from arion_api.config import Settings
from arion_api.db import SessionFactory
from arion_api.errors import (
    AcquisitionFailure,
    AcquisitionJobNotFoundError,
    InvalidCandidateError,
    YouTubeAcquisitionDisabledError,
)
from arion_api.models import AcquisitionJob
from arion_api.repository import AcquisitionJobRepository
from arion_api.schemas import (
    AcquisitionCandidateSummary,
    AcquisitionJobResponse,
    YouTubeCandidateResponse,
)


def candidate_response(
    candidate: AcquisitionCandidate,
    token: str,
) -> YouTubeCandidateResponse:
    return YouTubeCandidateResponse(
        candidate_id=token,
        video_id=candidate.external_id,
        title=candidate.title,
        channel=candidate.channel,
        duration_seconds=candidate.duration_seconds,
        thumbnail_url=candidate.thumbnail_url,
        page_url=candidate.page_url,
    )


def job_response(job: AcquisitionJob) -> AcquisitionJobResponse:
    return AcquisitionJobResponse(
        id=job.id,
        state=job.state,
        phase=job.phase,
        progress_percent=job.progress_percent,
        attempts=job.attempts,
        candidate=AcquisitionCandidateSummary(
            video_id=job.external_id,
            title=job.candidate_title,
            channel=job.candidate_channel,
            duration_seconds=job.candidate_duration_seconds,
            thumbnail_url=job.candidate_thumbnail_url,
            page_url=job.candidate_page_url,
        ),
        track_id=job.track_id,
        failure_code=job.failure_code,
        failure_message=job.failure_message,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


class AcquisitionService:
    def __init__(
        self,
        settings: Settings,
        session_factory: SessionFactory,
        provider: YouTubeProvider,
        signer: CandidateTokenSigner,
    ) -> None:
        self.settings = settings
        self.session_factory = session_factory
        self.provider = provider
        self.signer = signer

    def _require_enabled(self) -> None:
        if not self.settings.youtube_acquisition_enabled:
            raise YouTubeAcquisitionDisabledError()

    def discover(self, query: str) -> list[YouTubeCandidateResponse]:
        self._require_enabled()
        candidates = self.provider.discover(query)
        now = int(time.time())
        return [
            candidate_response(
                candidate,
                self.signer.sign(
                    candidate,
                    now=now,
                    ttl_seconds=self.settings.youtube_candidate_ttl_seconds,
                ),
            )
            for candidate in candidates
        ]

    def create_job(self, token: str) -> AcquisitionJobResponse:
        self._require_enabled()
        try:
            candidate = self.signer.verify(token, now=int(time.time()))
        except AcquisitionFailure as error:
            raise InvalidCandidateError() from error
        now = datetime.now(UTC)
        with self.session_factory() as session, session.begin():
            repository = AcquisitionJobRepository(session)
            repository.lock_origin(candidate.provider, candidate.external_id)
            source = repository.find_source(candidate.provider, candidate.external_id)
            if source is not None:
                job = repository.add(
                    self._new_job(candidate, now, state="completed", track_id=source.track_id)
                )
                return job_response(job)
            active = repository.find_active(candidate.provider, candidate.external_id)
            if active is not None:
                return job_response(active)
            job = repository.add(self._new_job(candidate, now))
            return job_response(job)

    @staticmethod
    def _new_job(
        candidate: AcquisitionCandidate,
        now: datetime,
        *,
        state: str = "queued",
        track_id: UUID | None = None,
    ) -> AcquisitionJob:
        completed = state == "completed"
        return AcquisitionJob(
            provider=candidate.provider,
            external_id=candidate.external_id,
            candidate_title=candidate.title,
            candidate_channel=candidate.channel,
            candidate_duration_seconds=candidate.duration_seconds,
            candidate_thumbnail_url=candidate.thumbnail_url,
            candidate_page_url=candidate.page_url,
            authorization_acknowledged_at=now,
            state=state,
            phase=state,
            progress_percent=100 if completed else 0,
            attempts=0,
            track_id=track_id,
            updated_at=now,
        )

    def get_job(self, job_id: UUID) -> AcquisitionJobResponse:
        with self.session_factory() as session:
            job = AcquisitionJobRepository(session).get(job_id)
            if job is None:
                raise AcquisitionJobNotFoundError()
            return job_response(job)
