from datetime import timedelta
from uuid import UUID

import pytest
from sqlalchemy import func, select

from app.domain import attach_offer, create_offer
from app.models import Beacon, Campaign, CampaignOffer, Merchant, Offer
from app.schemas import OfferInput
from conftest import NOW

URL = "/api/v1/beacons/0xABC123/offers"


def test_active_lookup_and_public_contract(client, session):
    before = {table.name: session.scalar(select(func.count()).select_from(table))
        for table in Beacon.metadata.sorted_tables}
    response = client.get(URL)
    assert response.status_code == 200
    data = response.json()
    assert data["beacon_id"] == "0xABC123"
    assert data["campaign"]["sample"] is True
    assert UUID(data["campaign"]["id"])
    assert data["offers"][0]["title"] == "wookiemeat"
    assert data["offers"][0]["merchant"]["location"] is None
    assert "owner_user_id" not in response.text
    assert "manager_user_id" not in response.text
    assert "merchant_id" not in response.text
    assert "email" not in response.text
    assert response.headers["cache-control"] == "no-store"
    after = {table.name: session.scalar(select(func.count()).select_from(table))
        for table in Beacon.metadata.sorted_tables}
    assert before == after


@pytest.mark.parametrize("identifier", ["abc123", "0xabc123", "0XABC123"])
def test_canonical_identifier(client, identifier):
    assert client.get(f"/api/v1/beacons/{identifier}/offers").json()["beacon_id"] == "0xABC123"


def test_unknown(client):
    assert client.get("/api/v1/beacons/0x000001/offers").status_code == 404


@pytest.mark.parametrize("identifier", ["wookiemeat", "0x1000000", "ABC12", "GGGGGG", "1234567", "1%27OR%271"])
def test_invalid_id(client, identifier):
    assert client.get(f"/api/v1/beacons/{identifier}/offers").status_code == 422


@pytest.mark.parametrize("model,field,value,status", [
    (Beacon, "active", False, 404),
    (Beacon, "campaign_id", None, 200),
    (Campaign, "active", False, 200),
    (Campaign, "start_at", NOW + timedelta(seconds=1), 200),
    (Campaign, "end_at", NOW - timedelta(seconds=1), 200),
    (Campaign, "end_at", NOW, 200),
    (Offer, "active", False, 200),
    (Offer, "start_at", NOW + timedelta(seconds=1), 200),
    (Offer, "end_at", NOW - timedelta(seconds=1), 200),
    (Offer, "end_at", NOW, 200),
    (Merchant, "active", False, 200),
    (CampaignOffer, "active", False, 200),
])
def test_unavailable_content_is_filtered(client, session, model, field, value, status):
    setattr(session.scalar(select(model)), field, value)
    session.commit()
    response = client.get(URL)
    assert response.status_code == status
    if status == 200:
        assert response.json()["offers"] == []


def test_start_inclusive_and_multiple_offers_ordered(client, session):
    campaign = session.scalar(select(Campaign))
    merchant = session.scalar(select(Merchant))
    campaign.start_at = NOW
    second = create_offer(session, merchant.owner_user_id, merchant.id,
        OfferInput(title="Second sample", description="Sample", terms="Not redeemable", active=True, start_at=NOW))
    attach_offer(session, merchant.owner_user_id, campaign, second, 1)
    session.commit()
    data = client.get(URL).json()
    assert [o["title"] for o in data["offers"]] == ["wookiemeat", "Second sample"]
    assert {o["merchant"]["id"] for o in data["offers"]} == {merchant.public_id}


def test_location_is_stored_merchant_location(client, session):
    merchant = session.scalar(select(Merchant))
    merchant.latitude, merchant.longitude = 10.0, 20.0
    session.commit()
    # Unused query values cannot become a fabricated merchant/speaker position.
    data = client.get(URL + "?latitude=50&longitude=60").json()
    assert data["offers"][0]["merchant"]["location"] == {"latitude": 10.0, "longitude": 20.0}


def test_post_is_not_available(client):
    assert client.post(URL, json={"active": True}).status_code == 405
