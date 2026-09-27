"""Hosting environment configuration regression tests; all credentials are fake."""
import pytest
from pydantic import ValidationError
from app.config import Settings

FAKE = 'postgresql://postgres.example:fake-password@aws-0-us-east-2.pooler.supabase.com:6543/postgres'

@pytest.fixture(autouse=True)
def clean_database_environment(monkeypatch):
    for name in ('AB_DATABASE_URL', 'DATABASE_URL', 'AB_ENVIRONMENT'):
        monkeypatch.delenv(name, raising=False)

@pytest.mark.parametrize('name', ['DATABASE_URL', 'AB_DATABASE_URL'])
@pytest.mark.parametrize('scheme', ['postgresql', 'postgres', 'postgresql+psycopg'])
def test_production_pooler_from_environment(monkeypatch, name, scheme):
    monkeypatch.setenv('AB_ENVIRONMENT', 'production')
    monkeypatch.setenv(name, FAKE.replace('postgresql://', scheme + '://'))
    settings = Settings(_env_file=None)
    assert settings.database_url.get_secret_value() == FAKE.replace('postgresql://', 'postgresql+psycopg://')
    assert 'fake-password' not in repr(settings)

@pytest.mark.parametrize('name', ['DATABASE_URL', 'AB_DATABASE_URL'])
def test_production_sqlite_is_rejected(monkeypatch, name):
    monkeypatch.setenv(name, 'sqlite:///./unsafe.db')
    with pytest.raises(ValidationError, match='Production requires PostgreSQL'):
        Settings(environment='production', _env_file=None)

def test_production_missing_configuration_is_rejected():
    with pytest.raises(ValidationError, match='Production requires PostgreSQL'):
        Settings(environment='production', _env_file=None)

@pytest.mark.parametrize('environment', ['development', 'test'])
def test_local_sqlite_default_unchanged(environment):
    assert Settings(environment=environment, _env_file=None).database_url.get_secret_value() == 'sqlite:///./beacon.db'

def test_namespaced_setting_takes_precedence(monkeypatch):
    monkeypatch.setenv('DATABASE_URL', 'sqlite:///./generic.db')
    monkeypatch.setenv('AB_DATABASE_URL', FAKE)
    assert Settings(environment='production', _env_file=None).database_url.get_secret_value().startswith('postgresql+psycopg://')

def test_constructor_field_still_supported(monkeypatch):
    monkeypatch.setenv('DATABASE_URL', 'sqlite:///./generic.db')
    assert Settings(environment='production', database_url=FAKE, _env_file=None).database_url.get_secret_value().startswith('postgresql+psycopg://')

def test_dotenv_generic_name(tmp_path):
    env_file = tmp_path / '.env'
    env_file.write_text('AB_ENVIRONMENT=production\nDATABASE_URL=' + FAKE + '\n')
    assert Settings(_env_file=env_file).database_url.get_secret_value().startswith('postgresql+psycopg://')

def test_unsupported_driver_is_not_silently_accepted():
    with pytest.raises(ValidationError, match='Use sqlite or postgresql'):
        Settings(environment='production', database_url=FAKE.replace('postgresql://', 'postgresql+asyncpg://'), _env_file=None)
