from datetime import datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.auth import COOKIE, digest, hash_password, verify_password
from app.bootstrap_manager import provision
from app.config import Settings
from app.main import create_app
from app.models import AccountCredential, AccountSession, User, Merchant

ORIGIN='https://merchant.acousticbeacon.com'
PASSWORD='test-only long passphrase 927!'

@pytest.fixture(scope='module')
def encoded():
    return hash_password(PASSWORD)

@pytest.fixture
def production(engine,encoded):
    with Session(engine) as s,s.begin():
        u=User(email='owner@example.invalid',role='manager');s.add(u);s.flush()
        s.add(AccountCredential(user_id=u.id,password_hash=encoded,enabled=True))
    settings=Settings(environment='production',database_url='postgresql://fake:fake@localhost/fake',_env_file=None)
    with TestClient(create_app(settings,engine),base_url=ORIGIN) as c:
        c.headers['Origin']=ORIGIN
        yield c

def login(c,**changes):
    r=c.post('/api/v1/dashboard/session',json={'email':'OWNER@example.invalid','password':PASSWORD,**changes})
    if r.status_code==200:c.headers['X-CSRF-Token']=r.json()['csrf_token']
    return r

def test_password_hash_not_plaintext_and_salted(encoded):
    assert PASSWORD not in encoded
    assert verify_password(PASSWORD,encoded)
    assert not verify_password('incorrect',encoded)
    assert hash_password(PASSWORD)!=encoded

def test_manager_signin_real_workspace_and_signout(production,engine):
    assert production.get('/api/v1/dashboard/workspace').status_code==401
    r=login(production);assert r.status_code==200
    cookie=r.headers['set-cookie'].lower()
    assert all(v in cookie for v in ['secure','httponly','samesite=strict','path=/'])
    assert 'domain=' not in cookie
    w=production.get('/api/v1/dashboard/workspace').json()
    assert w['account']['email']=='owner@example.invalid'
    assert w['account']['role']=='manager' and w['development'] is False
    assert w['campaigns']==[] and w['beacons']==[]
    assert w['csrf_token']==r.json()['csrf_token']
    create=production.post('/api/v1/dashboard/campaigns',json={'name':'Real owner campaign','offer_ids':[]})
    assert create.status_code==201
    with Session(engine) as s:
        session=s.scalar(select(AccountSession));assert session.token_hash==digest(production.cookies.get(COOKIE))
    assert production.post('/api/v1/dashboard/sign-out').status_code==200
    assert production.get('/api/v1/dashboard/workspace').status_code==401

def test_invalid_unknown_disabled_and_generic_errors(production,engine):
    wrong=login(production,password='incorrect')
    unknown=login(production,email='unknown@example.invalid')
    assert wrong.status_code==unknown.status_code==401
    assert wrong.json()==unknown.json()
    with Session(engine) as s,s.begin():
        c=s.scalar(select(AccountCredential));c.enabled=False
    assert login(production).status_code==401

def test_csrf_and_cross_origin(production):
    production.headers['Origin']='https://evil.example'
    assert login(production).status_code==403
    production.headers['Origin']=ORIGIN
    assert login(production).status_code==200
    production.headers.pop('X-CSRF-Token')
    assert production.post('/api/v1/dashboard/sign-out').status_code==403
    production.headers['X-CSRF-Token']='forged'
    assert production.post('/api/v1/dashboard/campaigns',json={'name':'Denied'}).status_code==403

def test_missing_origin_rejected(production):
    production.headers.pop('Origin')
    assert login(production).status_code==403

def test_expired_revoked_and_restart_sessions(production,engine):
    assert login(production).status_code==200
    settings=Settings(environment='production',database_url='postgresql://fake:fake@localhost/fake',_env_file=None)
    with TestClient(create_app(settings,engine),base_url=ORIGIN) as other:
        other.cookies.update(production.cookies)
        assert other.get('/api/v1/dashboard/workspace').status_code==200
    with Session(engine) as s,s.begin():
        entry=s.scalar(select(AccountSession));entry.expires_at=datetime.now(timezone.utc)-timedelta(seconds=1)
    assert production.get('/api/v1/dashboard/workspace').status_code==401
    assert login(production).status_code==200
    with Session(engine) as s,s.begin():s.scalar(select(AccountCredential)).enabled=False
    assert production.get('/api/v1/dashboard/workspace').status_code==401

def test_session_rotation(production,engine):
    login(production);old=production.cookies.get(COOKIE)
    login(production);assert old!=production.cookies.get(COOKIE)
    with Session(engine) as s:assert s.get(AccountSession,digest(old)) is None

def test_login_rate_shared_across_apps(production,engine,monkeypatch):
    monkeypatch.setattr('app.auth.verify_password',lambda *args:False)
    for _ in range(10):assert login(production).status_code==401
    assert login(production).status_code==429
    settings=Settings(environment='production',database_url='postgresql://fake:fake@localhost/fake',_env_file=None)
    with TestClient(create_app(settings,engine),base_url=ORIGIN) as other:
        other.headers['Origin']=ORIGIN
        assert login(other).status_code==429

def test_no_role_selection_or_password_echo(production):
    r=production.post('/api/v1/dashboard/session',json={'email':'owner@example.invalid','password':PASSWORD,'role':'manager'})
    assert r.status_code==422 and PASSWORD not in r.text
    assert production.post('/api/v1/dashboard/dev-session',json={'role':'manager'}).status_code==404

def test_bootstrap_only_creates_manager_and_never_replaces_data(session):
    before=list(session.scalars(select(Merchant.id)))
    user=provision(session,'new-owner@example.invalid',PASSWORD)
    assert user.role=='manager'
    assert session.get(AccountCredential,user.id)
    with pytest.raises(ValueError):provision(session,user.email,PASSWORD)
    existing=session.scalar(select(User).where(User.role=='merchant'))
    with pytest.raises(ValueError):provision(session,existing.email,PASSWORD)
    assert list(session.scalars(select(Merchant.id)))==before

def test_merchant_role_ownership_unchanged(production,engine,encoded):
    with Session(engine) as s,s.begin():
        merchant=s.scalar(select(Merchant));u=s.get(User,merchant.owner_user_id)
        email=u.email;s.add(AccountCredential(user_id=u.id,password_hash=encoded,enabled=True))
    assert login(production,email=email).status_code==200
    w=production.get('/api/v1/dashboard/workspace').json()
    assert w['account']['role']=='merchant' and w['offers']
    assert production.get('/api/v1/dashboard/activity').status_code==200
    assert production.post('/api/v1/dashboard/offers',json={'title':'Own offer','description':'Real','terms':'Terms'}).status_code==201
