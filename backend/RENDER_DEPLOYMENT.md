# Render deployment handoff

## Prepared configuration

The root render.yaml defines one Python web service (0.5c-512mb) and one PostgreSQL 17 database (0.1c-256mb, 1 GB) in Ohio. These are PAID plans: review Render's displayed estimate before applying. No resources or charges have been created. Auto-deploy is off. The backend root is backend; Render builds from requirements-lock.txt, runs python -m app.deploy before deployment, starts Uvicorn on $PORT, and checks /health/ready.

## Smallest external action

Sign in at https://dashboard.render.com, choose New > Blueprint, connect kevinbrowndc/acoustic_beacon, branch master, blueprint render.yaml. Review the paid plan estimate and apply. The account owner's Render login, GitHub authorization and billing approval are required. Once live, provide the public HTTPS service URL, not a secret or database URL. A consumer APK can then be built against that exact endpoint.

## Environment

AB_ENVIRONMENT=production rejects SQLite. AB_DATABASE_URL is supplied from Render's private PostgreSQL connection string; postgres:// and postgresql:// normalize to the installed psycopg driver. Public database ingress is disabled. AB_CORS_ORIGINS defaults to []; native Android/iOS clients do not need browser CORS. Optional browser origins must be explicit HTTPS origins.

AB_PROVISION_TEST_BEACON=true explicitly opts this physical-test deployment into idempotent 0xABC123 / wookiemeat sample provisioning during the pre-deploy job. Existing assignments are preserved. The content remains marked sample and not redeemable. The normal development seed command still refuses production. Turn the flag off after provisioning; this does not delete the sample.

The initial blueprint uses the managed database credential for migration and web requests; requests use read-only transactions. Before commercial rollout, isolate migration credentials and provision a SELECT-only runtime role. This is an integration deployment, not a claim that all commercial operations are complete.

## Health, logging and validation

/health/live checks the process; /health/ready checks the database, migration 0001 and beacon table. Failure gives a generic 503 response. Connection, statement and pool waits are bounded. Uvicorn access logs are disabled to avoid retaining beacon request paths; startup logs remain. Validation errors hide input values. Render terminates HTTPS; the API neither redirects nor trusts arbitrary forwarded headers.

After deploying, verify /health/ready, /api/v1/beacons/0xABC123/offers (sample campaign and wookiemeat), and an unknown ID (404). The live PostgreSQL and HTTPS checks remain pending. Offline DDL and SQLite tests are not substitutes.

Keep the previous successful revision for rollback. Do not automatically downgrade the database. Authentication/write APIs remain outside this phase.

References: https://render.com/docs/blueprint-spec and https://render.com/docs/deploys
