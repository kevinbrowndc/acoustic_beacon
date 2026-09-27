from datetime import datetime, timedelta, timezone
import pytest
from sqlalchemy import select
from app.activity import summarize, window
from app.models import ActivityEvent, Merchant, User
from test_dashboard import dashboard, login

NOW = datetime(2026, 9, 27, 12, tzinfo=timezone.utc)

def add(session, merchant, kind, at, key):
    session.add(ActivityEvent(merchant_id=merchant, kind=kind, occurred_at=at, event_key=key))

def test_isolation_ranges_buckets_and_comparison(session):
    user=User(email='other-analytics@example.invalid',role='merchant');session.add(user);session.flush()
    session.add(Merchant(owner_user_id=user.id,name='Other merchant',active=True));session.flush()
    merchants = list(session.scalars(select(Merchant)))
    own, other = merchants[0].id, merchants[1].id
    add(session, own, 'detections', NOW-timedelta(hours=2), 'a')
    add(session, own, 'views', NOW-timedelta(hours=2), 'b')
    add(session, own, 'saves', NOW-timedelta(hours=1), 'c')
    add(session, own, 'actions', NOW-timedelta(days=1,seconds=1), 'd')
    add(session, other, 'views', NOW-timedelta(hours=2), 'e')
    add(session, own, 'views', NOW, 'future-boundary')
    add(session, own, 'views', NOW-timedelta(days=3), 'outside')
    session.commit()
    result = summarize(session, own, 'today', NOW)
    assert result['total'] == 3
    assert result['previous_total'] == 1
    assert result['change_percent'] == 200
    assert result['buckets'][10]['detections'] == 1
    assert result['buckets'][10]['views'] == 1
    assert result['buckets'][11]['saves'] == 1
    assert result['totals']['actions'] == 0

@pytest.mark.parametrize('period,count,bucket', [('today',24,'hourly'),('7d',7,'daily'),('30d',30,'daily'),('90d',13,'weekly'),('12m',12,'monthly')])
def test_all_periods_empty_and_aggregation(session, period, count, bucket):
    merchant = session.scalar(select(Merchant.id))
    empty = summarize(session, merchant, period, NOW)
    assert empty['total'] == 0 and empty['change_percent'] is None
    assert len(empty['buckets']) == count and empty['bucket'] == bucket
    start, _, prev_start, _, edges, _ = window(period, NOW)
    add(session,merchant,'detections',start,'first')
    add(session,merchant,'actions',NOW-timedelta(seconds=1),'last')
    add(session,merchant,'saves',prev_start,'previous')
    session.commit()
    result = summarize(session,merchant,period,NOW)
    assert result['total'] == 2 and result['previous_total'] == 1
    assert sum(b['detections'] for b in result['buckets']) == 1
    assert sum(b['actions'] for b in result['buckets']) == 1

def test_endpoint_requires_identity_and_rejects_manager(dashboard):
    assert dashboard.get('/api/v1/dashboard/activity').status_code == 401
    login(dashboard)
    result=dashboard.get('/api/v1/dashboard/activity?period=7d')
    assert result.status_code == 200 and result.json()['total'] == 0
    assert result.headers['cache-control'] == 'no-store'
    assert dashboard.get('/api/v1/dashboard/activity?period=all').status_code == 422
    login(dashboard,'manager')
    assert dashboard.get('/api/v1/dashboard/activity').status_code == 403


def test_authenticated_endpoint_excludes_other_merchants(dashboard, session):
    workspace=login(dashboard)
    own=session.scalar(select(Merchant).where(Merchant.name==workspace['account']['business']))
    other=session.scalar(select(Merchant).where(Merchant.id!=own.id))
    now=datetime.now(timezone.utc)-timedelta(seconds=1)
    add(session,own.id,'views',now,'own-view')
    add(session,other.id,'views',now,'other-view')
    session.commit()
    response=dashboard.get('/api/v1/dashboard/activity?period=7d')
    assert response.status_code==200
    assert response.json()['totals']['views']==1
    assert response.json()['total']==1
