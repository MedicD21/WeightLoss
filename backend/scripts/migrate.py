"""Run Alembic migrations for main and auth databases."""
import os
import sys
from alembic import command
from alembic.config import Config

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from app.config import get_settings  # noqa: E402


def _upgrade(url: str, label: str) -> None:
    cfg = Config("alembic.ini")
    cfg.set_main_option("sqlalchemy.url", url)
    cfg.set_main_option("sqlalchemy.url.label", label)
    command.upgrade(cfg, "head")


def main() -> None:
    settings = get_settings()

    _upgrade(settings.database_url, "main")

    if settings.auth_database_url and settings.auth_database_url != settings.database_url:
        _upgrade(settings.auth_database_url, "auth")


if __name__ == "__main__":
    main()
