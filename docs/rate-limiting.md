# Rate Limiting

This document describes the rate limiting implementation for MediFlow Cloud Functions.

## Overview

Rate limiting protects Cloud Functions endpoints from excessive usage by tracking
request counts per user and endpoint within a time window.

## Implementation

### Rate Limiting Logic

Rate limiting is implemented in `functions/helpers/rateLimiter.js`:

- **AI Endpoints**: 20 requests per hour
- **General Endpoints**: 100 requests per hour

Documents are stored in the `rate_limits` Firestore collection with the following structure:

```json
{
  "count": 5,
  "windowStart": "2026-08-03T10:00:00.000Z"
}
```

- **Document ID**: `${uid}_${endpoint}`
- **count**: Number of requests in the current window
- **windowStart**: Timestamp when the current window began

### Automatic Cleanup

Expired rate-limit documents are automatically deleted by the scheduled Cloud Function
`cleanupExpiredRateLimitRecords`, which runs every 6 hours.

This approach is used instead of Firestore TTL because:
- Firestore TTL requires a timestamp field named `expireAt` or `ttl` in the document
- The rate limiting implementation uses `windowStart` for tracking request windows
- A scheduled cleanup function provides fine-grained control and logging

### Collection Rules

The `rate_limits` collection has restricted write access:

```javascript
match /rate_limits/{rateLimitId} {
  allow read: if isAdmin();
  allow write: if false;
}
```

Only Cloud Functions can create, update, or delete rate-limit documents.
