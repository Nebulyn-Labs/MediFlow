const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const { createFcmSender, isStaleTokenError } = require("../helpers/fcmSender");

function createLogger() {
  const warnings = [];
  return { warnings, warn: (...args) => warnings.push(args) };
}

function createFirestore(initialUsers = {}) {
  const users = new Map(Object.entries(initialUsers));
  return {
    users,
    collection: (name) => {
      assert.equal(name, "users");
      return {
        where: (field, op, value) => {
          assert.equal(field, "fcmToken");
          assert.equal(op, "==");
          const docs = [...users.entries()]
            .filter(([, data]) => data.fcmToken === value)
            .map(([id, data]) => ({
              id,
              ref: {
                update: async (patch) => users.set(id, { ...users.get(id), ...patch }),
              },
              data: () => data,
            }));
          return { get: async () => ({ docs }) };
        },
      };
    },
  };
}

describe("isStaleTokenError", () => {
  it("recognizes the specific FCM error codes that mean the token is dead", () => {
    assert.equal(isStaleTokenError({ code: "messaging/registration-token-not-registered" }), true);
    assert.equal(isStaleTokenError({ code: "messaging/invalid-registration-token" }), true);
    assert.equal(isStaleTokenError({ code: "messaging/invalid-argument" }), true);
  });

  it("does not treat unrelated errors as a stale token", () => {
    assert.equal(isStaleTokenError({ code: "messaging/internal-error" }), false);
    assert.equal(isStaleTokenError({ code: 503 }), false);
    assert.equal(isStaleTokenError(new Error("boom")), false);
  });
});

describe("createFcmSender (#208)", () => {
  it("sends via messaging.send with the given token and notification", async () => {
    const calls = [];
    const sender = createFcmSender({
      messaging: { send: async (payload) => calls.push(payload) },
      firestore: createFirestore(),
      logger: createLogger(),
    });

    await sender("token-1", { title: "Low Stock Alert", body: "Paracetamol is low" });

    assert.equal(calls.length, 1);
    assert.deepEqual(calls[0], {
      token: "token-1",
      notification: { title: "Low Stock Alert", body: "Paracetamol is low" },
    });
  });

  it("swallows a stale-token error instead of throwing, and clears the token from Firestore", async () => {
    const firestore = createFirestore({
      "user-1": { fcmToken: "dead-token", role: "facility_head" },
    });
    const logger = createLogger();
    const sender = createFcmSender({
      messaging: {
        send: async () => {
          const error = new Error("Requested entity was not found.");
          error.code = "messaging/registration-token-not-registered";
          throw error;
        },
      },
      firestore,
      logger,
    });

    await sender("dead-token", { title: "t", body: "b" });

    assert.equal(firestore.users.get("user-1").fcmToken, null);
    assert.equal(logger.warnings.length, 1);
  });

  it("swallows a non-stale error too, without touching Firestore (never aborts the caller's sweep)", async () => {
    const firestore = createFirestore({
      "user-1": { fcmToken: "token-1" },
    });
    const sender = createFcmSender({
      messaging: {
        send: async () => {
          const error = new Error("temporarily unavailable");
          error.code = "messaging/internal-error";
          throw error;
        },
      },
      firestore,
      logger: createLogger(),
    });

    await sender("token-1", { title: "t", body: "b" });

    assert.equal(firestore.users.get("user-1").fcmToken, "token-1");
  });
});