# Public Merchant signup and private Manager ownership

Signup: https://merchant.acousticbeacon.com/merchant/signup
Login: https://merchant.acousticbeacon.com/merchant/

Public POST `/api/v1/dashboard/register` accepts only business_name, contact_name, email, password and confirm_password. Extra fields (including role) are rejected. The server assigns `merchant`; User, Merchant, credential and secure session are committed together. Email is normalized and protected by a database unique constraint, including simultaneous registrations. The newly registered workspace has no offers, campaigns or beacons. No demo seed runs.

Origin, scrypt password hashing and Secure/HttpOnly/SameSite session handling reuse production authentication. Passwords must match and be 15–256 characters. Secret validation never reflects input. Database-backed registration limits allow 5 attempts per email per hour and 20 total per hour (fixed windows), separate from login limits. Existing/privileged email collisions return the same generic error without revealing roles. Contact names are stored privately, never exposed in public beacon responses.

## Initial Manager without an interactive shell

In the existing Northflank service's **runtime secret environment variables**, set both:

- `AB_BOOTSTRAP_MANAGER_EMAIL`: your chosen Manager login email
- `AB_BOOTSTRAP_MANAGER_PASSWORD`: your private password/passphrase, at least 15 characters

Save and redeploy the existing service. On startup, existing Alembic migrations run on one transaction under a PostgreSQL advisory lock, then a Manager is provisioned only if there are zero Manager users. Table locking prevents a simultaneous user insertion during this check. No HTTP bootstrap/Manager-registration route exists. Restart never resets a password or provisions another Manager when one already exists. Existing Merchant accounts are never promoted by this mechanism. Use an email that is not already a Merchant login.

Sign in at `/merchant/` using those credentials. After successful Manager sign-in, remove the two temporary bootstrap secrets from Northflank; the hashed database credential persists. Existing interactive `python -m app.bootstrap_manager` remains available to trusted operators. No secret belongs in Git, a URL, screenshots or chat.

## Deployment behavior

The production process now runs the existing additive Alembic migration chain before accepting traffic, because signup requires account tables even when shell access fails. No database credentials change. Runtime database permissions must permit migration DDL and account writes (the existing deployment uses the same database connection). Revision 0004 only adds nullable merchant contact_name. A migration/configuration failure aborts startup with a credential-safe message. Test-injected engines keep explicit migration fixtures.

`/demo` is unchanged, continues using only fictional local data, and retains its `connect-src 'none'` CSP. Public signup does not share its workspace.

This initial signup release does not verify email ownership or provide automated email password recovery/MFA. Do not represent registered email as verified. Production signup needs monitoring; stricter per-client bot controls and email delivery can be added when those services are configured. Manager permissions remain limited to existing authorized network content; Manager is not unrestricted access to every Merchant record. Customer event collection is unchanged.
