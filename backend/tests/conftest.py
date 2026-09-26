from datetime import datetime, timezone
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.config import Settings
from app.database import make_engine
from app.main import create_app, get_now
from app.seed import seed_demo

NOW = datetime(2026, 9, 25, 12, tzinfo=timezone.utc)
ROOT = Path(__file__).resolve().parents[1]


def migration_config(url):
    config = Config(str(ROOT / "alembic.ini"))
    config.attributes["database_url"] = url
    return config


@pytest.fixture
def engine(tmp_path):
    url = f"sqlite:///{(tmp_path / 'test.db').as_posix()}"
    command.upgrade(migration_config(url), "head")
    result = make_engine(url)
    with Session(result) as session, session.begin():
        seed_demo(session)
    yield result
    result.dispose()


@pytest.fixture
def session(engine):
    with Session(engine) as result:
        yield result


@pytest.fixture
def client(engine):
    app = create_app(Settings(environment="test", _env_file=None), engine=engine)
    app.dependency_overrides[get_now] = lambda: NOW
    with TestClient(app) as result:
        yield result
