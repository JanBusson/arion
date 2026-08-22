"""Synchronous PostgreSQL engine and session lifecycle."""

from collections.abc import Generator

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker

from arion_api.config import Settings

SessionFactory = sessionmaker[Session]


def create_database_engine(settings: Settings) -> Engine:
    """Create an engine without opening a database connection eagerly."""

    return create_engine(
        settings.database_url.get_secret_value(),
        pool_pre_ping=True,
        connect_args={"connect_timeout": 3},
    )


def create_session_factory(engine: Engine) -> SessionFactory:
    return sessionmaker(bind=engine, expire_on_commit=False)


def session_scope(factory: SessionFactory) -> Generator[Session, None, None]:
    """Yield one session and always close it."""

    session = factory()
    try:
        yield session
    finally:
        session.close()
