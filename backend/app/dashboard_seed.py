"""Run explicitly against a local development DB, never on application startup."""
from sqlalchemy import select
from sqlalchemy.orm import Session
from .config import Settings
from .database import make_engine
from .models import Merchant, Offer, User
from .seed import seed_demo


def seed_dashboard(session):
    seed_demo(session)
    merchant_user = session.scalar(select(User).where(User.email == "demo-merchant@example.invalid"))
    merchant = session.scalar(select(Merchant).where(Merchant.owner_user_id == merchant_user.id))
    if not session.scalar(select(Offer).where(Offer.merchant_id == merchant.id, Offer.title == "A little more for your next visit")):
        session.add(Offer(merchant_id=merchant.id, title="A little more for your next visit", description="An additional sample offer to explore campaign selection.", terms="Development sample only. Not redeemable.", active=False, manager_eligible=True))
    if not session.scalar(select(User).where(User.email == "demo-manager@example.invalid")):
        session.add(User(email="demo-manager@example.invalid", role="manager"))
    partner = session.scalar(select(User).where(User.email == "demo-partner@example.invalid"))
    if partner is None:
        partner = User(email="demo-partner@example.invalid", role="merchant")
        session.add(partner)
        session.flush()
        profile = Merchant(owner_user_id=partner.id, name="Partner Studio (sample)", description="Development partner", active=True)
        session.add(profile)
        session.flush()
        session.add(Offer(merchant_id=profile.id, title="Discover something local", description="Authorized sample content from a second merchant.", terms="Development sample only. Not redeemable.", active=True, manager_eligible=True))


def main():
    settings = Settings()
    if settings.environment != "development":
        raise SystemExit("Dashboard seed requires development mode")
    engine = make_engine(settings.database_url.get_secret_value())
    try:
        with Session(engine) as session, session.begin():
            seed_dashboard(session)
        print("Local merchant and manager sample workspaces are ready.")
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
