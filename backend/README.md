# Logged Fitness Tracker API

## Docker (Production)

Use the production compose file for a non-reload setup:
```
docker compose -f docker-compose.prod.yml up --build -d
```

Notes:
- Create a `.env` based on `.env.example` before starting.
- For database migrations, run: `python scripts/migrate.py` inside the api container.

## Migrations (Alembic)

The schema is managed by Alembic. Use this workflow for changes:

1) Create a new migration after updating models:
```
alembic revision --autogenerate -m "describe change"
```

2) Apply migrations to main + auth databases:
```
python scripts/migrate.py
```

Notes:
- `scripts/migrate.py` upgrades `DATABASE_URL` and also `AUTH_DATABASE_URL` when it is different.
- Automatic `create_all()` is disabled by default. If you need it in dev, set `DB_AUTO_INIT=true` or `DEBUG=true`.
