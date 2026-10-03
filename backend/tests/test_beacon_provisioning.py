from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
import wave
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.models import User, Merchant, Beacon, AccountCredential
from app.provisioning import ensure_beacon, backfill_merchants
from app.beacon_audio import render_wav, frame_bytes
from app.config import Settings
from app.main import create_app
from test_production_auth import production, encoded, ORIGIN, login
from test_registration import register


def test_signup_resolution_audio_and_isolation(production):
    assert register(production).status_code == 201
    b = production.get('/api/v1/dashboard/workspace').json()['beacons'][0]
    assert b['beacon_id'] != '0xABC123'
    offer = production.post('/api/v1/dashboard/offers', json={'title':'Merchant promotion','description':'Real test','terms':'Test only','active':True}).json()
    campaign = production.post('/api/v1/dashboard/campaigns', json={'name':'Launch','active':True,'offer_ids':[offer['id']]}).json()
    path = '/api/v1/dashboard/beacons/' + b['id']
    assert production.put(path+'/campaign',json={'campaign_id':campaign['id']}).status_code == 200
    found = production.get('/api/v1/beacons/'+b['beacon_id']+'/offers')
    assert found.status_code == 200 and found.json()['offers'][0]['title'] == 'Merchant promotion'
    audio = production.get(path+'/audio.wav')
    assert audio.status_code == 200 and audio.content == render_wav(int(b['beacon_id'],16))
    assert production.get('/api/v1/beacons/0x000000/offers').status_code == 404
    assert register(production,email='b@example.invalid').status_code == 201
    assert production.get(path+'/audio.wav').status_code == 404
    assert production.put(path+'/campaign',json={'campaign_id':campaign['id']}).status_code == 404
    assert production.put('/api/v1/dashboard/support/beacons/'+b['id'],json={'active':False}).status_code == 403
    assert production.get('/api/v1/dashboard/workspace').json()['support_beacons'] is None
    assert login(production).status_code == 200
    assert len(production.get('/api/v1/dashboard/workspace').json()['support_beacons']) == 3
    assert production.put('/api/v1/dashboard/support/beacons/'+b['id'],json={'active':False}).status_code == 200
    assert production.get('/api/v1/beacons/'+b['beacon_id']+'/offers').status_code == 404
    assert production.put('/api/v1/dashboard/support/beacons/'+b['id'],json={'active':True}).status_code == 200
    assert production.get('/api/v1/beacons/'+b['beacon_id']+'/offers').status_code == 200
    production.post('/api/v1/dashboard/sign-out')
    assert production.get(path+'/audio.wav').status_code == 401


def test_client_cannot_choose_id_or_manager(production):
    for extra in [{'beacon_id':'0xABC123'},{'payload_id':123},{'owner_user_id':1},{'role':'manager'}]:
        assert register(production,**extra).status_code == 422


def test_backfill_preserves_assignments_and_disabled_accounts(engine,encoded,monkeypatch):
    with Session(engine) as s,s.begin():
        for n in range(3):
            u=User(email=f'backfill{n}@example.invalid',role='merchant');s.add(u);s.flush()
            s.add(Merchant(owner_user_id=u.id,name=f'Merchant {n}',active=True))
            s.add(AccountCredential(user_id=u.id,password_hash=encoded,enabled=n!=2))
            if n==0:s.add(Beacon(payload_id=777,owner_user_id=u.id,active=True))
    values=iter([0xABC123-1,0xABC123-1,124])
    monkeypatch.setattr('app.provisioning.secrets.randbelow',lambda _:next(values))
    with Session(engine) as s,s.begin():backfill_merchants(s)
    with Session(engine) as s,s.begin():
        before=[(b.id,b.payload_id,b.owner_user_id,b.campaign_id) for b in s.scalars(select(Beacon).order_by(Beacon.id))]
        backfill_merchants(s)
        assert before==[(b.id,b.payload_id,b.owner_user_id,b.campaign_id) for b in s.scalars(select(Beacon).order_by(Beacon.id))]
        assert len(before)==3 and before[0][1]==0xABC123 and before[1][1]==777


