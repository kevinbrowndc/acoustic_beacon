import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import text
from app.config import Settings
from app.database import make_engine
from app.deploy import prepare
from app.main import create_app


def test_render_url_normalization():
    for scheme in ['postgres', 'postgresql']:
        settings = Settings(environment='production', database_url=f'{scheme}://user:pass@localhost/db', _env_file=None)
        assert settings.database_url.get_secret_value() == 'postgresql+psycopg://user:pass@localhost/db'
        assert 'pass' not in repr(settings.database_url)


def test_health_checks(client):
    assert client.get('/health/live').json() == {'status': 'ok'}
    response = client.get('/health/ready')
    assert response.status_code == 200
    assert response.json() == {'status': 'ready'}
    assert response.headers['cache-control'] == 'no-store'


def test_readiness_missing_schema_is_generic():
    engine = make_engine('sqlite:///:memory:')
    with TestClient(create_app(Settings(_env_file=None), engine=engine)) as client:
        response = client.get('/health/ready')
        assert response.status_code == 503
        assert response.json() == {'detail': 'Content temporarily unavailable'}
    engine.dispose()


def test_readiness_wrong_revision(client, engine):
    with engine.begin() as connection:
        connection.execute(text("UPDATE alembic_version SET version_num='old'"))
    assert client.get('/health/ready').status_code == 503


def test_cors_explicit_allowlist(engine):
    settings = Settings(cors_origins=['https://consumer.example.com'], _env_file=None)
    with TestClient(create_app(settings, engine=engine)) as client:
        assert client.get('/health/live', headers={'Origin': 'https://consumer.example.com'}).headers['access-control-allow-origin'] == 'https://consumer.example.com'
        assert 'access-control-allow-origin' not in client.get('/health/live', headers={'Origin': 'https://untrusted.example.com'}).headers
    with pytest.raises(ValidationError):
        Settings(cors_origins=['*'], _env_file=None)


def test_predeploy_migrates_and_explicitly_provisions_sample(tmp_path):
    url = f"sqlite:///{(tmp_path / 'deployment.db').as_posix()}"
    settings = Settings(database_url=url, provision_test_beacon=True, _env_file=None)
    prepare(settings)
    prepare(settings)
    engine = make_engine(url)
    with TestClient(create_app(settings, engine=engine)) as client:
        assert client.get('/health/ready').status_code == 200
        response = client.get('/api/v1/beacons/0xABC123/offers').json()
        assert response['offers'][0]['title'] == 'wookiemeat'
        assert response['campaign']['sample'] is True
        assert len(response['offers']) == 1
    engine.dispose()


def test_predeploy_does_not_seed_by_default(tmp_path):
    settings = Settings(database_url=f"sqlite:///{(tmp_path / 'empty.db').as_posix()}", _env_file=None)
    prepare(settings)
    engine = make_engine(settings.database_url.get_secret_value())
    with TestClient(create_app(settings, engine=engine)) as client:
        assert client.get('/health/ready').status_code == 200
        assert client.get('/api/v1/beacons/0xABC123/offers').status_code == 404
    engine.dispose()
