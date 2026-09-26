from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_validator, model_validator


class OfferInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    title: Annotated[str, Field(min_length=1, max_length=200)]
    description: Annotated[str, Field(min_length=1, max_length=20000)]
    terms: Annotated[str, Field(min_length=1, max_length=20000)]
    image_url: HttpUrl | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    active: bool = False
    manager_eligible: bool = False

    @field_validator("image_url")
    @classmethod
    def safe_image(cls, value):
        if value and (value.scheme != "https" or value.username or value.password):
            raise ValueError("Image URL must use HTTPS without credentials")
        return value

    @field_validator("start_at", "end_at")
    @classmethod
    def aware_dates(cls, value):
        if value is not None:
            if value.utcoffset() is None:
                raise ValueError("Timestamps must include a timezone")
            return value.astimezone(timezone.utc)
        return value

    @model_validator(mode="after")
    def ordered_dates(self):
        if self.start_at and self.end_at and self.end_at <= self.start_at:
            raise ValueError("end_at must be later than start_at")
        return self


class LocationOut(BaseModel):
    latitude: float
    longitude: float


class MerchantOut(BaseModel):
    id: UUID
    name: str
    description: str
    address: str | None
    city: str | None
    country_code: str | None
    location: LocationOut | None


class OfferOut(BaseModel):
    id: UUID
    title: str
    description: str
    terms: str
    image_url: str | None
    start_at: datetime | None
    end_at: datetime | None
    merchant: MerchantOut


class CampaignOut(BaseModel):
    id: UUID
    name: str
    sample: bool


class BeaconOffersOut(BaseModel):
    beacon_id: str
    campaign: CampaignOut | None
    offers: list[OfferOut]
