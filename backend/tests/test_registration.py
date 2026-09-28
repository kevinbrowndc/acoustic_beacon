from concurrent.futures import ThreadPoolExecutor
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from app.models import User, Merchant, AccountCredential, AccountSession
from app.auth import verify_password
from app.config import Settings
from app.main import create_app
from app.account_startup import prepare_accounts
from app.database import make_engine
from test_production_auth import production, encoded, ORIGIN, PASSWORD

def payload(**changes):
    return {'business_name':'New business','contact_name':'Owner name','email':'new@example.invalid','password':PASSWORD,'confirm_password':PASSWORD,**changes}

def register(c,**changes):
    r=c.post('/api/v1/dashboard/register',json=payload(**changes))
    if r.status_code==201:c.headers['X-CSRF-Token']=r.json()['csrf_token']
    return r

def test_signup_empty_workspace_hash_and_login(production,engine):
    assert register(production).status_code==201
    w=production.get('/api/v1/dashboard/workspace').json()
    assert w['account']['role']=='merchant' and w['account']['business']=='New business'
    assert w['offers']==w['campaigns']==[]
    assert len(w['beacons'])==1
    assert w['development'] is False
    with Session(engine) as s:
        u=s.scalar(select(User).where(User.email=='new@example.invalid'))
        assert u.role=='merchant'
        m=s.scalar(select(Merchant).where(Merchant.owner_user_id==u.id))
        assert m.contact_name=='Owner name'
        password_hash=s.get(AccountCredential,u.id).password_hash
        assert PASSWORD not in password_hash and verify_password(PASSWORD,password_hash)
    assert production.post('/api/v1/dashboard/sign-out').status_code==200
    assert production.post('/api/v1/dashboard/session',json={'email':'new@example.invalid','password':'wrong'}).status_code==401
    assert production.post('/api/v1/dashboard/session',json={'email':'new@example.invalid','password':PASSWORD}).status_code==200
    assert production.get('/api/v1/dashboard/workspace').status_code==200

@pytest.mark.parametrize('changes',[{'password':'short','confirm_password':'short'},{'confirm_password':'different long password'}, {'role':'manager'},{'role':'merchant'},{'user_id':1},{'business_name':'   '},{'contact_name':' '},{'email':'bad-email'}])
def test_invalid_registration(production,changes):
    r=register(production,**changes)
    assert r.status_code==422 and PASSWORD not in r.text
    assert production.get('/api/v1/dashboard/workspace').status_code==401

def test_duplicate_and_privileged_email_same_error(production,engine):
    assert register(production).status_code==201
    same=register(production,email='NEW@example.invalid')
    privileged=register(production,email='owner@example.invalid')
    assert same.status_code==privileged.status_code==409
    assert same.json()==privileged.json()
    assert 'manager' not in same.text.lower()
    with Session(engine) as s:
        assert s.scalar(select(func.count()).select_from(User).where(User.email=='new@example.invalid'))==1
        assert s.scalar(select(User).where(User.email=='owner@example.invalid')).role=='manager'

def test_ownership_across_registered_merchants(production):
    register(production)
    offer=production.post('/api/v1/dashboard/offers',json={'title':'Private A','description':'Own','terms':'Own'}).json()
    campaign=production.post('/api/v1/dashboard/campaigns',json={'name':'Private A','offer_ids':[offer['id']]}).json()
    register(production,email='second@example.invalid')
    w=production.get('/api/v1/dashboard/workspace').json()
    assert w['offers']==w['campaigns']==[]
    assert production.put('/api/v1/dashboard/offers/'+offer['id'],json={'title':'Attack','description':'X','terms':'X'}).status_code==404
    assert production.put('/api/v1/dashboard/campaigns/'+campaign['id'],json={'name':'Attack'}).status_code==404

def test_signup_origin_and_throttle(production,monkeypatch):
    production.headers['Origin']='https://evil.example'
    assert register(production).status_code==403
    production.headers['Origin']=ORIGIN
    monkeypatch.setattr('app.auth.hash_password',lambda *a:'not-a-real-hash')
    assert register(production).status_code==201
    for _ in range(4):assert register(production).status_code==409
    assert register(production).status_code==429

def test_registration_unique_under_race(production,engine):
    settings=Settings(environment='production',database_url='postgresql://fake:fake@localhost/fake',_env_file=None)
    def attempt(_):
        with TestClient(create_app(settings,engine),base_url=ORIGIN) as c:
            c.headers['Origin']=ORIGIN
            return register(c,email='race@example.invalid').status_code
    with ThreadPoolExecutor(max_workers=2) as pool:codes=list(pool.map(attempt,range(2)))
    assert sorted(codes)==[201,409]
    with Session(engine) as s:assert s.scalar(select(func.count()).select_from(User).where(User.email=='race@example.invalid'))==1

def test_startup_migrates_and_private_manager_once(tmp_path):
    url='sqlite:///'+(tmp_path/'startup.db').as_posix()
    engine=make_engine(url)
    settings=Settings(database_url=url,bootstrap_manager_email='private@example.invalid',bootstrap_manager_password=PASSWORD,_env_file=None)
    prepare_accounts(engine,settings)
    prepare_accounts(engine,settings)
    with Session(engine) as s:
        users=list(s.scalars(select(User)))
        assert len(users)==1 and users[0].role=='manager'
        assert verify_password(PASSWORD,s.get(AccountCredential,users[0].id).password_hash)
        assert not list(s.scalars(select(Merchant)))
    # Later changed deployment settings never reset the password or add a second Manager.
    prepare_accounts(engine,Settings(database_url=url,bootstrap_manager_email='other@example.invalid',bootstrap_manager_password='a different strong passphrase',_env_file=None))
    with Session(engine) as s:assert s.scalar(select(func.count()).select_from(User))==1
    engine.dispose()

def test_startup_without_private_secrets_does_not_create_manager(tmp_path):
    url='sqlite:///'+(tmp_path/'no-owner.db').as_posix();engine=make_engine(url)
    prepare_accounts(engine,Settings(database_url=url,_env_file=None))
    with Session(engine) as s:assert not list(s.scalars(select(User)))
    engine.dispose()
