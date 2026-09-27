"""Serialized account-schema rollout and private environment-only owner provisioning."""
from pathlib import Path
from alembic import command
from alembic.config import Config
from sqlalchemy import select, text
from sqlalchemy.orm import Session
from .models import User
from .bootstrap_manager import provision

def prepare_accounts(engine,settings):
    with engine.begin() as connection:
        if connection.dialect.name=='postgresql':
            # Serialize Alembic and bootstrap across overlapping deployment replicas.
            connection.execute(text('SELECT pg_advisory_xact_lock(724806190)'))
        config=Config(str(Path(__file__).resolve().parents[1]/'alembic.ini'))
        config.attributes['database_url']=settings.database_url.get_secret_value()
        config.attributes['connection']=connection
        command.upgrade(config,'head')
        email=settings.bootstrap_manager_email
        password=settings.bootstrap_manager_password
        if email is None and password is None:
            return
        if email is None or password is None:
            raise RuntimeError('Both private Manager bootstrap settings are required')
        with Session(bind=connection) as session:
            if connection.dialect.name=='postgresql':
                connection.execute(text('LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE'))
            if session.scalar(select(User.id).where(User.role=='manager').limit(1)) is not None:
                return  # Never reset credentials or create another owner on restart.
            try:
                provision(session,email.get_secret_value(),password.get_secret_value())
                session.flush()
            except ValueError:
                raise RuntimeError('Manager bootstrap settings are invalid or the account is unavailable') from None
