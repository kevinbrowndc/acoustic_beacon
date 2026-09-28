# Privacy implementation audit — September 28, 2026

Scope: marketing `main`; merchant presentation links only on `master`. Consumer source inspected read-only at sibling `acoustic_beacon_consumer`; no Flutter changes.

## Evidence
- Consumer `lib/audio/microphone.dart`: PCM startStream, transient memory; no file recording/upload. `consumer/api_repository.dart`: GET beacon ID, no coordinates, account or device ID; nearby returns empty without network. `consumer/controller.dart`: location/pins in memory. `consumer/store.dart`: local saved snapshots/onboarding/theme/haptics. `consumer/nearby_map.dart`: OpenStreetMap tile requests. `consumer/design.dart`: remote offer images.
- Backend `app/models.py`: merchant name/contact/email (User), website/consent, optional business address/coordinates, content, ownership, timestamps; password hashes/session hashes/rate counters. Activity records: merchant, event key/type/time only.
- `app/auth.py`: scrypt, secure HttpOnly SameSite cookie, 8-hour expiry; hashed-email rate counters; cleanup on auth activity. No IP-based rate storage.
- `app/main.py` beacon lookup: read-only DB session. `ACTIVITY.md` and `app/activity.py`: consumer collection not connected; counts are recorded events, not unique people.
- Dashboard sources: no localStorage/sessionStorage or analytics SDK. Public demo data in memory and CSP connect-src none. External images can contact their host.
- Marketing homepage: Google Analytics G-ETJQDV6T2K loads unconditionally. Netlify contact and update forms. No cookie-consent mechanism added or claimed in this pass; browser controls described accurately.
- Production backend Dockerfile: Uvicorn default access logs, no-proxy-headers. Infrastructure can process network metadata even though domain tables have no visitor IP/device fields.
- Providers established from configuration: Netlify, Northflank, Supabase PostgreSQL, Google Analytics, OpenStreetMap. GitHub stores/deploys code, not a customer submission processor in this implementation.

## Not established by repository
- Exact retention/deletion schedules for hosting logs, form submissions, analytics, database backups; provider regions, contracts/subprocessors and international safeguards.
- Google Analytics console settings (Google Signals, advertising integrations, enhanced measurement and retention), actual cookie behavior across user regions.
- Operator's formal legal entity/address, request-handling staffing, actual response procedures or legal applicability thresholds. No entity/address was invented.
- Exact mobile binary currently in each tester's hands or its configured endpoint. Policy identifies the inspected current/pre-release implementation.
- No automated account deletion, consumer event ingestion, consumer accounts, or universal data-retention job exists. Policies do not claim otherwise.

## Legal review boundary
These pages describe implementation, not a certification of legal compliance. Operator should confirm operational commitments, provider settings and retention, and obtain review of terms/rights applicability before broad launch. Kentucky provisions retain mandatory rights; no arbitration or fabricated venue county. No claim of guaranteed security or immediate backup erasure.

Reference checks: https://www.ftc.gov/business-guidance/privacy-security ; https://www.ag.ky.gov/about/Office-Divisions/ODP/KCDPA/Pages/default.aspx .
