"""Trusted service boundary for future authenticated APIs; never exposed by HTTP yet.

Actor IDs must come from verified authentication, NOT a request-supplied user ID.
Callers own the transaction and commit/rollback. No service transfers ownership.
"""
from sqlalchemy.orm import Session

from .models import Beacon, Campaign, CampaignOffer, Merchant, Offer, User
from .schemas import OfferInput


class AuthorizationError(Exception):
    pass


def campaign_owner(session: Session, campaign: Campaign) -> int | None:
    if campaign.merchant_id is not None:
        merchant = session.get(Merchant, campaign.merchant_id)
        owner = session.get(User, merchant.owner_user_id) if merchant else None
        return owner.id if owner and owner.role == "merchant" else None
    owner = session.get(User, campaign.manager_user_id)
    return owner.id if owner and owner.role == "manager" else None


def require_campaign_owner(session, actor_id, campaign):
    if campaign_owner(session, campaign) != actor_id:
        raise AuthorizationError("Campaign is not owned by the authenticated actor")


def create_offer(session: Session, actor_id: int, merchant_id: int, data: OfferInput) -> Offer:
    actor = session.get(User, actor_id)
    merchant = session.get(Merchant, merchant_id)
    if not actor or actor.role != "merchant" or not merchant or merchant.owner_user_id != actor.id:
        raise AuthorizationError("Only the merchant owner may create offers")
    values = data.model_dump(mode="python")
    values["image_url"] = str(data.image_url) if data.image_url else None
    offer = Offer(merchant_id=merchant.id, **values)
    session.add(offer)
    session.flush()
    return offer


def set_manager_eligibility(session: Session, actor_id: int, offer: Offer, eligible: bool):
    merchant = session.get(Merchant, offer.merchant_id)
    actor = session.get(User, actor_id)
    if not actor or actor.role != "merchant" or merchant.owner_user_id != actor.id:
        raise AuthorizationError("Only the merchant owner controls network consent")
    offer.manager_eligible = eligible
    session.flush()


def attach_offer(session: Session, actor_id: int, campaign: Campaign, offer: Offer, display_order: int = 0):
    require_campaign_owner(session, actor_id, campaign)
    if display_order < 0:
        raise ValueError("display_order must be nonnegative")
    if campaign.manager_user_id is not None:
        if not offer.manager_eligible:
            raise AuthorizationError("Merchant has not authorized network use")
    elif campaign.merchant_id != offer.merchant_id:
        raise AuthorizationError("Merchant campaigns can only include their own offers")
    link = session.get(CampaignOffer, (campaign.id, offer.id))
    if link is None:
        link = CampaignOffer(campaign_id=campaign.id, offer_id=offer.id)
        session.add(link)
    link.display_order, link.active = display_order, True
    session.flush()
    return link


def assign_beacon(session: Session, actor_id: int, beacon: Beacon, campaign: Campaign):
    require_campaign_owner(session, actor_id, campaign)
    if beacon.owner_user_id != actor_id:
        raise AuthorizationError("Beacon is not authorized to this actor")
    beacon.campaign_id = campaign.id
    session.flush()
