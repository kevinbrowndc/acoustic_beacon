import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.config import Settings
from app.dashboard_seed import seed_dashboard
from app.main import create_app
from app.models import Beacon, Merchant, Offer, User


@pytest.fixture
def dashboard(engine):
    with Session(engine) as session, session.begin():
        seed_dashboard(session)
    with TestClient(create_app(Settings(environment='test', dashboard_dev_auth=True, _env_file=None), engine=engine)) as client:
        yield client


def login(client, role='merchant'):
    response=client.post('/api/v1/dashboard/dev-session',json={'role':role},headers={'X-Beacon-Development':'1'})
    assert response.status_code == 200
    client.headers['X-CSRF-Token']=response.json()['csrf_token']
    return client.get('/api/v1/dashboard/workspace').json()


def payload(title='Fresh offer', **changes):
    return {'title':title,'description':'A real persisted development offer.','terms':'Sample only.', 'active':True, **changes}


def test_session_and_csrf(dashboard):
    assert dashboard.get('/api/v1/dashboard/workspace').status_code == 401
    response=dashboard.post('/api/v1/dashboard/dev-session',json={'role':'merchant'},headers={'X-Beacon-Development':'1','Origin':'https://evil.example'})
    assert response.status_code == 403
    workspace=login(dashboard)
    assert workspace['account']['role']=='merchant'
    assert workspace['analytics_available'] is True
    assert 'httponly' in str(dashboard.cookies).lower() or dashboard.cookies.get('ab_dashboard_session')
    dashboard.headers.pop('X-CSRF-Token')
    assert dashboard.post('/api/v1/dashboard/offers',json=payload()).status_code == 403


def test_development_login_never_available_in_production(engine):
    settings=Settings(environment='production',database_url='postgresql://unused:unused@localhost/unused',dashboard_dev_auth=True,_env_file=None)
    with TestClient(create_app(settings,engine=engine)) as client:
        assert client.post('/api/v1/dashboard/dev-session',json={'role':'merchant'},headers={'X-Beacon-Development':'1'}).status_code == 404
        assert client.get('/api/v1/dashboard/workspace').status_code == 503


def test_offer_create_edit_activate_and_validation(dashboard):
    login(dashboard)
    response=dashboard.post('/api/v1/dashboard/offers',json=payload())
    assert response.status_code == 201
    offer=response.json()
    assert offer['status']=='active'
    response=dashboard.put('/api/v1/dashboard/offers/'+offer['id'],json=payload('Updated',active=False,manager_eligible=True))
    assert response.status_code == 200
    assert response.json()['status']=='inactive'
    assert response.json()['manager_eligible'] is True
    assert dashboard.post('/api/v1/dashboard/offers',json=payload(image_url='javascript:alert(1)')).status_code == 422
    assert dashboard.post('/api/v1/dashboard/offers',json=payload(merchant_id=99)).status_code == 422


def test_cross_merchant_ownership(dashboard,session):
    login(dashboard)
    partner=session.scalar(select(Offer).join(Merchant).where(Merchant.name=='Partner Studio (sample)'))
    assert dashboard.put('/api/v1/dashboard/offers/'+partner.public_id,json=payload()).status_code == 404
    response=dashboard.post('/api/v1/dashboard/campaigns',json={'name':'Stolen content','active':True,'offer_ids':[partner.public_id]})
    assert response.status_code == 403
    assert all(c['name']!='Stolen content' for c in dashboard.get('/api/v1/dashboard/workspace').json()['campaigns'])


def test_campaign_multiple_selection_and_beacon_contract(dashboard):
    workspace=login(dashboard)
    first=next(o for o in workspace['offers'] if o['title']=='wookiemeat')
    second=dashboard.post('/api/v1/dashboard/offers',json=payload()).json()
    campaign=dashboard.post('/api/v1/dashboard/campaigns',json={'name':'Two discoveries','active':True,'offer_ids':[first['id'],second['id']]}).json()
    beacon=workspace['beacons'][0]
    response=dashboard.put('/api/v1/dashboard/beacons/'+beacon['id']+'/campaign',json={'campaign_id':campaign['id']})
    assert response.status_code==200
    result=dashboard.get('/api/v1/beacons/0xABC123/offers').json()
    assert {o['title'] for o in result['offers']}=={'wookiemeat','Fresh offer'}
    assert result['beacon_id']=='0xABC123'
    dashboard.put('/api/v1/dashboard/campaigns/'+campaign['id'],json={'name':'Updated collection','active':True,'offer_ids':[second['id']]})
    assert len(dashboard.get('/api/v1/beacons/0xABC123/offers').json()['offers'])==1
    dashboard.put('/api/v1/dashboard/offers/'+second['id'],json=payload(active=False))
    assert dashboard.get('/api/v1/beacons/0xABC123/offers').json()['offers']==[]


def test_manager_cannot_edit_and_revocation_is_enforced(dashboard,engine):
    merchant_workspace=login(dashboard)
    own=next(o for o in merchant_workspace['offers'] if o['title']=='wookiemeat')
    dashboard.put('/api/v1/dashboard/offers/'+own['id'],json=payload('wookiemeat',manager_eligible=True))
    manager_workspace=login(dashboard,'manager')
    assert len({o['merchant_id'] for o in manager_workspace['offers']})==2
    assert dashboard.put('/api/v1/dashboard/offers/'+own['id'],json=payload()).status_code==403
    ids=[o['id'] for o in manager_workspace['offers'] if o['active']]
    response=dashboard.post('/api/v1/dashboard/campaigns',json={'name':'Network collection','active':True,'offer_ids':ids})
    assert response.status_code==201
    campaign=response.json()
    assert dashboard.put('/api/v1/dashboard/campaigns/'+merchant_workspace['campaigns'][0]['id'],json={'name':'No','offer_ids':[]}).status_code==404
    with Session(engine) as session,session.begin():
        manager=session.scalar(select(User).where(User.role=='manager'))
        beacon=Beacon(payload_id=0xAA0001,owner_user_id=manager.id,active=True)
        session.add(beacon);session.flush();beacon_id=beacon.public_id
    dashboard.put('/api/v1/dashboard/beacons/'+beacon_id+'/campaign',json={'campaign_id':campaign['id']})
    assert len(dashboard.get('/api/v1/beacons/0xAA0001/offers').json()['offers'])==2
    login(dashboard)
    dashboard.put('/api/v1/dashboard/offers/'+own['id'],json=payload('wookiemeat',manager_eligible=False))
    result=dashboard.get('/api/v1/beacons/0xAA0001/offers').json()
    assert [o['title'] for o in result['offers']]==['Discover something local']
    login(dashboard,'manager')
    assert dashboard.put('/api/v1/dashboard/campaigns/'+campaign['id'],json={'name':'Network collection','active':True,'offer_ids':ids}).status_code==403
    assert dashboard.get('/api/v1/beacons/0xAA0001/offers').json()['offers'][0]['title']=='Discover something local'


def test_campaign_validation_and_signout(dashboard):
    login(dashboard)
    response=dashboard.post('/api/v1/dashboard/campaigns',json={'name':'Invalid','start_at':'2030-01-02T12:00:00Z','end_at':'2030-01-01T12:00:00Z'})
    assert response.status_code==422
    assert dashboard.post('/api/v1/dashboard/sign-out').status_code==200
    assert dashboard.get('/api/v1/dashboard/workspace').status_code==401
