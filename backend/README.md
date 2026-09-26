# Acoustic Beacon backend — Phase 1

Standalone campaign-resolution service. The Flutter application and acoustic decoder are unchanged and are not connected to this service yet. No production deployment, authentication system, merchant dashboard, or write API is included.

## Local setup

Use Python 3.12 or later. Run these PowerShell commands from this `backend` directory:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-lock.txt
$env:AB_ENVIRONMENT = 'development'
$env:AB_DATABASE_URL = 'sqlite:///./beacon.db'
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m app.seed
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Open `http://127.0.0.1:8000/docs` for the development API documentation. On Linux/macOS use `.venv/bin/python` and `export AB_ENVIRONMENT=development` / `export AB_DATABASE_URL=sqlite:///./beacon.db`.

PostgreSQL is the intended production database. For an existing empty development PostgreSQL database, set `AB_DATABASE_URL` to `postgresql+psycopg://USER:PASSWORD@HOST:5432/DATABASE` using your own credentials (URL-encode reserved characters), then run the same migration and optional development seed commands. Alternatively copy `.env.example` to `.env` and replace every placeholder. Environment variables override that file. Never commit credentials or `.env` files. Production mode rejects SQLite and refuses the seed command.

The server does not create tables or seed records on startup. Run migrations explicitly using a separate migration credential. Provision a least-privilege, SELECT-only PostgreSQL role for the public service; the route also starts a read-only PostgreSQL transaction. Use TLS, a secret manager, monitoring, rate limiting and deployment-specific database configuration before public hosting.

## Public contract

`GET /api/v1/beacons/0xABC123/offers`

Accepts exactly six hexadecimal digits with an optional `0x` prefix. The response normalizes the ID to `0xABC123`. It contains `beacon_id`, nullable `campaign`, and an `offers` array. Campaign fields are `id`, `name`, and `sample`. Each offer contains `id`, `title`, `description`, `terms`, `image_url`, `start_at`, `end_at`, and its `merchant`. Merchant fields include identity, description, `address`, `city`, `country_code` and nullable stored coordinates. Public record IDs are UUIDs; internal numeric keys and user emails are not exposed. See `/docs` for the complete generated schema.

* Unknown or inactive beacon: 404, `Beacon unavailable`.
* Malformed beacon identifier: 422.
* Active beacon with unavailable/unassigned campaign: 200 with null campaign and an empty offers array.
* Available campaign without current eligible offers: 200 with campaign metadata and an empty array.
* Database failure: 503 with a generic temporary-unavailability message.

Successful lookups are read-only and return `Cache-Control: no-store`. No detection history, device identity or location is recorded. Content returned by the service must be displayed inside the app; future client integration must never automatically follow external links.

## Model and authorization

`Beacon → Campaign → CampaignOffer → Offer → Merchant` supports multiple offers and changing campaign content without changing acoustic transmissions. Users have merchant or manager roles. A campaign belongs exclusively to a merchant or a manager. A beacon has an owner and an optional campaign assignment. Merchant coordinates describe the merchant; they are never inferred from a detecting phone's location.

An eligible result requires an active beacon, authorized campaign assignment, active campaign, active campaign-offer link, active offer and active merchant. Optional time windows use UTC, inclusive starts and exclusive ends. Offers are ordered by link display order and then stable public ID.

`app/domain.py` provides trusted mutation helpers for future authenticated endpoints: merchant-owned offer creation, merchant-controlled manager eligibility, campaign attachment and beacon assignment. Merchant campaigns cannot attach another merchant's offers. Manager campaigns require explicit offer eligibility; attaching an offer never transfers its ownership. The public lookup rechecks eligibility, so revoked consent stops publication even when a link remains.

These helpers are not authentication. Future endpoints must obtain the actor from verified credentials, never a client-supplied actor ID, and must use the domain helpers inside a transaction. There are no public mutation endpoints. Database constraints enforce foreign keys, uniqueness, exclusive ownership shape, date ordering, coordinate ranges and the 24-bit ID range. Cross-record role/authorization rules are enforced in the domain layer and defended in lookup; privileged direct database writes can bypass domain helpers and must be restricted operationally.

## Development seed

The explicit development seed creates beacon `0xABC123`, a clearly marked sample campaign, and a sample offer titled `wookiemeat`. It invents no real participating merchant or geographic coordinates. The content is not redeemable. Re-running the seed preserves an existing beacon assignment and edited content.

This backend sample is separate from the phone's existing local `wookiemeat` mapping. The mobile mapping, D09 decoder and acoustic format have not been changed. A future repository adapter can replace the local lookup with this endpoint after deployment and integration testing.

## Validation

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

Tests use isolated SQLite databases created by the actual Alembic migration. They cover lookup filtering and time boundaries, multiple offers, malformed and unknown IDs, manager consent and revocation, ownership isolation, schema/foreign-key constraints, input validation, idempotent seeding, read-only responses, migration downgrade/upgrade and model/schema agreement. PostgreSQL offline DDL compilation is also tested. A live PostgreSQL migration/query run remains required before deployment; offline compilation is not a substitute for that check.

## File inventory

All additions are contained in `backend/`:

* `.gitignore`, `.env.example`, `pyproject.toml`, `requirements-lock.txt`: configuration, dependency ranges and exact tested versions.
* `alembic.ini`, `migrations/env.py`, `migrations/script.py.mako`, `migrations/versions/0001_initial_schema.py`: migration configuration and initial schema.
* `app/__init__.py`, `app/config.py`, `app/database.py`: package, environment settings and database setup.
* `app/models.py`, `app/schemas.py`: storage and validated API contracts.
* `app/domain.py`, `app/lookup.py`: authorization helpers and content resolution.
* `app/main.py`, `app/seed.py`: read-only HTTP endpoint and explicit development seed.
* `tests/conftest.py`, `tests/test_lookup.py`, `tests/test_authorization.py`, `tests/test_integrity.py`: isolated fixtures and regression coverage.
* `README.md`: setup, contract and limitations.

Local virtual environments, database files, caches and secrets are ignored. No mobile files are intentionally modified.

## Next backend phase

Implement verified authentication and provisioning, merchant/manager write endpoints using the existing authorization boundary, media handling, deployment operations and live PostgreSQL integration checks. Add nearby-discovery endpoints separately if needed; this phase does not provide geographic search. Wire the consumer repository to the deployed public contract with loading/offline/error handling while preserving the validated acoustic core. Beacon IDs identify campaigns; CRC validation is not source authentication or proof of an authorized transmitter.

## Render configuration additions

See RENDER_DEPLOYMENT.md and the repository-root render.yaml for the actual hosting handoff. The public health endpoints are /health/live and /health/ready. Render PostgreSQL URL schemes are normalized automatically. Optional AB_CORS_ORIGINS is an explicit HTTPS-origin list. AB_PROVISION_TEST_BEACON is false by default; the physical-test blueprint explicitly enables it for its pre-deploy job. This is the sole opt-in production sample provisioning path; python -m app.seed still requires development mode.
