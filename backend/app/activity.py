"""Bounded UTC reporting, with counts aggregated in SQL rather than raw event export."""
from datetime import datetime, timedelta, timezone
from sqlalchemy import case, func, select
from .models import ActivityEvent

KINDS = ('detections', 'views', 'saves', 'actions')
PERIODS = ('today', '7d', '30d', '90d', '12m')

def month_start(value, delta=0):
    year, month = divmod(value.year * 12 + value.month - 1 + delta, 12)
    return datetime(year, month + 1, 1, tzinfo=timezone.utc)

def window(period, now):
    day = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if period == '12m':
        start = month_start(now, -11)
        edges = [month_start(start, i) for i in range(13)]
        previous_start = month_start(start, -12)
        # Compare equally elapsed portions, not a partial month against a full month.
        previous_end = month_start(now, -12) + (now - month_start(now))
        return start, now, previous_start, min(previous_end, start), edges, 'monthly'
    days = {'today': 1, '7d': 7, '30d': 30, '90d': 90}[period]
    start = day - timedelta(days=days-1)
    step = timedelta(hours=1) if period == 'today' else timedelta(days=7 if period == '90d' else 1)
    edges = [start]
    end = day + timedelta(days=1)
    while edges[-1] < end:
        edges.append(min(edges[-1] + step, end))
    return start, now, start-timedelta(days=days), now-timedelta(days=days), edges, 'hourly' if period == 'today' else ('weekly' if period == '90d' else 'daily')

def summarize(session, merchant_id, period, now):
    start, end, prev_start, prev_end, edges, bucket = window(period, now)
    # One grouped query; maximum 30 buckets plus the comparison group.
    group = case(*[( (ActivityEvent.occurred_at >= a) & (ActivityEvent.occurred_at < b), i)
                    for i, (a,b) in enumerate(zip(edges, edges[1:]))], else_=-1)
    ranges = ((ActivityEvent.occurred_at >= start) & (ActivityEvent.occurred_at < end)) | ((ActivityEvent.occurred_at >= prev_start) & (ActivityEvent.occurred_at < prev_end))
    rows = session.execute(select(group, ActivityEvent.kind, func.count()).where(
        ActivityEvent.merchant_id == merchant_id, ranges).group_by(group, ActivityEvent.kind))
    totals = dict.fromkeys(KINDS, 0)
    previous = dict.fromkeys(KINDS, 0)
    buckets = [{'start':a.isoformat(), **dict.fromkeys(KINDS, 0)} for a in edges[:-1]]
    for index, kind, count in rows:
        if index == -1:
            previous[kind] += count
        else:
            buckets[index][kind] += count
            totals[kind] += count
    total, previous_total = sum(totals.values()), sum(previous.values())
    return {'period':period, 'timezone':'UTC', 'bucket':bucket, 'start':start.isoformat(), 'end':end.isoformat(),
            'totals':totals, 'total':total, 'previous_total':previous_total,
            'change_percent':round((total-previous_total)*100/previous_total, 1) if previous_total else None,
            'buckets':buckets, 'sample':False,
            'tracking_note':'Recorded events only. Consumer event collection is not connected yet.'}
