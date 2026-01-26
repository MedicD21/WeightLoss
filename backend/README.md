# Logged Fitness Tracker API

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
