const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const {
  isValidFcmToken,
  registerFcmToken,
  unregisterFcmToken,
} = require("../helpers/fcmTokens");

function createFirestore() {
  const users = new Map();
  return {
    users,
    collection: (name) => {
      assert.equal(name, "users");
      return {
        doc: (uid) => ({
          set: async (value, options) => {
            const existing = users.get(uid) || {};
            users.set(uid, options?.merge ? { ...existing, ...value } : value);
          },
        }),
      };
    },
  };
}

describe("isValidFcmToken", () => {
  it("accepts a reasonable token string", () => {
    assert.equal(isValidFcmToken("a".repeat(140)), true);
  });

  it("rejects empty, non-string, and oversized values", () => {
    assert.equal(isValidFcmToken(""), false);
    assert.equal(isValidFcmToken("   "), false);
    assert.equal(isValidFcmToken(null), false);
    assert.equal(isValidFcmToken(undefined), false);
    assert.equal(isValidFcmToken(12345), false);
    assert.equal(isValidFcmToken("a".repeat(5000)), false);
  });
});

describe("registerFcmToken (#208)", () => {
  it("writes the token and an update timestamp onto the user doc", async () => {
    const firestore = createFirestore();
    const sentinelTimestamp = { sentinel: "server-timestamp" };

    await registerFcmToken(firestore, "user-1", "token-abc", {
      serverTimestamp: () => sentinelTimestamp,
    });

    assert.deepEqual(firestore.users.get("user-1"), {
      fcmToken: "token-abc",
      fcmTokenUpdatedAt: sentinelTimestamp,
    });
  });

  it("merges onto an existing user doc without clobbering other fields", async () => {
    const firestore = createFirestore();
    firestore.users.set("user-1", { role: "facility_head", facilityId: "f1" });

    await registerFcmToken(firestore, "user-1", "token-abc", {
      serverTimestamp: () => "ts",
    });

    assert.deepEqual(firestore.users.get("user-1"), {
      role: "facility_head",
      facilityId: "f1",
      fcmToken: "token-abc",
      fcmTokenUpdatedAt: "ts",
    });
  });

  it("rejects an invalid token before writing anything", async () => {
    const firestore = createFirestore();

    await assert.rejects(
      registerFcmToken(firestore, "user-1", "", { serverTimestamp: () => "ts" }),
      (error) => error.code === "invalid-argument"
    );
    assert.equal(firestore.users.has("user-1"), false);
  });
});

describe("unregisterFcmToken", () => {
  it("clears the token field using the supplied delete sentinel", async () => {
    const firestore = createFirestore();
    firestore.users.set("user-1", { fcmToken: "stale-token", role: "facility_head" });
    const deleteValue = { sentinel: "field-delete" };

    await unregisterFcmToken(firestore, "user-1", {
      serverTimestamp: () => "ts",
      deleteValue,
    });

    assert.deepEqual(firestore.users.get("user-1"), {
      role: "facility_head",
      fcmToken: deleteValue,
      fcmTokenUpdatedAt: "ts",
    });
  });
});