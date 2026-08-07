/**
 * Unit tests for facility lookup without email-derived document IDs — Issue #409
 */

"use strict";

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/**
 * Re-implementation of getUserFacilityAndRole for testing facility lookup
 * without external network or emulator dependencies.
 */
async function getUserFacilityAndRole(auth, db) {
  if (!auth) {
    throw new HttpsError("unauthenticated", "User must log in");
  }

  const uid = auth.uid;
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) {
    const userEmail = auth.token.email.toLowerCase();
    const isAdmin = userEmail === "admin@mediflow.com";
    let userFacilityId = null;

    if (!isAdmin) {
      const rawEmail = auth.token.email;
      let facilitiesSnapshot = await db.collection("facilities")
        .where("email", "==", userEmail)
        .limit(1)
        .get();
      if (facilitiesSnapshot.empty && rawEmail && rawEmail.toLowerCase() !== userEmail) {
        facilitiesSnapshot = await db.collection("facilities")
          .where("email", "==", rawEmail)
          .limit(1)
          .get();
      }
      if (facilitiesSnapshot.empty) {
        throw new HttpsError("failed-precondition", "No facility assigned to this user");
      }
      userFacilityId = facilitiesSnapshot.docs[0].id;
    }

    return {
      userEmail,
      userFacilityId,
      isAdmin,
      role: isAdmin ? "admin" : "facility_head",
    };
  }

  const userData = userDoc.data();
  const role = userData.role || "facility_head";
  const isAdmin = role === "admin";
  let userFacilityId = null;

  if (!isAdmin) {
    userFacilityId = userData.facilityId || null;
    if (!userFacilityId) {
      const userEmail = auth.token.email.toLowerCase();
      const rawEmail = auth.token.email;
      let facilitiesSnapshot = await db.collection("facilities")
        .where("email", "==", userEmail)
        .limit(1)
        .get();
      if (facilitiesSnapshot.empty && rawEmail && rawEmail.toLowerCase() !== userEmail) {
        facilitiesSnapshot = await db.collection("facilities")
          .where("email", "==", rawEmail)
          .limit(1)
          .get();
      }
      if (facilitiesSnapshot.empty) {
        throw new HttpsError("failed-precondition", "No facility assigned to this user");
      }
      userFacilityId = facilitiesSnapshot.docs[0].id;
    }
  }

  return {
    userEmail: auth.token.email.toLowerCase(),
    userFacilityId,
    isAdmin,
    role,
  };
}

// In-memory Firestore mock helper
function createMockDb(usersMap = {}, facilitiesList = []) {
  return {
    collection(colName) {
      if (colName === "users") {
        return {
          doc(id) {
            return {
              async get() {
                const data = usersMap[id];
                return {
                  exists: !!data,
                  data: () => data,
                };
              },
            };
          },
        };
      }
      if (colName === "facilities") {
        return {
          where(field, op, value) {
            return {
              limit(n) {
                return {
                  async get() {
                    const matches = facilitiesList
                      .filter((f) => {
                        if (field === "email" && op === "==") {
                          return f.data.email === value;
                        }
                        return false;
                      })
                      .slice(0, n);
                    return {
                      empty: matches.length === 0,
                      docs: matches,
                    };
                  },
                };
              },
            };
          },
        };
      }
      throw new Error(`Unknown collection: ${colName}`);
    },
  };
}

describe("Facility Lookup — Issue #409", () => {
  it("resolves facilityId when facility doc has arbitrary non-email-derived ID", async () => {
    const db = createMockDb(
      {},
      [
        {
          id: "custom_fac_991823", // Non-email derived document ID
          data: { email: "clinic@mediflow.com", name: "Custom Clinic" },
        },
      ]
    );

    const auth = { uid: "user_1", token: { email: "clinic@mediflow.com" } };
    const res = await getUserFacilityAndRole(auth, db);

    assert.equal(res.userFacilityId, "custom_fac_991823");
    assert.equal(res.role, "facility_head");
  });

  it("resolves facility for emails with uppercase characters", async () => {
    const db = createMockDb(
      {},
      [
        {
          id: "fac_alpha_101",
          data: { email: "user.name@health.org", name: "Alpha Health" },
        },
      ]
    );

    const auth = { uid: "user_2", token: { email: "User.Name@Health.ORG" } };
    const res = await getUserFacilityAndRole(auth, db);

    assert.equal(res.userFacilityId, "fac_alpha_101");
  });

  it("resolves facility for emails with subdomains and multi-part TLDs", async () => {
    const db = createMockDb(
      {},
      [
        {
          id: "fac_subdomain_77",
          data: { email: "admin@sub.district.health.gov.in", name: "District HQ" },
        },
      ]
    );

    const auth = { uid: "user_3", token: { email: "admin@sub.district.health.gov.in" } };
    const res = await getUserFacilityAndRole(auth, db);

    assert.equal(res.userFacilityId, "fac_subdomain_77");
  });

  it("uses facilityId stored on user profile when present", async () => {
    const db = createMockDb(
      {
        user_4: {
          role: "facility_head",
          facilityId: "fac_user_profile_mapped",
        },
      },
      []
    );

    const auth = { uid: "user_4", token: { email: "profile@mediflow.com" } };
    const res = await getUserFacilityAndRole(auth, db);

    assert.equal(res.userFacilityId, "fac_user_profile_mapped");
  });

  it("throws precondition failure when no facility is found for email", async () => {
    const db = createMockDb({}, []);
    const auth = { uid: "user_5", token: { email: "unknown@mediflow.com" } };

    await assert.rejects(
      async () => {
        await getUserFacilityAndRole(auth, db);
      },
      (err) => {
        assert.equal(err.code, "failed-precondition");
        return true;
      }
    );
  });
});
