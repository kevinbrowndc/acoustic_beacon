# Northflank + existing Supabase: deployment configuration

Current status: prepared, NOT deployed. Supabase is retained. D09, Flutter and application behavior are unchanged. Leapcell is unavailable to Kevin (signup returns "Error, back to home"); do not retry it, Render, PythonAnywhere or Koyeb without evidence their documented blockers are resolved.

## Verified provider capabilities (2026-09-26)

Northflank Developer Sandbox provides two free services and two jobs, always-on with no sleeping. Its documentation supports FastAPI, Docker builds from GitHub, HTTPS public ports, secrets and external database connections. It is suitable for this development/demo deployment; Northflank explicitly says the free tier should not be used for production applications.

A payment method is REQUIRED to create resources on every plan, including Sandbox. This is identity verification, not permission to select paid services. Use only resources displaying $0; do not enable paid volumes, addons, dedicated egress, BYOC or upgrades. Billing alerts are not a hard spending cap. Actual account eligibility and connectivity to this Supabase project still need verification.

Primary sources:
- https://northflank.com/pricing
- https://northflank.com/docs/v1/application/billing/pricing-on-northflank
- https://northflank.com/docs/v1/application/billing/add-a-card
- https://northflank.com/guides/deploy-fastapi-postgres-cloud-docker
- https://northflank.com/docs/v1/application/production-workloads/persistent-storage-in-production

Alwaysdata was rejected because its free plan prohibits commercial use and custom domains. No additional attempt was made at the four blocked providers.

## Ready configuration

- Provider plan: Developer Sandbox, Northflank Cloud (not BYOC).
- Combined build/deploy service, repository `kevinbrowndc/acoustic_beacon`, branch `master`.
- Build context: repository root; Dockerfile: `deploy/Dockerfile`.
- One free instance, no persistent disk and NO new database.
- Public HTTP port: 8080; provider terminates HTTPS.
- Readiness probe: HTTP `/health/ready`; liveness `/health/live`.
- Dashboard path: `/merchant/`.
- Migration job from the same built image: `python -m app.deploy`, working directory `/app/backend`. Execute once before validating the service, not on every web worker start. Use only a free job; no schedule needed.
- Image build has no database access or secrets. Root .dockerignore excludes mobile, credentials, local databases, virtual environments and generated files. The unchanged dashboard is built into the image using Python.

Runtime secret settings:
- `AB_ENVIRONMENT=production`
- `AB_DASHBOARD_DEV_AUTH=false`
- `AB_DATABASE_URL`: existing Supabase Session Pooler connection (port 5432), copied exactly from Connect. URL-encode the password. Use `sslmode=require` at minimum, preferably `verify-full` with Supabase CA configured. Do not print or commit this value.
- `AB_DASHBOARD_API_BASE_URL`: actual assigned HTTPS origin after service creation.
- `AB_CORS_ORIGINS=[]` for same-origin dashboard.
- Migration job only: `AB_PROVISION_TEST_BEACON=true` to provision the already-authorized non-redeemable 0xABC123 campaign idempotently.

Separate migration and runtime database permissions. Current public API runtime needs SELECT; public merchant writes remain disabled until genuine production identity integration exists. Do not expose the local role selector or call that a successful management deployment.

## Verification and remaining access

After migration, verify PostgreSQL dialect, encrypted Supabase connection and Alembic revision 0001 in the hosting runtime without logging credentials. Run `python deploy/verify_public.py https://ACTUAL-ORIGIN` locally against the assigned public URL. It verifies health, assets, production mode, 0xABC123 -> campaign -> wookiemeat, and unknown beacon handling; management authentication is explicitly reported separately.

No live checks have yet passed. The local Docker executable exists but its Linux engine is not running, so the image build itself remains unverified pending the host build. Existing backend/frontend tests and Python dashboard packaging can be checked locally. No DNS edits or guessed DNS records: register subdomains only after host HTTPS validation, then use exact records supplied by Northflank. Preserve the existing apex website.

No Northflank token was present in the process environment. Human-only next step: create/sign in to a Northflank Developer Sandbox account. Payment-method verification is required by the provider before resource creation. Supabase secrets belong in host settings, never chat. No paid resources are authorized.
