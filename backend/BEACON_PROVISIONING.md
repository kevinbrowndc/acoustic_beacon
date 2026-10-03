# Automatic merchant beacons

Registration allocates one active, unassigned beacon in the same transaction as the Merchant, credential and session. The server uses secrets.randbelow for nonzero 24-bit IDs, reserves 0xABC123, and retries collisions under the existing unique database constraint. A User row lock serializes allocation/backfill for one owner in PostgreSQL. Ownership cannot be selected or changed by a merchant.

Production startup runs the existing serialized Alembic/account initialization, then idempotently provisions active Merchant profiles with enabled credentials that have no existing beacon. Existing beacons (including inactive ones), campaigns, sample identities and Manager accounts are preserved. No schema change or manual database operation is required. Failed initialization rolls back and fails startup rather than leaving partial provisioning.

Merchant steps: create and activate an offer; create and activate a campaign containing it; on Beacon select that campaign and Save assignment. Play or download the authenticated audio on the same page. Each file has three transmissions. Updating offers never requires a new ID or audio file. Managers can view merchant beacon assignments and suspend/restore delivery through the Beacon support section; they cannot change ownership here.

Audio endpoint: GET /api/v1/dashboard/beacons/{public_uuid}/audio.wav. It requires the existing owner session, accepts no protocol parameters or custom ID, and sends private/no-store headers. The server renderer matches the unchanged consumer Dart production ultrasonic generator: 20000/21000 Hz, 40 ms symbols, CD A8 preamble, 24-bit ID, CRC-8/0x07, 48 kHz mono PCM16, existing ramps/amplitude/padding. The checked-in SHA-256 test vector was generated directly by that Dart generator. No consumer or D09 file was edited.

Public demo hides audio delivery controls and remains isolated from production APIs. Beacon IDs identify content; they are not secrets or authentication credentials. Existing signup rate limits, password policy, sessions, CSRF, role assignment and tenant checks remain in force.
