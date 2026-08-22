from __future__ import annotations

import os
from collections.abc import Iterator

import pytest
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from arion_api.models import Base


@pytest.fixture
def postgres_engine() -> Iterator[Engine]:
    url = os.getenv("ARION_TEST_DATABASE_URL")
    if not url:
        pytest.skip("ARION_TEST_DATABASE_URL is required for PostgreSQL integration tests")
    engine = create_engine(url, pool_pre_ping=True)
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    try:
        yield engine
    finally:
        Base.metadata.drop_all(engine)
        engine.dispose()


@pytest.fixture
def postgres_session_factory(
    postgres_engine: Engine,
) -> sessionmaker[Session]:
    return sessionmaker(bind=postgres_engine, expire_on_commit=False)
