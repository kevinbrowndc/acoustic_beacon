from sqlalchemy import create_engine, event
from sqlalchemy.pool import StaticPool


def make_engine(url: str):
    options = {"pool_pre_ping": True}
    if url.startswith("sqlite:"):
        options["connect_args"] = {"check_same_thread": False}
        if url in {"sqlite://", "sqlite:///:memory:"}:
            options["poolclass"] = StaticPool
    else:
        options["connect_args"] = {"connect_timeout": 5, "options": "-c statement_timeout=8000"}
        options["pool_size"] = 5
        options["max_overflow"] = 5
        options["pool_timeout"] = 5
    engine = create_engine(url, **options)
    if engine.dialect.name == "sqlite":
        @event.listens_for(engine, "connect")
        def enable_foreign_keys(connection, _):
            cursor = connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()
    return engine
