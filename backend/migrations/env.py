from alembic import context
from app.config import Settings
from app.database import make_engine
from app.models import Base

config = context.config
url = config.attributes.get("database_url") or Settings().database_url.get_secret_value()

if context.is_offline_mode():
    context.configure(url=url, target_metadata=Base.metadata, literal_binds=True,
        dialect_opts={"paramstyle": "named"})
    with context.begin_transaction():
        context.run_migrations()
elif config.attributes.get('connection') is not None:
    context.configure(connection=config.attributes['connection'], target_metadata=Base.metadata, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()
else:
    engine = make_engine(url)
    try:
        with engine.connect() as connection:
            context.configure(connection=connection, target_metadata=Base.metadata, compare_type=True)
            with context.begin_transaction():
                context.run_migrations()
    finally:
        engine.dispose()
