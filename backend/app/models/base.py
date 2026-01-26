"""Base model and database setup."""
import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import MetaData, DateTime, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncAttrs, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.engine.url import make_url

from app.config import get_settings

settings = get_settings()

# Naming convention for constraints
convention = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(AsyncAttrs, DeclarativeBase):
    """Base class for all models."""

    metadata = MetaData(naming_convention=convention)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    def to_dict(self) -> dict[str, Any]:
        """Convert model to dictionary."""
        return {c.name: getattr(self, c.name) for c in self.__table__.columns}


# Database engine and session
def _build_engine_params(database_url: str) -> tuple[str, dict]:
    """Normalize asyncpg URL options and return (url, connect_args)."""
    url = make_url(database_url)
    query = dict(url.query)
    connect_args: dict = {}

    sslmode = query.pop("sslmode", None)
    if sslmode and sslmode.lower() != "disable":
        connect_args["ssl"] = True

    # libpq-only options; asyncpg does not accept these as kwargs
    query.pop("channel_binding", None)

    return url.set(query=query).render_as_string(hide_password=False), connect_args


database_url, database_connect_args = _build_engine_params(settings.database_url)
engine = create_async_engine(
    database_url,
    echo=settings.database_echo,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
    connect_args=database_connect_args,
)

auth_db_url = settings.auth_database_url or settings.database_url
auth_url, auth_connect_args = _build_engine_params(auth_db_url)
auth_engine = create_async_engine(
    auth_url,
    echo=settings.database_echo,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    connect_args=auth_connect_args,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)

AsyncAuthSessionLocal = async_sessionmaker(
    auth_engine,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def get_db():
    """Dependency to get database session."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def get_auth_db():
    """Dependency to get auth database session."""
    async with AsyncAuthSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db():
    """Initialize database tables."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def init_auth_db():
    """Initialize auth database tables."""
    async with auth_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
