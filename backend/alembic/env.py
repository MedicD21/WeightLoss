import os
import sys
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine.url import make_url
from sqlalchemy.ext.asyncio import create_async_engine

from alembic import context

# this is the Alembic Config object, which provides access to the values
# within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Ensure app module is on path when running via alembic CLI.
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

# Import models to register metadata.
from app.models.base import Base  # noqa: E402
from app.models import user, nutrition, workout, tracking, chat  # noqa: E402,F401
from app.config import get_settings  # noqa: E402

target_metadata = Base.metadata


def _normalize_url(database_url: str) -> tuple[str, dict]:
    url = make_url(database_url)
    query = dict(url.query)
    connect_args: dict = {}

    sslmode = query.pop("sslmode", None)
    if sslmode and sslmode.lower() != "disable":
        connect_args["ssl"] = True

    # libpq-only options; asyncpg does not accept these as kwargs
    query.pop("channel_binding", None)

    return url.set(query=query).render_as_string(hide_password=False), connect_args


def get_database_url() -> str:
    return os.getenv("DATABASE_URL") or get_settings().database_url


def run_migrations_offline() -> None:
    url, _ = _normalize_url(get_database_url())
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        compare_type=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    url, connect_args = _normalize_url(get_database_url())
    connectable = create_async_engine(
        url,
        poolclass=pool.NullPool,
        connect_args=connect_args,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    import asyncio

    asyncio.run(run_migrations_online())
