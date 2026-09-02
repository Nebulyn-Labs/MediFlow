/**
 * Registers/clears the FCM token on a user's Firestore doc.
 *
 * Nothing in the app previously wrote users/{uid}.fcmToken, so the
 * `if (user.fcmToken && sendNotification)` check in helpers/lowStock.js
 * silently skipped sending on every run - the alert logic and FCM send call
 * were both fine, but the token that would let them fire never existed
 * (#208). This is the missing write.
 */

const MAX_TOKEN_LENGTH = 4096;

function isValidFcmToken(token) {
  return typeof token === "string" &&
    token.trim().length > 0 &&
    token.length <= MAX_TOKEN_LENGTH;
}

async function registerFcmToken(firestore, uid, token, { serverTimestamp }) {
  if (!isValidFcmToken(token)) {
    const error = new Error("A valid FCM token is required");
    error.code = "invalid-argument";
    throw error;
  }

  await firestore.collection("users").doc(uid).set(
    {
      fcmToken: token,
      fcmTokenUpdatedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

async function unregisterFcmToken(firestore, uid, { serverTimestamp, deleteValue }) {
  await firestore.collection("users").doc(uid).set(
    {
      fcmToken: deleteValue,
      fcmTokenUpdatedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

module.exports = { isValidFcmToken, registerFcmToken, unregisterFcmToken };