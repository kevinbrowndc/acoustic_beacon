import pytest
from sqlalchemy import select
from app.directory import normalize_website
from app.models import Merchant,User,AccountCredential
from test_production_auth import production,encoded
from test_registration import register

@pytest.mark.parametrize('value,result',[('example.com','https://example.com/'),(' https://Example.com/path ','https://example.com/path'),('http://example.com','http://example.com/'),('',None)])
def test_normalization(value,result):assert normalize_website(value)==result

@pytest.mark.parametrize('value',['javascript:alert(1)','data:text/html,x','file:///tmp/x','ftp://example.com','not a website','http:///example.com','https://user:pass@example.com','https://','https://example.com\\evil',123])
def test_unsafe_or_malformed(value):
    with pytest.raises(ValueError):normalize_website(value)

def test_signup_profile_opt_in_and_public_projection(production,session):
    assert register(production,email='business@directory.example',website='Example.com',directory_opt_in=True).status_code==201
    w=production.get('/api/v1/dashboard/workspace').json()
    assert w['account']['website']=='https://example.com/' and w['account']['directory_opt_in'] is True
    rows=production.get('/api/v1/businesses').json()
    assert rows==[{'business_name':'New business','website':'https://example.com/'}]
    assert all(set(row)=={'business_name','website'} for row in rows)
    r=production.put('/api/v1/dashboard/profile',json={'website':'https://updated.example','directory_opt_in':True})
    assert r.status_code==200
    assert production.get('/api/v1/businesses').json()[0]['website']=='https://updated.example/'
    assert production.put('/api/v1/dashboard/profile',json={'website':'updated.example','directory_opt_in':False}).status_code==200
    assert production.get('/api/v1/businesses').json()==[]
    assert production.get('/api/v1/dashboard/workspace').status_code==200

def test_default_opt_out_enable_and_ownership(production):
    assert register(production,email='one@directory.example',website='one.example').status_code==201
    assert production.get('/api/v1/businesses').json()==[]
    assert production.put('/api/v1/dashboard/profile',json={'website':'one.example','directory_opt_in':True}).status_code==200
    assert register(production,email='two@directory.example',website='two.example').status_code==201
    assert production.put('/api/v1/dashboard/profile',json={'website':'two.example','directory_opt_in':True,'merchant_id':1}).status_code==422
    assert production.get('/api/v1/businesses').json()==[{'business_name':'New business','website':'https://one.example/'}]

def test_website_required_for_listing_and_signup_invalid(production):
    assert register(production,directory_opt_in=True).status_code==422
    assert register(production,website='javascript:alert(1)').status_code==422

def test_demo_disabled_accounts_and_private_fields_never_public(production,session,encoded):
    m=session.scalar(select(Merchant));m.directory_opt_in=True;m.website='https://example.com'
    session.add(AccountCredential(user_id=m.owner_user_id,password_hash=encoded,enabled=True));session.commit()
    assert production.get('/api/v1/businesses').json()==[]
    assert register(production,email='disabled@directory.example',website='real.example',directory_opt_in=True).status_code==201
    u=session.scalar(select(User).where(User.email=='disabled@directory.example'));session.get(AccountCredential,u.id).enabled=False;session.commit()
    assert production.get('/api/v1/businesses').json()==[]

def test_profile_requires_merchant_identity(production):
    assert production.put('/api/v1/dashboard/profile',json={'website':'x.example'}).status_code==401
    from test_production_auth import login
    login(production)
    assert production.put('/api/v1/dashboard/profile',json={'website':'x.example'}).status_code==403
