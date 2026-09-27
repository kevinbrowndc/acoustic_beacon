# Supabase / free-host deployment handoff

SUPERSEDED: Leapcell signup is unavailable to Kevin ("Error, back to home"). Do not retry signup. Use NORTHFLANK_DEPLOYMENT.md for the current candidate and configuration. The remaining Leapcell notes are historical, not active instructions.

Status: PREPARED, NOT DEPLOYED. No public URL, Supabase connection, migration execution, or DNS changes are claimed. Existing production merchant authentication is not implemented; deploying the current dashboard exposes its sign-in-unavailable state, not a working authenticated management workflow. Local merchant/manager workflows are preserved. Never enable development identity publicly.

## Host decision (checked 2026-09-26)

Leapcell is the selected candidate: official pricing lists $0 Hobby serverless compute, 100,000 monthly invocations, 3 GB-hours and 2 GB outbound transfer; quota excess returns HTTP 429. Persistent servers are paid and must NOT be selected. GitHub FastAPI deployment, HTTPS, environment variables and idle dormancy are documented. Credit-card-free activation and Supabase outbound TCP remain UNVERIFIED in an actual account. No charge or subscription is authorized by this configuration. Do not represent these outstanding checks as passes.

Sources:
- https://leapcell.io/pricing
- https://docs.leapcell.io/examples/python/fastapi/
- https://docs.leapcell.io/serverless-vs-persistent/
- https://docs.leapcell.io/12factors/
- https://supabase.com/docs/guides/database/connecting-to-postgres

Existing Render billing restriction, PythonAnywhere outbound block and Koyeb path are not retried. Hugging Face is unsuitable: its current documentation limits outbound ports and requires a paid plan to create compute Spaces.

## Exact service configuration

Repository: https://github.com/kevinbrowndc/acoustic_beacon
Branch: master
Root: repository root (NOT backend; dashboard is a sibling).
Runtime: Python 3.12, Hobby / serverless only.
Build: `pip install -r backend/requirements-lock.txt && python deploy/build_dashboard.py`
Start: `cd backend && python -m uvicorn app.main:app --host 0.0.0.0 --port 8080 --no-access-log --no-proxy-headers`
Port: 8080
Readiness endpoint: `/health/ready`; liveness `/health/live`.
Dashboard: `/merchant/`.

Leapcell documents a platform port probe; where configurable, use the readiness endpoint. Independently require successful readiness before advertising the deployment. Building never accesses the database. Run the explicit one-off migration below before traffic verification; do not put migration in every worker startup. Dashboard packaging needs only Python, no Node install or frontend dependency changes.

Secrets/environment in hosting settings only:
- AB_ENVIRONMENT=production
- AB_DATABASE_URL: exact Supabase Connect > Session pooler URI (5432), URL-encoded password and `sslmode=require` minimum; `verify-full` with the supplied CA where available. Never infer the pooler hostname. Existing psycopg URL normalization accepts postgresql://.
- AB_DASHBOARD_DEV_AUTH=false
- AB_DASHBOARD_API_BASE_URL: actual assigned public HTTPS origin, no path. Set once allocated; never invent a hostname.
- AB_CORS_ORIGINS=[] for same-origin dashboard.
- AB_PROVISION_TEST_BEACON=true only for the authorized non-redeemable 0xABC123 test campaign.

Use one instance/conservative concurrency for initial session-pooler verification. The current pool can hold up to ten connections per process; unbounded serverless scale must not be enabled against a small Supabase database. If the host cannot cap scale, configure an appropriate connection strategy before proceeding. This run has not guessed or changed database pool behavior. The session pooler preserves current SQLAlchemy/psycopg semantics; transaction mode needs separate compatibility handling and is not interchangeable.

## Migration / verification

With AB_DATABASE_URL injected securely into a one-off process, working directory `backend`:
`python -m app.deploy`

Use a migration-capable role for that step; restrict the public runtime role to SELECT on application tables while management authentication remains disabled. Future authenticated management requires appropriate DML rights, not an unrestricted administrator connection. Review Supabase API exposure/RLS of application tables before exposing content through its separate Data API; do not assume FastAPI authorization protects that API.

Then, with the runtime credential, privately verify PostgreSQL dialect, TLS connection, `alembic_version=0001`, and the expected test beacon from the hosting runtime. Do not print connection strings. Public readiness alone does not prove Supabase provenance.

Run from repository root:
`python deploy/verify_public.py https://ACTUAL-HOST-ORIGIN`

This checks HTTPS routes/assets, production config, test campaign and unknown ID. It explicitly reports management status rather than pretending sign-in works. Completing public merchant editing needs production identity integration; opening up the local role selector is not an acceptable deployment fix.

## Domains and rollback

No DNS values are available until the service exists. First verify the host-provided HTTPS URL. Then register merchant.acousticbeacon.com and api.acousticbeacon.com in the host and copy its exact verification/routing records. Preserve the apex website. Do not infer a CNAME target from examples.

Rollback to the previous host revision without downgrading database schema automatically. Current changes only package unchanged frontend files; no mobile/protocol/schema modification.

## Remaining access

No Leapcell or Supabase credentials were present in the checked process environment or backend .env. Browser automation could not initialize, so existing browser sign-in state could not be inspected. Next human step: sign in to Leapcell with GitHub. Account eligibility and repository authorization must be verified before any service is provisioned. Supabase credentials must be entered into the host's secret settings, never chat or Git.
