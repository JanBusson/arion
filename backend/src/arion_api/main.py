"""FastAPI application entry point."""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from uuid import UUID

from fastapi import FastAPI, Query, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse, Response, StreamingResponse
from sqlalchemy import select
from sqlalchemy.orm import Session
from starlette.datastructures import UploadFile

from arion_api import __version__
from arion_api.config import Settings, get_settings
from arion_api.db import SessionFactory, create_database_engine, create_session_factory
from arion_api.errors import (
    ArionError,
    AudioNotFoundError,
    CoverNotFoundError,
    DuplicateTrackError,
    TrackNotFoundError,
)
from arion_api.metadata import MediaInspector
from arion_api.models import Track
from arion_api.repository import TrackRepository
from arion_api.schemas import TrackListResponse, TrackPatch, TrackResponse
from arion_api.services import ImportService, reconcile_storage
from arion_api.storage import LocalMediaStorage, StorageKey
from arion_api.streaming import InvalidByteRange, parse_byte_range

logger = logging.getLogger(__name__)


def _error_body(error: ArionError) -> dict[str, object]:
    detail: dict[str, object] = {
        "code": error.code,
        "message": error.public_message,
    }
    if isinstance(error, DuplicateTrackError):
        detail["existing_track_id"] = str(error.existing_track_id)
    return {"detail": detail}


