const admin = require("firebase-admin");
const { HttpsError } = require("firebase-functions/v2/https");

const LIMITS = {
  AI: {
    limit: 20,
    windowMs: 60 * 60 * 1000,
  },
  GENERAL: {
    limit: 100,
    windowMs: 60 * 60 * 1000,
  },
  PASSWORD_RESET_IP: {
    limit: 20,
    windowMs: 60 * 60 * 1000, // 1 hour
  },
  PASSWORD_RESET_EMAIL: {
    limit: 5,
    windowMs: 60 * 60 * 1000, // 1 hour
  },
};

async function checkRateLimit(uid, endpoint, config) {
  const db = admin.firestore();

  const docRef = db
    .collection("rate_limits")
    .doc(`${uid}_${endpoint}`);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(docRef);

    const now = admin.firestore.Timestamp.now();
    const nowMillis = now.toMillis();

    if (!snapshot.exists) {
      transaction.set(docRef, {
        count: 1,
        windowStart: now,
      });
      return;
    }

    const data = snapshot.data();
    const windowStartMillis = data.windowStart.toMillis();
    if (nowMillis - windowStartMillis >= config.windowMs) {
      transaction.set(docRef, {
        count: 1,
        windowStart: now,
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

async function cleanupExpiredRateLimitRecords() {
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const nowMillis = now.toMillis();

  let deletedCount = 0;

  const snapshot = await db.collection("rate_limits").get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const windowStartMillis = data.windowStart.toMillis();
    const windowMs = 60 * 60 * 1000;

    if (nowMillis - windowStartMillis >= windowMs) {
      await doc.ref.delete();
      deletedCount++;
    }
  }

  return deletedCount;
}

module.exports = {
  checkRateLimit,
  cleanupExpiredRateLimitRecords,
  LIMITS,
};
