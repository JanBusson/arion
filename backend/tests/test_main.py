from fastapi import FastAPI
from fastapi.testclient import TestClient

from arion_api.config import Settings
from arion_api.main import app, create_app


def test_module_exposes_fastapi_application() -> None:
    assert isinstance(app, FastAPI)


def test_application_starts_with_default_configuration() -> None:
    settings = Settings(_env_file=None)
    application = create_app(settings)

    with TestClient(application):
        assert application.state.settings is settings
