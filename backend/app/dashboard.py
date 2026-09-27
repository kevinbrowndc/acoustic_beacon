"""Merchant management API. Development identity is explicitly loopback-only.

Production identity-provider integration is intentionally fail-closed.
"""
import hashlib
import hmac
import secrets
import time
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .domain import AuthorizationError, assign_beacon, attach_offer, create_offer, require_campaign_owner
from .lookup import aware, lookup_offers
from .models import Beacon, Campaign, CampaignOffer, Merchant, Offer, User
from .schemas import OfferInput

router = APIRouter(prefix="/api/v1/dashboard", tags=["Merchant dashboard"])
COOKIE = "ab_dashboard_session"


def db(request: Request):
    with Session(request.app.state.engine) as session:
        yield session


def development_enabled(request):
    config = request.app.state.settings
    local = request.client and request.client.host in {"127.0.0.1", "::1", "testclient"}
    return config.environment != "production" and config.dashboard_dev_auth and local and request.url.hostname in {"localhost", "127.0.0.1", "::1", "testserver"}


def origin_check(request):
    origin = request.headers.get("origin")
    if origin and origin != str(request.base_url).rstrip("/"):
        raise HTTPException(403, "Cross-origin session actions are not allowed")


def csrf(token):
    return hashlib.sha256((token + ":csrf").encode()).hexdigest()


def actor(request: Request, session: Session = Depends(db)):
    if not development_enabled(request):
        raise HTTPException(503, "Production account authentication is not connected yet")
    token = request.cookies.get(COOKIE, "")
    entry = request.app.state.dashboard_sessions.get(hashlib.sha256(token.encode()).hexdigest())
    if not entry or entry[1] <= time.time():
        raise HTTPException(401, "Sign in to your workspace")
    if request.method not in {"GET", "HEAD"}:
        origin_check(request)
        if not hmac.compare_digest(request.headers.get("x-csrf-token", ""), csrf(token)):
            raise HTTPException(403, "Session verification failed. Refresh and try again.")
    user = session.get(User, entry[0])
    if not user:
        raise HTTPException(401, "Account unavailable")
    return user


class SignIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: Literal["merchant", "manager"]


@router.get("/config")
def configuration(request: Request):
    return {"development_sign_in": bool(development_enabled(request)),
            "api_base_url": request.app.state.settings.dashboard_api_base_url,
            "production": request.app.state.settings.environment == "production"}


@router.post("/dev-session")
def sign_in(data: SignIn, request: Request, response: Response, session: Session = Depends(db)):
    if not development_enabled(request):
        raise HTTPException(404, "Not found")
    origin_check(request)
    if request.headers.get("x-beacon-development") != "1":
        raise HTTPException(403, "Explicit development sign-in required")
    email = f"demo-{data.role}@example.invalid"
    user = session.scalar(select(User).where(User.email == email, User.role == data.role))
    if not user:
        raise HTTPException(409, "Run the dashboard development seed first")
    sessions = request.app.state.dashboard_sessions
    for key, entry in list(sessions.items()):
        if entry[1] <= time.time():
            sessions.pop(key, None)
    if len(sessions) >= 128:
        raise HTTPException(429, "Too many development sessions; restart the local server")
    previous = request.cookies.get(COOKIE)
    if previous:
        sessions.pop(hashlib.sha256(previous.encode()).hexdigest(), None)
    token = secrets.token_urlsafe(32)
    sessions[hashlib.sha256(token.encode()).hexdigest()] = (user.id, time.time() + 28800)
    response.set_cookie(COOKIE, token, httponly=True, secure=request.url.scheme == "https",
                        samesite="strict", max_age=28800, path="/api/v1/dashboard")
    response.headers["Cache-Control"] = "no-store"
    return {"csrf_token": csrf(token)}


@router.post("/sign-out")
def sign_out(request: Request, response: Response, user: User = Depends(actor)):
    token = request.cookies.get(COOKIE, "")
    request.app.state.dashboard_sessions.pop(hashlib.sha256(token.encode()).hexdigest(), None)
    response.delete_cookie(COOKIE, path="/api/v1/dashboard")
    return {"signed_out": True}


