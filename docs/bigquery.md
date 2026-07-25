# BigQuery Integration

This document describes the BigQuery integration used to archive MediFlow
operational data for reporting and analytics.

## Overview

Cloud Functions mirror Firestore changes to the `mediflow_analytics` BigQuery
dataset by default. The following tables are created automatically:

- `ai_decisions`
- `transfer_requests`
- `inventory_snapshots`
- `usage_analytics`
- `audit_events`

Set `BQ_DATASET` and `BQ_LOCATION` in the Functions environment to override the
default dataset name or its `US` location.

## Insertion recovery

Each insertion uses a stable insert ID and follows this recovery flow:

1. Successful inserts return immediately, as before.
2. Transient failures such as timeouts, rate limiting, and HTTP 5xx responses
   are retried three times with exponential backoff.
3. An exhausted or non-transient failure is saved in the Firestore collection
   `bigquery_insert_failures` instead of being discarded.
4. `retryFailedBigQueryInsertions` runs every five minutes and replays due
   failures. It retries recoverable failures up to ten scheduled runs.

The recovery worker uses a transaction-based claim. A claim older than ten
minutes is considered abandoned and can be reclaimed after an interrupted
worker run.

## Monitoring and investigation

Cloud Logging emits structured entries for immediate retries, queued failures,
and every scheduled recovery summary. Alert on the message
`BigQuery insertion queued for recovery` to detect new failures quickly.

The `bigquery_insert_failures` collection is server-only under the current
Firestore rules. Investigate it from the Firebase console or an authorized
backend. Important fields include:

| Field | Meaning |
| --- | --- |
| `tableName` | Destination BigQuery table |
| `source` | Cloud Function path that produced the rows |
| `rows` | Payload retained for replay |
| `status` | `pending`, `retrying`, `recovered`, or `dead` |
| `insertionAttempts` | Attempts made before the fallback write |
| `recoveryAttempts` | Scheduled recovery runs performed |
| `lastError` | Sanitized error name, message, code, and reasons |
| `firstFailedAt` / `lastFailedAt` | Failure timestamps |
| `nextRetryAt` | Next scheduled replay time |

`dead` documents need manual investigation, usually for schema or payload
errors. After correcting the root cause, an operator can set the document back
to `pending`, reset `recoveryAttempts`, and set `nextRetryAt` to the current
time to request another replay. Keep `rows` and `tableName` unchanged.

Deploy both Functions and Firestore indexes when releasing this integration:

```bash
firebase deploy --only functions,firestore:indexes
```

## Local verification

The recovery behavior is covered by isolated unit tests and does not require
live Firebase or BigQuery credentials:

```bash
cd functions
npm ci
npm test
npm run lint
```
