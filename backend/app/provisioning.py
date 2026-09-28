"""Server-owned allocation. Existing beacon ownership is never changed."""
import secrets
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from .models import User, Merchant, Beacon, AccountCredential


def ensure_beacon(session, user_id):
    # Serialize concurrent onboarding/backfill for the same account in PostgreSQL.
    user = session.scalar(select(User).where(User.id == user_id).with_for_update())
    if user is None or user.role != 'merchant':
        raise ValueError('A merchant account is required')
    existing = session.scalar(select(Beacon).where(Beacon.owner_user_id == user_id).order_by(Beacon.id))
    if existing is not None:
        return existing
    for _ in range(128):
        payload_id = secrets.randbelow(0xFFFFFF) + 1
        if payload_id == 0xABC123:  # Reserved physical-test ID, even before sample provisioning.
            continue
        try:
            with session.begin_nested():
                beacon = Beacon(payload_id=payload_id, owner_user_id=user_id, active=True)
                session.add(beacon)
                session.flush()
            return beacon
        except IntegrityError:
            # Unique payload constraint arbitrates collisions across all workers.
            if session.scalar(select(Beacon.id).where(Beacon.payload_id == payload_id)) is None:
                raise
    raise RuntimeError('Beacon allocation temporarily unavailable')


def backfill_merchants(session):
    # Real, enabled merchant accounts only. Never allocate to Managers or sample identities.
    owners = session.scalars(select(User.id).join(Merchant, Merchant.owner_user_id == User.id)
        .join(AccountCredential, AccountCredential.user_id == User.id)
        .where(User.role == 'merchant', Merchant.active.is_(True), AccountCredential.enabled.is_(True))
        .distinct().order_by(User.id)).all()
    for owner in owners:
        ensure_beacon(session, owner)
    session.flush()
