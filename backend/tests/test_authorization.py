import pytest
from sqlalchemy import select

from app.domain import AuthorizationError, assign_beacon, attach_offer, create_offer, set_manager_eligibility
from app.models import Beacon, Campaign, CampaignOffer, Merchant, Offer, User
from app.schemas import OfferInput

URL = "/api/v1/beacons/0xABC123/offers"


def manager_campaign(session):
    manager = User(email="manager@example.invalid", role="manager")
    session.add(manager)
    session.flush()
    campaign = Campaign(name="Network campaign", manager_user_id=manager.id, active=True)
    session.add(campaign)
    session.flush()
    return manager, campaign


def test_manager_requires_consent_and_cannot_take_ownership(session):
    manager, campaign = manager_campaign(session)
    offer = session.scalar(select(Offer))
    merchant = session.get(Merchant, offer.merchant_id)
    with pytest.raises(AuthorizationError):
        attach_offer(session, manager.id, campaign, offer)
    with pytest.raises(AuthorizationError):
        set_manager_eligibility(session, manager.id, offer, True)
    with pytest.raises(AuthorizationError):
        create_offer(session, manager.id, merchant.id, OfferInput(title="No", description="No", terms="No"))
    set_manager_eligibility(session, merchant.owner_user_id, offer, True)
    attach_offer(session, manager.id, campaign, offer)
    assert offer.merchant_id == merchant.id
    assert session.get(Merchant, offer.merchant_id).owner_user_id == merchant.owner_user_id


@pytest.mark.parametrize("initial_consent", [False, True])
def test_manager_lookup_filters_invalid_or_revoked_consent(client, session, initial_consent):
    manager, campaign = manager_campaign(session)
    offer = session.scalar(select(Offer))
    merchant = session.get(Merchant, offer.merchant_id)
    if initial_consent:
        set_manager_eligibility(session, merchant.owner_user_id, offer, True)
        attach_offer(session, manager.id, campaign, offer)
        set_manager_eligibility(session, merchant.owner_user_id, offer, False)
    else:
        # Simulate a bad administrative insertion; public reads must still filter.
        session.add(CampaignOffer(campaign_id=campaign.id, offer_id=offer.id))
    beacon = session.scalar(select(Beacon))
    beacon.owner_user_id = manager.id  # trusted fixture provisioning, not an API
    assign_beacon(session, manager.id, beacon, campaign)
    session.commit()
    assert client.get(URL).json()["offers"] == []


def test_manager_can_select_multiple_merchants_with_consent(client, session):
    manager, campaign = manager_campaign(session)
    first = session.scalar(select(Offer))
    first.manager_eligible = True
    other = User(email="other@example.invalid", role="merchant")
    session.add(other)
    session.flush()
    merchant = Merchant(owner_user_id=other.id, name="Other sample", active=True)
    session.add(merchant)
    session.flush()
    second = create_offer(session, other.id, merchant.id, OfferInput(title="Other offer",
        description="Sample", terms="Sample", active=True, manager_eligible=True))
    attach_offer(session, manager.id, campaign, first, 1)
    attach_offer(session, manager.id, campaign, second, 0)
    beacon = session.scalar(select(Beacon))
    beacon.owner_user_id = manager.id
    assign_beacon(session, manager.id, beacon, campaign)
    session.commit()
    data = client.get(URL).json()
    assert [o["title"] for o in data["offers"]] == ["Other offer", "wookiemeat"]
    assert data["offers"][0]["merchant"]["id"] == merchant.public_id
    assert data["offers"][0]["merchant"]["id"] != data["offers"][1]["merchant"]["id"]


def test_unauthorized_actor_and_beacon_assignment(session):
    manager, campaign = manager_campaign(session)
    beacon = session.scalar(select(Beacon))
    with pytest.raises(AuthorizationError):
        assign_beacon(session, manager.id, beacon, campaign)
    with pytest.raises(AuthorizationError):
        attach_offer(session, beacon.owner_user_id, campaign, session.scalar(select(Offer)))


def test_merchant_cannot_attach_foreign_offers_even_if_eligible(session):
    user = User(email="second@example.invalid", role="merchant")
    session.add(user)
    session.flush()
    merchant = Merchant(owner_user_id=user.id, name="Other merchant")
    session.add(merchant)
    session.flush()
    campaign = Campaign(name="Own campaign", merchant_id=merchant.id)
    session.add(campaign)
    session.flush()
    offer = session.scalar(select(Offer))
    offer.manager_eligible = True
    with pytest.raises(AuthorizationError):
        attach_offer(session, user.id, campaign, offer)
