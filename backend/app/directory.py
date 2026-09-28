"""Explicit opt-in public projection; never serialize the private Merchant model."""
import re
from pydantic import BaseModel, ConfigDict, HttpUrl, TypeAdapter, field_validator, model_validator
from sqlalchemy import select
from .models import Merchant, User, AccountCredential

URL=TypeAdapter(HttpUrl)

def normalize_website(value):
    if value is None or value=='':return None
    if not isinstance(value,str):raise ValueError('Enter a valid business website')
    value=value.strip()
    if not value:return None
    if len(value)>2048 or any(c.isspace() or ord(c)<32 for c in value) or '\\' in value:
        raise ValueError('Enter a valid business website')
    if value.startswith('//'):value='https:'+value
    elif not re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:',value):value='https://'+value
    from urllib.parse import urlsplit
    if not urlsplit(value).netloc:raise ValueError('Enter a valid business website')
    url=URL.validate_python(value)
    if url.username or url.password or not url.host or '.' not in url.host:
        raise ValueError('Enter a public business website without credentials')
    normalized=str(url)
    if len(normalized)>2048:raise ValueError('Website is too long')
    return normalized

class DirectoryProfile(BaseModel):
    model_config=ConfigDict(extra='forbid')
    website: str | None = None
    directory_opt_in: bool = False

    @field_validator('website',mode='before')
    @classmethod
    def website_url(cls,value):return normalize_website(value)

    @model_validator(mode='after')
    def listing_needs_website(self):
        if self.directory_opt_in and not self.website:
            raise ValueError('Add a website before enabling the directory listing')
        return self

def public_businesses(session):
    rows=session.execute(select(Merchant.name,Merchant.website).join(User,User.id==Merchant.owner_user_id).join(
        AccountCredential,AccountCredential.user_id==User.id).where(
        Merchant.active.is_(True), Merchant.directory_opt_in.is_(True), Merchant.website.is_not(None),
        User.role=='merchant', AccountCredential.enabled.is_(True),
        ~User.email.like('%@example.invalid')).order_by(Merchant.name,Merchant.id))
    result=[]
    for name,website in rows:
        try:website=normalize_website(website)
        except (ValueError,TypeError):continue
        if website:result.append({'business_name':name,'website':website})
    return result
