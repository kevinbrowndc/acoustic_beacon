"""Explicit development seed; never automatically runs with the server."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import Settings
from .database import make_engine
from .domain import assign_beacon, attach_offer, create_offer
from .models import Beacon, Campaign, Merchant, User
from .schemas import OfferInput


def seed_demo(session: Session):
    existing = session.scalar(select(Beacon).where(Beacon.payload_id == 0xABC123))
    if existing:
        # Never overwrite an existing authorized assignment or edited offer.
        return existing
    user = session.scalar(select(User).where(User.email == "demo-merchant@example.invalid"))
    if user is None:
        user = User(email="demo-merchant@example.invalid", role="merchant")
        session.add(user)
        session.flush()
    merchant = Merchant(owner_user_id=user.id, name="Acoustic Beacon demonstration",
        description="Sample merchant, not a participating real business.", active=True)
    session.add(merchant)
    session.flush()
    campaign = Campaign(name="wookiemeat sample campaign", merchant_id=merchant.id, active=True, sample=True)
    session.add(campaign)
    session.flush()
    offer = create_offer(session, user.id, merchant.id, OfferInput(title="wookiemeat",
        description="Development test content for the validated 0xABC123 beacon.",
        terms="Sample only. Not redeemable.", active=True))
    attach_offer(session, user.id, campaign, offer)
    beacon = Beacon(payload_id=0xABC123, owner_user_id=user.id, active=True)
    session.add(beacon)
    session.flush()
    assign_beacon(session, user.id, beacon, campaign)
    return beacon


def main():
    settings = Settings()
    if settings.environment != "development":
        raise SystemExit("Development seed requires AB_ENVIRONMENT=development")
    engine = make_engine(settings.database_url.get_secret_value())
    try:
        with Session(engine) as session, session.begin():
            seed_demo(session)
        print("Development beacon 0xABC123 is present. Existing assignments were not overwritten.")
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
