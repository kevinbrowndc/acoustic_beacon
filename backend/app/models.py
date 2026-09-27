from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import Boolean, CheckConstraint, DateTime, Float, ForeignKey, Integer, String, Text, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def utcnow():
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Identity:
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    public_id: Mapped[str] = mapped_column(String(36), unique=True, default=lambda: str(uuid4()))


class Timestamps:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)


class User(Identity, Timestamps, Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint("role IN ('merchant', 'manager')", name="ck_user_role"),
        CheckConstraint("email = lower(trim(email)) AND length(email) > 3", name="ck_user_email_normalized"),
    )
    email: Mapped[str] = mapped_column(String(320), unique=True)
    role: Mapped[str] = mapped_column(String(16))


class Merchant(Identity, Timestamps, Base):
    __tablename__ = "merchants"
    __table_args__ = (
        CheckConstraint("length(trim(name)) > 0", name="ck_merchant_name"),
        CheckConstraint("(latitude IS NULL AND longitude IS NULL) OR (latitude IS NOT NULL AND longitude IS NOT NULL AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)", name="ck_merchant_coordinates"),
    )
    owner_user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text, default="")
    address: Mapped[str | None] = mapped_column(String(500))
    city: Mapped[str | None] = mapped_column(String(100))
    country_code: Mapped[str | None] = mapped_column(String(2))
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    active: Mapped[bool] = mapped_column(Boolean, default=False)


class Offer(Identity, Timestamps, Base):
    __tablename__ = "offers"
    __table_args__ = (
        CheckConstraint("length(trim(title)) > 0", name="ck_offer_title"),
        CheckConstraint("start_at IS NULL OR end_at IS NULL OR end_at > start_at", name="ck_offer_window"),
    )
    merchant_id: Mapped[int] = mapped_column(ForeignKey("merchants.id", ondelete="RESTRICT"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text)
    terms: Mapped[str] = mapped_column(Text)
    image_url: Mapped[str | None] = mapped_column(String(2048))
    start_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    active: Mapped[bool] = mapped_column(Boolean, default=False)
    manager_eligible: Mapped[bool] = mapped_column(Boolean, default=False)


class Campaign(Identity, Timestamps, Base):
    __tablename__ = "campaigns"
    __table_args__ = (
        CheckConstraint("(merchant_id IS NOT NULL AND manager_user_id IS NULL) OR (merchant_id IS NULL AND manager_user_id IS NOT NULL)", name="ck_campaign_one_owner"),
        CheckConstraint("start_at IS NULL OR end_at IS NULL OR end_at > start_at", name="ck_campaign_window"),
        CheckConstraint("length(trim(name)) > 0", name="ck_campaign_name"),
    )
    name: Mapped[str] = mapped_column(String(200))
    merchant_id: Mapped[int | None] = mapped_column(ForeignKey("merchants.id", ondelete="RESTRICT"), index=True)
    manager_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    active: Mapped[bool] = mapped_column(Boolean, default=False)
    sample: Mapped[bool] = mapped_column(Boolean, default=False)
    start_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class CampaignOffer(Base):
    __tablename__ = "campaign_offers"
    __table_args__ = (CheckConstraint("display_order >= 0", name="ck_campaign_offer_order"),)
    campaign_id: Mapped[int] = mapped_column(ForeignKey("campaigns.id", ondelete="CASCADE"), primary_key=True)
    offer_id: Mapped[int] = mapped_column(ForeignKey("offers.id", ondelete="RESTRICT"), primary_key=True, index=True)
    display_order: Mapped[int] = mapped_column(Integer, default=0)
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class Beacon(Identity, Timestamps, Base):
    __tablename__ = "beacons"
    __table_args__ = (CheckConstraint("payload_id BETWEEN 0 AND 16777215", name="ck_beacon_24bit"),)
    payload_id: Mapped[int] = mapped_column(Integer, unique=True)
    owner_user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    campaign_id: Mapped[int | None] = mapped_column(ForeignKey("campaigns.id", ondelete="RESTRICT"), index=True)
    active: Mapped[bool] = mapped_column(Boolean, default=False)


class ActivityEvent(Base):
    """Trusted event ingestion only; no customer identity or arbitrary public writes."""
    __tablename__ = "activity_events"
    __table_args__ = (
        CheckConstraint("kind IN ('detections', 'views', 'saves', 'actions')", name="ck_activity_kind"),
        Index("ix_activity_merchant_time", "merchant_id", "occurred_at"),
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    event_key: Mapped[str] = mapped_column(String(128), unique=True)
    merchant_id: Mapped[int] = mapped_column(ForeignKey("merchants.id", ondelete="RESTRICT"))
    kind: Mapped[str] = mapped_column(String(16))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
