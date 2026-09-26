from datetime import datetime, timezone

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from .domain import campaign_owner
from .models import Beacon, Campaign, CampaignOffer, Merchant, Offer
from .schemas import BeaconOffersOut, CampaignOut, LocationOut, MerchantOut, OfferOut


def aware(value):
    # SQLite drops the zone; all writes via domain schemas are normalized to UTC.
    return value.replace(tzinfo=timezone.utc) if value and value.tzinfo is None else value


def in_window(entity, now):
    return (entity.start_at is None or aware(entity.start_at) <= now) and (
        entity.end_at is None or now < aware(entity.end_at))


def lookup_offers(session: Session, payload_id: int, now: datetime) -> BeaconOffersOut | None:
    beacon = session.scalar(select(Beacon).where(Beacon.payload_id == payload_id, Beacon.active.is_(True)))
    if beacon is None:
        return None
    result = BeaconOffersOut(beacon_id=f"0x{payload_id:06X}", campaign=None, offers=[])
    campaign = session.get(Campaign, beacon.campaign_id) if beacon.campaign_id else None
    if not campaign or not campaign.active or not in_window(campaign, now):
        return result
    if campaign_owner(session, campaign) != beacon.owner_user_id:
        return result
    if campaign.merchant_id is not None:
        owner_merchant = session.get(Merchant, campaign.merchant_id)
        if not owner_merchant.active:
            return result
    result.campaign = CampaignOut(id=campaign.public_id, name=campaign.name, sample=campaign.sample)
    query = (select(Offer, Merchant).join(Merchant, Offer.merchant_id == Merchant.id)
        .join(CampaignOffer, CampaignOffer.offer_id == Offer.id)
        .where(CampaignOffer.campaign_id == campaign.id, CampaignOffer.active.is_(True),
            Offer.active.is_(True), Merchant.active.is_(True),
            or_(Offer.start_at.is_(None), Offer.start_at <= now),
            or_(Offer.end_at.is_(None), Offer.end_at > now))
        .order_by(CampaignOffer.display_order, Offer.public_id))
    # Defense in depth: re-check consent/ownership at read time, even for links
    # inserted by a migration or after a merchant revokes manager eligibility.
    if campaign.manager_user_id is not None:
        query = query.where(Offer.manager_eligible.is_(True))
    else:
        query = query.where(Offer.merchant_id == campaign.merchant_id)
    for offer, merchant in session.execute(query):
        location = None if merchant.latitude is None else LocationOut(
            latitude=merchant.latitude, longitude=merchant.longitude)
        result.offers.append(OfferOut(id=offer.public_id, title=offer.title,
            description=offer.description, terms=offer.terms, image_url=offer.image_url,
            start_at=aware(offer.start_at), end_at=aware(offer.end_at),
            merchant=MerchantOut(id=merchant.public_id, name=merchant.name,
                description=merchant.description, address=merchant.address, city=merchant.city,
                country_code=merchant.country_code, location=location)))
    return result
