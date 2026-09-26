from datetime import timedelta
from io import StringIO

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from pydantic import ValidationError
from sqlalchemy import inspect, select
from sqlalchemy.exc import IntegrityError

from app.config import Settings
from app.models import Base, Beacon, Campaign, CampaignOffer, Merchant, Offer, User
from app.schemas import OfferInput
from app.seed import seed_demo
from conftest import NOW, migration_config


@pytest.mark.parametrize("model,field,value", [
    (User, "role", "admin"),
    (User, "email", "UPPER@example.invalid"),
    (Merchant, "latitude", 91),
    (Merchant, "latitude", 40),  # longitude missing
    (Offer, "merchant_id", 999999),
    (Campaign, "merchant_id", None),
    (Campaign, "manager_user_id", 1),  # ambiguous ownership
    (Beacon, "payload_id", 16777216),
    (Beacon, "payload_id", -1),
    (CampaignOffer, "display_order", -1),
])
def test_database_rejects_invalid_state(session, model, field, value):
    setattr(session.scalar(select(model)), field, value)
    with pytest.raises(IntegrityError):
        session.flush()
    session.rollback()


@pytest.mark.parametrize("model", [Offer, Campaign])
def test_database_rejects_reversed_dates(session, model):
    row = session.scalar(select(model))
    row.start_at, row.end_at = NOW, NOW - timedelta(seconds=1)
    with pytest.raises(IntegrityError):
        session.flush()
    session.rollback()


def test_unique_payload(session):
    source = session.scalar(select(Beacon))
    session.add(Beacon(payload_id=source.payload_id, owner_user_id=source.owner_user_id))
    with pytest.raises(IntegrityError):
        session.flush()
    session.rollback()


def test_seed_idempotent_and_preserves_edits(session):
    offer = session.scalar(select(Offer))
    offer.title = "Merchant's updated title"
    seed_demo(session)
    seed_demo(session)
    assert len(session.scalars(select(Beacon)).all()) == 1
    assert len(session.scalars(select(Offer)).all()) == 1
    assert offer.title == "Merchant's updated title"


@pytest.mark.parametrize("changes", [
    {"title": " "}, {"start_at": "2026-09-25T12:00:00"},
    {"image_url": "http://example.com/a.png"},
    {"image_url": "https://user:pass@example.com/a.png"},
    {"image_url": "javascript:alert(1)"},
    {"merchant_id": 2},
    {"start_at": NOW, "end_at": NOW},
])
def test_domain_input_validation(changes):
    data = {"title": "Test", "description": "Test", "terms": "Test", **changes}
    with pytest.raises(ValidationError):
        OfferInput(**data)


def test_production_cannot_use_sqlite():
    with pytest.raises(ValidationError):
        Settings(environment="production", database_url="sqlite:///x.db", _env_file=None)


def test_migration_matches_models_and_roundtrips(engine):
    with engine.connect() as connection:
        assert compare_metadata(MigrationContext.configure(connection), Base.metadata) == []
    config = migration_config(str(engine.url))
    command.downgrade(config, "base")
    assert set(inspect(engine).get_table_names()) <= {"alembic_version"}
    command.upgrade(config, "head")
    assert set(Base.metadata.tables).issubset(inspect(engine).get_table_names())


def test_postgresql_migration_compiles_offline():
    config = migration_config("postgresql+psycopg://unused:unused@localhost/unused")
    buffer = StringIO()
    config.output_buffer = buffer
    command.upgrade(config, "head", sql=True)
    sql = buffer.getvalue()
    assert "CREATE TABLE beacons" in sql
    assert "TIMESTAMP WITH TIME ZONE" in sql
    assert "ck_campaign_one_owner" in sql
