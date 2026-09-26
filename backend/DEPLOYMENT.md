# Backend deployment preparation

Hosting destination is not selected yet. No public service or database has been created. This directory is the deployment build context; do not upload the mobile project or local virtual environment.

The Dockerfile runs Python 3.12 and Uvicorn as a non-root user on port 8000. It defaults to production mode, which requires PostgreSQL. The build context allowlist excludes local environment files, databases, logs and credentials. Container build/run remains unverified until a Docker engine is available. The locked dependency set includes the existing test tools; it is preserved rather than silently upgraded.

Required hosting configuration:

- HTTPS termination and routing to container port 8000.
- Secret AB_DATABASE_URL using the postgresql+psycopg:// scheme and the provider-required TLS parameters.
- AB_ENVIRONMENT=production.
- Separate migration job: python -m alembic upgrade head, with a migration-capable credential. Run once per deployment before directing traffic to the new revision; never auto-run from every web instance.
- Runtime database role restricted to SELECT on required tables. Do not use the database administrator credential for normal requests.
- Provider access controls, logs, restart policy and PostgreSQL backup/restore configuration.

The development seed refuses production mode. Do not bypass that safeguard to populate a public deployment. Test-campaign provisioning must be agreed for the deployment environment. No merchant content is invented automatically.

After deployment: verify HTTPS, successful database migration, expected API response for a provisioned beacon, 404 for an unknown beacon and absence of secrets in errors/logs. A 404 for an unseeded ID is not evidence that the wookiemeat campaign has been provisioned. Keep the preceding deployment available for rollback; review migration compatibility before any database downgrade.

Provider-specific configuration, health checks and live PostgreSQL/HTTPS validation will be completed after the hosting destination and access method are known. No deployment, commit or push has occurred.

Render is the selected provider. The root render.yaml and RENDER_DEPLOYMENT.md supersede the earlier provider-neutral handoff. The native Python deployment does not require the local Docker engine. Its explicit pre-deploy sample flag provisions the requested non-redeemable physical-test content; the server never seeds on normal startup.
