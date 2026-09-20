from __future__ import annotations

import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import Engine, inspect, text

from arion_api.models import Base


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def test_alembic_upgrade_creates_acquisition_schema(
    postgres_engine: Engine, monkeypatch: pytest.MonkeyPatch
) -> None:
    url = os.environ["ARION_TEST_DATABASE_URL"]
    Base.metadata.drop_all(postgres_engine)
    with postgres_engine.begin() as connection:
        connection.execute(text("DROP TABLE IF EXISTS alembic_version"))
    monkeypatch.setenv("ARION_DATABASE_URL", url)
    configuration = Config(str(BACKEND_ROOT / "alembic.ini"))

    try:
        command.upgrade(configuration, "head")
        tables = set(inspect(postgres_engine).get_table_names())
        assert {"tracks", "acquisition_jobs", "track_sources"} <= tables
        constraints = inspect(postgres_engine).get_unique_constraints("track_sources")
        assert any(item["name"] == "uq_track_sources_origin" for item in constraints)
    finally:
        Base.metadata.drop_all(postgres_engine)
        with postgres_engine.begin() as connection:
            connection.execute(text("DROP TABLE IF EXISTS alembic_version"))
