> Public Merchant registration and shell-free private Manager setup are now available. See [MERCHANT_SIGNUP.md](MERCHANT_SIGNUP.md). The interactive command below remains an operator fallback.

# Production account access

The existing dashboard now authenticates email/password against `users` and additive `account_credentials` / `account_sessions` tables in the configured PostgreSQL database. No Supabase Auth service or new hosting service is required. Existing role/ownership enforcement remains authoritative. No roles can be chosen at login and public registration can create Merchant accounts only.

## One-time private setup

After deploying master, open the **existing Northflank service Shell** and run:

```
python -m app.bootstrap_manager
```

The command runs the existing Alembic upgrade to head (0003, including analytics 0002), then asks for your email and a password of at least 15 characters, twice, with hidden input. It creates only a Manager credential/account. It never runs demo seeding, changes assignments or promotes existing Merchant users. Existing credentials are never overwritten. Passwords are salted scrypt hashes; plaintext is never stored. The command must run in a terminal capable of hidden input, otherwise it aborts rather than echoing a password. No environment-variable change is required on the current domain. Runtime DB credentials must have the existing migration/write privileges; if they do not, an operator must use the existing migration credential privately.

Open https://merchant.acousticbeacon.com/merchant/ and use that email/password. New Manager accounts see only eligible merchant offers and campaigns/beacons they own. An empty real account is not filled with sample content. Merchant credentials attach to existing Merchant users; role/ownership rules are unchanged. Merchant analytics remains merchant-only.

## Security and operational behavior

Passwords use scrypt N=131072, r=8, p=1, random 16-byte salts. Sessions are random 256-bit opaque tokens, hashed at rest, expire after eight hours, survive workers/restarts, rotate on sign-in and are deleted on sign-out. Disabling a credential revokes access immediately. The `__Host-ab_session` cookie is Secure, HttpOnly, SameSite=Strict with no Domain. CSRF tokens plus exact Origin checks protect authenticated mutations and login. The default public origin is the existing merchant HTTPS domain, independent of the internal HTTP proxy connection; forwarded headers are not trusted. `AB_DASHBOARD_PUBLIC_ORIGIN` can configure another explicit HTTPS origin if hosting changes later.

DB-backed login limits: 10 attempts per email per 15-minute fixed window and 30 total per minute. Unknown users receive the same password work and failure text. A per-worker semaphore bounds memory for scrypt. These conservative initial limits can deny sign-ins during abuse; production edge abuse protection remains an operational follow-up, not an authentication bypass.

Public demo stays isolated and its CSP continues to prohibit API requests. Public beacon lookup is unchanged. No passwords/tokens enter browser storage or URL query strings. There is no password recovery email, public signup, or MFA UI in this initial operator-provisioned release; account recovery requires a trusted operator. Do not expose shell access or use development sign-in in production.

Reference: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html and https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
