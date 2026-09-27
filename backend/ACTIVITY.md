# Customer Activity

The production and demo dashboards share `dashboard/src/activity.js`. The demo alone uses deterministic fictional hourly activity (two years of history for twelve-month comparisons). It never fetches the production analytics endpoint. Public demo CSP still prohibits all network connections.

## Backend contract

`GET /api/v1/dashboard/activity?period=today|7d|30d|90d|12m`

Uses the existing `actor` session guard and derives the merchant from that actor, never from a supplied merchant ID. Managers cannot access merchant activity. Response is no-store. Aggregation happens in SQL with bounded bucket output, not raw customer events.

Response includes `period`, `timezone` (UTC), `bucket`, `start`, `end`, `totals` (`detections`, `views`, `saves`, `actions`), `total`, `previous_total`, nullable `change_percent`, and zero-filled `buckets`. Counts are events, not unique customers. A zero previous total gives no percentage rather than infinity or fictional growth.

Today uses hourly buckets; 7/30 calendar days including today use daily buckets; 90 days uses seven-day buckets anchored at the range start (final bucket can be shorter); twelve months including the current month uses monthly buckets. All ranges are half-open and end at the current time. The preceding equivalent period compares equally elapsed time; future portions of the current bucket are not counted.

## Storage and rollout

Migration `0002` adds only `activity_events`, a merchant foreign key, event-kind constraint, unique source `event_key` and merchant/time index. Upgrade preserves every existing table and row. Downgrade drops the new analytics table and its data only.

In the existing Northflank container Shell, after deploying this revision:

```
python -m alembic upgrade head
```

This is the repository's existing explicit migration path. Runtime startup does not migrate. Existing public lookup readiness accepts both 0001 and 0002 during rollout; analytics requires 0002. No credentials should be pasted or printed.

## Honest current limitations

Production identity integration remains fail-closed, unchanged: the deployed merchant endpoints return 503 until the separate identity integration exists. Authenticated local merchant sessions exercise the complete analytics endpoint.

There was no existing customer event model or collector. This change adds the storage and read/aggregation architecture, not a public unauthenticated event-write endpoint. Trusted consumer-event ingestion must later write the validated merchant association, one of the four kinds, UTC occurrence time and a globally unique event key (to prevent duplicate ingestion). No customer identity is stored. Do not count offer lookups or dashboard visits as acoustic detections, and do not invent redemptions. Until real event collection is connected, production totals are legitimately zero. D09 and Flutter remain untouched.

## Deployment branches

Demo and production dashboard are both built from master by the existing backend Dockerfile. Main hosts only the public marketing homepage, whose existing Demo link is unchanged. No main change or duplicate demo deployment is required.
