# Serve the existing merchant dashboard on Northflank

Dockerfile: `/backend/Dockerfile`. Docker BUILD CONTEXT: repository root `/` (not `/backend`). Keep the existing service, runtime environment and public port 8000. The Dockerfile copies the existing native dashboard modules/CSS/logo from the sibling dashboard directory, without rebuilding or redesigning the UI. No Node runtime is needed.

This build-context adjustment is required if the current service restricts Docker's context to backend: Docker cannot COPY files outside its context. In the existing service's build settings retain backend/Dockerfile, set build context to the repository root, and deploy the latest master commit. Do not create another service.

The image serves `/dashboard/dist` through FastAPI's existing mount. `/` redirects to `/merchant/`; relative static asset URLs remain within that path. The frontend uses its own HTTPS origin when AB_DASHBOARD_API_BASE_URL is empty, and still supports an explicitly configured HTTPS origin. Local HTTP origins remain forbidden in production. No DATABASE_URL or Supabase change is involved.

Production entry screen is available. Authenticated merchant management is NOT yet enabled: the UI explicitly explains that production account sign-in is not connected. It does not display fake offers, analytics or a development role selector. Existing local merchant/manager workflows remain intact. This integration does not implement production authentication.

Validation: run `python deploy/build_dashboard.py` before the backend suite (as with the existing native frontend build); then `python -m pytest backend/tests -q`, `node dashboard/scripts/check.mjs`, and `node --test dashboard/tests/*.test.mjs`. Production delivery tests verify redirects, all static assets, same-origin configuration and denial of development sign-in. Live deployment must still be checked on the actual host URL; local tests are not a live deployment claim.