def merchant_for(session, user):
    if user.role != "merchant":
        raise HTTPException(403, "Only merchants can edit their offers")
    merchant = session.scalar(select(Merchant).where(Merchant.owner_user_id == user.id).order_by(Merchant.id))
    if not merchant:
        raise HTTPException(409, "No merchant profile is linked to this account")
    return merchant


def owned_offer(session, user, public_id):
    merchant = merchant_for(session, user)
    offer = session.scalar(select(Offer).where(Offer.public_id == str(public_id), Offer.merchant_id == merchant.id))
    if not offer:
        raise HTTPException(404, "Offer unavailable")
    return offer


def owned_campaign(session, user, public_id):
    campaign = session.scalar(select(Campaign).where(Campaign.public_id == str(public_id)))
    if not campaign:
        raise HTTPException(404, "Campaign unavailable")
    try:
        require_campaign_owner(session, user.id, campaign)
    except AuthorizationError:
        raise HTTPException(404, "Campaign unavailable") from None
    return campaign


def status(item):
    now = datetime.now(timezone.utc)
    if not item.active:
        return "inactive"
    if item.end_at and aware(item.end_at) <= now:
        return "expired"
    if item.start_at and aware(item.start_at) > now:
        return "scheduled"
    return "active"


def offer_json(offer, merchant):
    return {"id": offer.public_id, "merchant": merchant.name, "merchant_id": merchant.public_id,
            "title": offer.title, "description": offer.description, "terms": offer.terms,
            "image_url": offer.image_url, "start_at": aware(offer.start_at), "end_at": aware(offer.end_at),
            "active": offer.active, "manager_eligible": offer.manager_eligible, "status": status(offer)}


def campaign_json(session, campaign):
    links = session.execute(select(Offer.public_id, CampaignOffer.display_order).join(
        CampaignOffer, CampaignOffer.offer_id == Offer.id).where(
        CampaignOffer.campaign_id == campaign.id, CampaignOffer.active.is_(True)).order_by(CampaignOffer.display_order)).all()
    return {"id": campaign.public_id, "name": campaign.name, "active": campaign.active,
            "sample": campaign.sample, "start_at": aware(campaign.start_at), "end_at": aware(campaign.end_at),
            "status": status(campaign), "offer_ids": [row[0] for row in links]}


@router.get("/workspace")
def workspace(request: Request, response: Response, user: User = Depends(actor), session: Session = Depends(db)):
    response.headers["Cache-Control"] = "no-store"
    merchant = merchant_for(session, user) if user.role == "merchant" else None
    offers_query = select(Offer, Merchant).join(Merchant, Merchant.id == Offer.merchant_id)
    if merchant:
        offers_query = offers_query.where(Offer.merchant_id == merchant.id)
        campaigns_query = select(Campaign).where(Campaign.merchant_id == merchant.id)
    else:
        offers_query = offers_query.where(Offer.manager_eligible.is_(True), Merchant.active.is_(True))
        campaigns_query = select(Campaign).where(Campaign.manager_user_id == user.id)
    campaigns = list(session.scalars(campaigns_query.order_by(Campaign.updated_at.desc())))
    beacons = []
    for beacon in session.scalars(select(Beacon).where(Beacon.owner_user_id == user.id)):
        campaign = session.get(Campaign, beacon.campaign_id) if beacon.campaign_id else None
        result = lookup_offers(session, beacon.payload_id, datetime.now(timezone.utc))
        beacons.append({"id": beacon.public_id, "beacon_id": f"0x{beacon.payload_id:06X}", "active": beacon.active,
            "campaign_id": campaign.public_id if campaign else None,
            "served_offers": [item.model_dump(mode="json") for item in result.offers] if result else []})
    return {"account": {"email": user.email, "role": user.role,
                "business": merchant.name if merchant else "Acoustic Beacon Network",
                "description": merchant.description if merchant else "Authorized merchant campaigns"},
            "csrf_token": csrf(request.cookies.get(COOKIE, "")),
            "offers": [offer_json(o, m) for o, m in session.execute(offers_query.order_by(Offer.updated_at.desc()))],
            "campaigns": [campaign_json(session, c) for c in campaigns], "beacons": beacons,
            "analytics_available": merchant is not None, "development": True}


