"""Explicit Render pre-deploy job; never invoked by web workers."""
from pathlib import Path
from alembic import command
from alembic.config import Config
from sqlalchemy.orm import Session
from .config import Settings
from .database import make_engine
from .seed import seed_demo


def prepare(settings=None):
    settings = settings or Settings()
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = settings.database_url.get_secret_value()
    command.upgrade(config, "head")
    if settings.provision_test_beacon:
        engine = make_engine(settings.database_url.get_secret_value())
        try:
            with Session(engine) as session, session.begin():
                seed_demo(session)
        finally:
            engine.dispose()
        print("Explicit sample provisioning completed; existing assignments preserved.")
    print("Database migration completed.")


if __name__ == "__main__":
    prepare()
