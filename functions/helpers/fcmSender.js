/**
 * Wraps admin.messaging().send() so a stale/uninstalled-app token can't
 * throw and abort a low-stock sweep or real-time trigger (#208 follow-on
 * safety: once fcmToken actually gets populated by registerFcmToken(), this
 * send path starts firing for real and needs to tolerate tokens going bad).
 *
 * When FCM reports the token itself is no longer valid, the stale token is
 * also cleared from whichever user doc(s) reference it, so the next sweep
 * doesn't keep retrying a dead token forever.
 */

const STALE_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

function isStaleTokenError(error) {
  const code = error?.code || error?.errorInfo?.code;
  return STALE_TOKEN_CODES.has(code);
}

function createFcmSender({ messaging, firestore, logger }) {
  return async function sendNotification(token, notification) {
    try {
      await messaging.send({ token, notification });
    } catch (error) {
      if (logger) {
        logger.warn("FCM send failed", {
          code: error?.code || error?.errorInfo?.code || null,
          stale: isStaleTokenError(error),
          error: error?.message || String(error),
        });
      }
      if (isStaleTokenError(error)) {
        const staleQuery = await firestore
          .collection("users")
          .where("fcmToken", "==", token)
          .get();
        await Promise.all(
          staleQuery.docs.map((doc) => doc.ref.update({ fcmToken: null }))
        );
      }
    }
  };
}

module.exports = { createFcmSender, isStaleTokenError };