@router.post("/offers", status_code=201)
def add_offer(data: OfferInput, user: User = Depends(actor), session: Session = Depends(db)):
    merchant = merchant_for(session, user)
    offer = create_offer(session, user.id, merchant.id, data)
    session.commit()
    return offer_json(offer, merchant)


@router.put("/offers/{public_id}")
def edit_offer(public_id: UUID, data: OfferInput, user: User = Depends(actor), session: Session = Depends(db)):
    offer = owned_offer(session, user, public_id)
    values = data.model_dump()
    values["image_url"] = str(data.image_url) if data.image_url else None
    for key, value in values.items():
        setattr(offer, key, value)
    session.commit()
    return offer_json(offer, session.get(Merchant, offer.merchant_id))


class CampaignInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=200)
    active: bool = False
    start_at: datetime | None = None
    end_at: datetime | None = None
    offer_ids: list[UUID] = Field(default_factory=list, max_length=100)

    @field_validator("start_at", "end_at")
    @classmethod
    def date_zone(cls, value):
        return OfferInput.aware_dates(value)

    @model_validator(mode="after")
    def valid_window(self):
        if self.start_at and self.end_at and self.end_at <= self.start_at:
            raise ValueError("End must be after start")
        if len(set(self.offer_ids)) != len(self.offer_ids):
            raise ValueError("Select each offer once")
        return self


def save_campaign(session, user, campaign, data):
    campaign.name, campaign.active = data.name, data.active
    campaign.start_at, campaign.end_at = data.start_at, data.end_at
    session.add(campaign)
    session.flush()
    session.execute(delete(CampaignOffer).where(CampaignOffer.campaign_id == campaign.id))
    for order, public_id in enumerate(data.offer_ids):
        offer = session.scalar(select(Offer).where(Offer.public_id == str(public_id)))
        if not offer:
            raise HTTPException(422, "A selected offer is unavailable")
        try:
            attach_offer(session, user.id, campaign, offer, order)
        except AuthorizationError:
            raise HTTPException(403, "A selected offer is not authorized for this campaign") from None
    session.commit()
    return campaign_json(session, campaign)


@router.post("/campaigns", status_code=201)
def add_campaign(data: CampaignInput, user: User = Depends(actor), session: Session = Depends(db)):
    campaign = Campaign(merchant_id=merchant_for(session, user).id) if user.role == "merchant" else Campaign(manager_user_id=user.id)
    return save_campaign(session, user, campaign, data)


@router.put("/campaigns/{public_id}")
def edit_campaign(public_id: UUID, data: CampaignInput, user: User = Depends(actor), session: Session = Depends(db)):
    return save_campaign(session, user, owned_campaign(session, user, public_id), data)


class Assignment(BaseModel):
    model_config = ConfigDict(extra="forbid")
    campaign_id: UUID | None


@router.put("/beacons/{public_id}/campaign")
def update_assignment(public_id: UUID, data: Assignment, user: User = Depends(actor), session: Session = Depends(db)):
    beacon = session.scalar(select(Beacon).where(Beacon.public_id == str(public_id), Beacon.owner_user_id == user.id))
    if not beacon:
        raise HTTPException(404, "Beacon unavailable")
    if data.campaign_id is None:
        beacon.campaign_id = None
    else:
        assign_beacon(session, user.id, beacon, owned_campaign(session, user, data.campaign_id))
    session.commit()
    return {"updated": True}


@router.get("/activity")
def customer_activity(response: Response, period: Literal['today', '7d', '30d', '90d', '12m'] = 'today',
                      user: User = Depends(actor), session: Session = Depends(db)):
    from .activity import summarize
    response.headers['Cache-Control'] = 'no-store'
    merchant = merchant_for(session, user)
    return summarize(session, merchant.id, period, datetime.now(timezone.utc))