def create_app(
    settings: Settings | None = None,
    *,
    session_factory: SessionFactory | None = None,
    storage: LocalMediaStorage | None = None,
    inspector: MediaInspector | None = None,
) -> FastAPI:
    """Create the Arion API while deferring external connections until use."""

    selected_settings = settings or get_settings()
    selected_factory = session_factory
    if selected_factory is None:
        engine = create_database_engine(selected_settings)
        selected_factory = create_session_factory(engine)
    selected_storage = storage or LocalMediaStorage(selected_settings.media_root)
    selected_inspector = inspector or MediaInspector(
        selected_settings.ffprobe_executable,
        selected_settings.ffprobe_timeout_seconds,
    )

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        try:
            await run_in_threadpool(
                reconcile_storage,
                application.state.session_factory,
                application.state.storage,
                application.state.settings.reconciliation_grace_seconds,
            )
        except Exception:
            logger.warning("Startup media reconciliation skipped: database unavailable")
        yield

    application = FastAPI(
        title="Arion API", version=__version__, lifespan=lifespan
    )
    application.state.settings = selected_settings
    application.state.session_factory = selected_factory
    application.state.storage = selected_storage
    application.state.inspector = selected_inspector
    application.state.import_service = ImportService(
        selected_factory,
        selected_storage,
        selected_inspector,
        selected_settings.max_upload_bytes,
    )

    @application.exception_handler(ArionError)
    async def handle_arion_error(
        _request: Request, error: ArionError
    ) -> JSONResponse:
        return JSONResponse(status_code=error.status_code, content=_error_body(error))

    @application.get("/health", include_in_schema=False)
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @application.get("/ready", include_in_schema=False)
    def ready(request: Request) -> Response:
        dependencies = {"database": "ready", "storage": "ready"}
        try:
            with request.app.state.session_factory() as session:
                session.scalar(select(Track.id).limit(1))
        except Exception:
            dependencies["database"] = "unavailable"
        if not request.app.state.storage.probe_ready():
            dependencies["storage"] = "unavailable"
        if all(value == "ready" for value in dependencies.values()):
            return JSONResponse(status_code=200, content={"status": "ready"})
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "dependencies": dependencies},
        )

    @application.post(
        "/api/v1/tracks/import", response_model=TrackResponse, status_code=201
    )
    async def import_track(request: Request) -> Track:
        form = await request.form()
        entries = list(form.multi_items())
        if (
            len(entries) != 1
            or entries[0][0] != "file"
            or not isinstance(entries[0][1], UploadFile)
        ):
            return JSONResponse(  # type: ignore[return-value]
                status_code=422,
                content={
                    "detail": {
                        "code": "invalid_upload",
                        "message": "Exactly one multipart file field named 'file' is required.",
                    }
                },
            )
        upload = entries[0][1]
        try:
            return await run_in_threadpool(
                request.app.state.import_service.import_file,
                upload.file,
                upload.filename or "upload",
            )
        finally:
            await upload.close()

    @application.get("/api/v1/tracks", response_model=TrackListResponse)
    def list_tracks(
        request: Request,
        limit: int = Query(default=50, ge=1, le=100),
        offset: int = Query(default=0, ge=0),
        q: str | None = Query(default=None),
    ) -> TrackListResponse:
        with request.app.state.session_factory() as session:
            items, total = TrackRepository(session).list(
                query=q, limit=limit, offset=offset
            )
            return TrackListResponse(
                items=[TrackResponse.model_validate(item) for item in items],
                total=total,
                limit=limit,
                offset=offset,
            )

    @application.get("/api/v1/tracks/{track_id}", response_model=TrackResponse)
    def get_track(track_id: UUID, request: Request) -> Track:
        with request.app.state.session_factory() as session:
            track = TrackRepository(session).get(track_id)
            if track is None:
                raise TrackNotFoundError()
            return track

    @application.patch("/api/v1/tracks/{track_id}", response_model=TrackResponse)
    def patch_track(track_id: UUID, patch: TrackPatch, request: Request) -> Track:
        with request.app.state.session_factory() as session:
            with session.begin():
                repository = TrackRepository(session)
                track = repository.get(track_id)
                if track is None:
                    raise TrackNotFoundError()
                return repository.update_text(
                    track,
                    title=patch.title,
                    artist=patch.artist,
                    album=patch.album,
                )

    @application.get("/api/v1/tracks/{track_id}/cover")
    def get_cover(track_id: UUID, request: Request) -> Response:
        with request.app.state.session_factory() as session:
            track = TrackRepository(session).get(track_id)
            if track is None:
                raise TrackNotFoundError()
            if not track.cover_storage_key or not track.cover_media_type:
                raise CoverNotFoundError()
            try:
                content = request.app.state.storage.read_bytes(
                    StorageKey(track.cover_storage_key)
                )
            except (OSError, ValueError):
                raise CoverNotFoundError() from None
            return Response(content=content, media_type=track.cover_media_type)

    @application.get("/api/v1/tracks/{track_id}/audio")
    def get_audio(track_id: UUID, request: Request) -> Response:
        with request.app.state.session_factory() as session:
            track = TrackRepository(session).get(track_id)
            if track is None:
                raise TrackNotFoundError()
            try:
                audio_key = StorageKey(track.audio_storage_key)
                info = request.app.state.storage.audio_info(audio_key)
            except (OSError, ValueError):
                raise AudioNotFoundError() from None

        common_headers = {
            "Accept-Ranges": "bytes",
            "Content-Length": str(info.size),
        }
        range_header = request.headers.get("range")
        if range_header is None:
            try:
                content = (
                    request.app.state.storage.iter_bytes(
                        audio_key, 0, info.size - 1
                    )
                    if info.size
                    else iter(())
                )
            except (OSError, ValueError):
                raise AudioNotFoundError() from None
            return StreamingResponse(
                content,
                status_code=200,
                media_type=info.media_type,
                headers=common_headers,
            )

        try:
            selected = parse_byte_range(range_header, info.size)
        except InvalidByteRange:
            return Response(
                status_code=416,
                headers={
                    "Accept-Ranges": "bytes",
                    "Content-Range": f"bytes */{info.size}",
                    "Content-Length": "0",
                },
            )

        try:
            content = request.app.state.storage.iter_bytes(
                audio_key, selected.start, selected.end
            )
        except (OSError, ValueError):
            raise AudioNotFoundError() from None
        return StreamingResponse(
            content,
            status_code=206,
            media_type=info.media_type,
            headers={
                "Accept-Ranges": "bytes",
                "Content-Length": str(selected.length),
                "Content-Range": (
                    f"bytes {selected.start}-{selected.end}/{info.size}"
                ),
            },
        )

    return application


app = create_app()