def test_collision_retry(engine,monkeypatch):
    with Session(engine) as s,s.begin():
        a=User(email='a@example.invalid',role='merchant');b=User(email='b@example.invalid',role='merchant');s.add_all([a,b]);s.flush()
        s.add(Beacon(payload_id=100,owner_user_id=a.id,active=True));s.flush()
        values=iter([99,100]);monkeypatch.setattr('app.provisioning.secrets.randbelow',lambda _:next(values))
        allocated=ensure_beacon(s,b.id)
        assert allocated.payload_id==101
        assert ensure_beacon(s,b.id).id==allocated.id


def test_concurrent_signups(production,engine):
    settings=Settings(environment='production',database_url='postgresql://fake:fake@localhost/fake',_env_file=None)
    def signup(n):
        with TestClient(create_app(settings,engine),base_url=ORIGIN) as c:
            c.headers['Origin']=ORIGIN
            assert register(c,email=f'parallel{n}@example.invalid').status_code==201
            return c.get('/api/v1/dashboard/workspace').json()['beacons'][0]['beacon_id']
    with ThreadPoolExecutor(max_workers=4) as pool:ids=list(pool.map(signup,range(4)))
    assert len(set(ids))==4


def test_d09_wire_format():
    # CRC-8/SMBUS published check vector and unchanged D09 preamble, MSB ordering.
    assert frame_bytes(0xABC123).hex()=='cda8abc123'+format(_crc(bytes.fromhex('abc123')),'02x')
    with wave.open(BytesIO(render_wav(0xABC123))) as w:
        assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes())==(1,2,48000,295680)


def _crc(data):
    value=0
    for byte in data:
        for shift in range(7,-1,-1):
            feedback=(value>>7)^((byte>>shift)&1)
            value=((value<<1)&255)^(7 if feedback else 0)
    return value


def test_startup_backfill_persists(engine,encoded):
    from app.account_startup import prepare_accounts
    with Session(engine) as s,s.begin():
        u=User(email='existing@example.invalid',role='merchant');s.add(u);s.flush()
        owner=u.id
        s.add(Merchant(owner_user_id=owner,name='Existing real account',active=True))
        s.add(AccountCredential(user_id=owner,password_hash=encoded,enabled=True))
    prepare_accounts(engine,Settings(database_url=str(engine.url),_env_file=None))
    prepare_accounts(engine,Settings(database_url=str(engine.url),_env_file=None))
    with Session(engine) as s:
        assert len(list(s.scalars(select(Beacon).where(Beacon.owner_user_id==owner))))==1


def test_audio_matches_production_ultrasonic_vectors():
    import hashlib, json
    from pathlib import Path
    vectors=json.loads((Path(__file__).parent/'fixtures/d09-wav-sha256.json').read_text())
    for beacon_id, expected in vectors.items():
        assert hashlib.sha256(render_wav(int(beacon_id,16))).hexdigest()==expected


def test_production_wav_frequency_profile():
    import math, struct
    from app.beacon_audio import PROFILE
    assert PROFILE == {'sample_rate':48000,'zero_hz':20000,'one_hz':21000,'symbol_ms':40}
    pcm=render_wav(0x96939B)[44:]
    # First preamble bit is 1; third is 0. Sample only each steady tone plateau.
    for bit_index, expected in [(0,21000),(2,20000)]:
        start=4800+bit_index*1920+120
        samples=struct.unpack('<720h',pcm[start*2:(start+720)*2])
        def energy(hz):
            return abs(sum(value*complex(math.cos(2*math.pi*hz*i/48000),math.sin(2*math.pi*hz*i/48000)) for i,value in enumerate(samples)))
        assert max([4000,5000,20000,21000],key=energy)==expected
