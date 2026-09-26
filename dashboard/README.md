# Acoustic Beacon merchant dashboard

Native browser ES modules and responsive CSS, served by the existing FastAPI application. No frontend runtime dependencies or external font/CDN requests. The approved consumer logo is reused unchanged.

## Open locally

With Node.js and the existing backend `.venv` installed, run from the repository:

```powershell
./dashboard/Start-Dashboard.ps1
```

Open http://127.0.0.1:8766/merchant/ and choose **Open merchant workspace**. The alternative Manager workspace uses the same database with separate ownership. Stop the local server with Ctrl+C.

The launcher migrates and idempotently seeds `backend/dashboard.db`, separate from the consumer integration database. Data is persisted in the real backend. Seeded businesses/offers are explicitly sample content. `0xABC123` retains its existing campaign and `wookiemeat` offer. Activity is an honest unavailable state; no analytics are simulated.

## Working features

Dashboard summary; offer creation/editing, dates, activation, HTTPS image URLs, network consent and preview; campaign creation/editing with multiple offers; owned beacon assignment and actual publicly served offers; account identity/sign-out. Merchant writes are ownership-scoped. Managers can create campaigns from eligible merchant offers but cannot edit merchant content. Public delivery rechecks consent and availability. No schema migration or consumer contract change was needed.

Offer removal is campaign unlinking or offer deactivation, not destructive deletion. Beacon provisioning remains outside this UI. Account information is read-only. The initial merchant workspace selects the first owned merchant; a multi-business selector is future work.

## Authentication and deployment boundary

This is a functional LOCAL development product, not production account authentication. `AB_DASHBOARD_DEV_AUTH=true` is opt-in, non-production, and loopback-host-only. The two predefined development accounts use random opaque, expiring HttpOnly/SameSite cookies, CSRF checks and origin validation. Sessions are in memory and expire on server restart. Do not expose the development server through a public proxy or tunnel.

Production management requests fail closed. Before public use, integrate verified identity-provider sessions with the existing User/Merchant ownership model, durable session management, account provisioning/recovery and operational rate limiting. Do not enable the development role selector in production.

`AB_DASHBOARD_API_BASE_URL` configures the API origin via `/api/v1/dashboard/config`. Development defaults explicitly to the same local origin. Production UI requires an explicit HTTPS non-loopback origin and never substitutes sample data. Same-origin deployment is recommended. A separate frontend origin also needs deliberate credentialed CORS and cookie/CSRF policy after production identity integration. Merely changing the URL does not supply production authentication.

Build `dashboard/dist` before starting FastAPI; the server mounts it at `/merchant/`. Build outputs and databases are ignored by Git. See existing backend deployment documentation for database/environment setup. Render is deferred. Event ingestion, aggregation and authorization are needed before Activity can show genuine analytics; image upload/storage is not implemented (hosted HTTPS URLs work).

## Checks

```powershell
node dashboard/scripts/check.mjs
node --test dashboard/tests/*.test.mjs
node dashboard/scripts/build.mjs
backend/.venv/Scripts/python.exe -m pytest backend/tests -q
```

Optional browser workflow uses Playwright 1.55 (`pip install playwright==1.55.0`, `python -m playwright install chromium`) in the backend development venv. With the local server running:

```powershell
backend/.venv/Scripts/python.exe dashboard/tests/browser_smoke.py
```

It checks desktop navigation, persistent offer and multi-offer campaign creation, mobile overflow/forms, manager restrictions and JavaScript errors. It creates explicitly named browser sample records in the development database. Screenshots go to ignored `dashboard/test-results`. API tests separately verify authorization, CSRF, validation, rollback, beacon delivery, consent revocation and production denial. Frontend checks include syntax validation and focused configuration/state/API tests.

## Protected baseline

No Flutter, microphone, decoder, protocol, WAV, timing, frequency or CRC code is changed. The existing public beacon lookup contract is retained. The six consumer protected-file SHA-256 values were checked against the pre-existing integrity manifest.
