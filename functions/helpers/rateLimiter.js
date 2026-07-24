const admin = require("firebase-admin");
const { HttpsError } = require("firebase-functions/v2/https");

const LIMITS = {
  AI: {
    limit: 20,
    windowMs: 60 * 60 * 1000, // 1 hour
  },
  GENERAL: {
    limit: 100,
    windowMs: 60 * 60 * 1000, // 1 hour
  },
};

const COLLECTION = "rate_limits";
const CLEANUP_BATCH_SIZE = 100;

function computeTtl(windowStartMs, windowMs) {
  return admin.firestore.Timestamp.fromMillis(
    windowStartMs + windowMs + 60 * 60 * 1000
  );
}

async function checkRateLimit(uid, endpoint, config) {
  const db = admin.firestore();

  const docRef = db
    .collection(COLLECTION)
    .doc(`${uid}_${endpoint}`);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(docRef);

    const now = admin.firestore.Timestamp.now();
    const nowMillis = now.toMillis();
    const ttl = computeTtl(nowMillis, config.windowMs);

    if (!snapshot.exists) {
      transaction.set(docRef, {
        count: 1,
        windowStart: now,
        ttl,
      });
      return;
    }

    const data = snapshot.data();
    const windowStartMillis = data.windowStart.toMillis();
    if (nowMillis - windowStartMillis >= config.windowMs) {
      transaction.set(docRef, {
        count: 1,
        windowStart: now,
        ttl,
      });
      return;
    }

    if (data.count >= config.limit) {
      throw new HttpsError(
        "resource-exhausted",
        "Rate limit exceeded. Please try again later."
      );
    }

    transaction.update(docRef, {
      count: data.count + 1,
    });
  });
}

async function cleanupExpiredRateLimits() {
  const db = admin.firestore();

  const now = admin.firestore.Timestamp.now();
  const expiredQuery = db
    .collection(COLLECTION)
    .where("ttl", "<", now)
    .limit(CLEANUP_BATCH_SIZE);

  let totalDeleted = 0;
  let hasMore = true;

  while (hasMore) {
    const snapshot = await expiredQuery.get();

    if (snapshot.empty) {
      hasMore = false;
      break;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    totalDeleted += snapshot.size;
    hasMore = snapshot.size === CLEANUP_BATCH_SIZE;
  }

  return { deletedCount: totalDeleted };
}

module.exports = {
  checkRateLimit,
  cleanupExpiredRateLimits,
  LIMITS,
  COLLECTION,
  CLEANUP_BATCH_SIZE,
};
