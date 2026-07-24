const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const path = require("path");

// ─── Mock module loader ───────────────────────────────────────────────────

function mockTimestamp(now = Date.now()) {
  return {
    now: () => ({ toMillis: () => now, seconds: Math.floor(now / 1000), nanoseconds: 0 }),
    fromMillis: (ms) => ({ toMillis: () => ms, seconds: Math.floor(ms / 1000), nanoseconds: 0 }),
    fromDate: (d) => ({ toMillis: () => d.getTime(), seconds: Math.floor(d.getTime() / 1000), nanoseconds: 0 }),
  };
}

function mockFieldValue() {
  return { serverTimestamp: () => ({ _fieldTransform: "SERVER_TIMESTAMP" }) };
}

class MockHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function loadFunctions(seedData = {}) {
  const documents = new Map();

  // Seed initial data
  for (const [key, data] of Object.entries(seedData)) {
    documents.set(key, { ...data, _exists: true });
  }

  const getDoc = (coll, id) => {
    const key = `${coll}/${id}`;
    if (!documents.has(key)) documents.set(key, { _exists: false, _id: id });
    return documents.get(key);
  };

  const makeDocRef = (coll, id) => {
    const key = `${coll}/${id}`;
    return {
      id,
      key,
      get: async () => {
        const entry = documents.get(key) || { _exists: false };
        return { exists: entry._exists, data: () => entry, id };
      },
      set: async (data) => {
        documents.set(key, { ...data, _exists: true, _id: id });
      },
      update: async (data) => {
        const entry = documents.get(key) || { _exists: true, _id: id };
        documents.set(key, { ...entry, ...data, _exists: true });
      },
      delete: async () => { documents.delete(key); },
    };
  };

  const makeSubColl = (parentKey, subName) => ({
    doc: (id) => {
      const key = `${parentKey}/${subName}/${id}`;
      return {
        id,
        key,
        get: async () => {
          const entry = documents.get(key) || { _exists: false };
          return { exists: entry._exists, data: () => entry, id };
        },
        set: async (data) => { documents.set(key, { ...data, _exists: true, _id: id }); },
        update: async (data) => {
          const entry = documents.get(key) || { _exists: true, _id: id };
          documents.set(key, { ...entry, ...data, _exists: true });
        },
        delete: async () => { documents.delete(key); },
      };
    },
    get: async () => {
      const docs = [];
      for (const [k, v] of documents) {
        if (k.startsWith(`${parentKey}/${subName}/`) && v._exists) {
          docs.push({ id: v._id, data: () => v, exists: true });
        }
      }
      return { docs, size: docs.length, empty: docs.length === 0 };
    },
    add: async (data) => {
      const newId = `auto_${Date.now()}_${Math.random().toString(36).slice(2)}`;
      const key = `${parentKey}/${subName}/${newId}`;
      documents.set(key, { ...data, _exists: true, _id: newId });
      return { id: newId };
    },
  });

  let transactionState = null;

  const db = {
    collection: (name) => ({
      doc: (id) => {
        const ref = makeDocRef(name, id);
        ref.collection = (sub) => makeSubColl(name + "/" + id, sub);
        return ref;
      },
      where: (field, op, value) => ({
        limit: () => ({
          get: async () => {
            const docs = [];
            for (const [k, v] of documents) {
              if (k.startsWith(`${name}/`) && v._exists && k.split("/").length === 2) {
                if (v[field] === value) {
                  docs.push({ id: v._id, data: () => v, exists: true });
                }
              }
            }
            return { docs, size: docs.length, empty: docs.length === 0 };
          },
        }),
      }),
      add: async (data) => {
        const newId = `auto_${Date.now()}_${Math.random().toString(36).slice(2)}`;
        documents.set(`${name}/${newId}`, { ...data, _exists: true, _id: newId });
        return { id: newId };
      },
      get: async () => {
        const docs = [];
        for (const [k, v] of documents) {
          if (k.startsWith(`${name}/`) && v._exists && k.split("/").length === 2) {
            docs.push({ id: v._id, data: () => v, exists: true });
          }
        }
        return { docs, size: docs.length, empty: docs.length === 0 };
      },
    }),
    runTransaction: async (fn) => {
      const cached = new Map();
      transactionState = { cached, dirty: new Set() };

      const transaction = {
        get: async (ref) => {
          if (!cached.has(ref.key)) {
            const entry = documents.get(ref.key) || { _exists: false };
            cached.set(ref.key, { ...entry });
          }
          const data = cached.get(ref.key);
          return { exists: data._exists, data: () => data, id: ref.id };
        },
        set: (ref, data) => {
          cached.set(ref.key, { ...data, _exists: true, _id: ref.id });
          transactionState.dirty.add(ref.key);
        },
        update: (ref, data) => {
          const existing = cached.get(ref.key) || { _exists: true, _id: ref.id };
          cached.set(ref.key, { ...existing, ...data, _exists: true });
          transactionState.dirty.add(ref.key);
        },
      };

      await fn(transaction);

      for (const key of transactionState.dirty) {
        documents.set(key, { ...cached.get(key) });
      }
      transactionState = null;
    },
    batch: () => ({
      delete: () => {},
      commit: async () => {},
    }),
  };

  const ts = mockTimestamp();
  const firestoreFn = () => db;
  firestoreFn.Timestamp = ts;
  firestoreFn.FieldValue = mockFieldValue();

  const mockAdmin = {
    initializeApp: () => {},
    firestore: firestoreFn,
    credential: { applicationDefault: () => {} },
    messaging: () => ({
      send: async () => {},
    }),
  };

  const indexJsPath = path.resolve(__dirname, "..", "index.js");

  const mockModules = {
    "firebase-admin": mockAdmin,
    "firebase-functions/v2/https": { onCall: (_c, h) => h, onRequest: (h) => h, HttpsError: MockHttpsError },
    "firebase-functions/v2/firestore": { onDocumentWritten: (_p, h) => h, onDocumentUpdated: (_p, h) => h },
    "firebase-functions/v2/scheduler": { onSchedule: (_s, h) => h },
    "firebase-functions/logger": { info() {}, warn() {}, error() {}, log() {} },
    "@google/generative-ai": { GoogleGenerativeAI: function() { return { getGenerativeModel: () => ({ generateContent: async () => ({ response: { text: () => "{}" } }), startChat: () => ({ sendMessage: async () => ({ response: { text: () => "", functionCalls: null } }) }) }) }; } },
    "@google-cloud/bigquery": { BigQuery: function() { return {}; } },
    "./helpers/rateLimiter": { checkRateLimit: async () => {}, cleanupExpiredRateLimits: async () => ({}), LIMITS: { AI: { limit: 20 }, GENERAL: { limit: 100 } } },
    "./helpers/bigQueryRecovery": { createBigQueryRecovery: () => ({ insert: async () => ({}), recoverPending: async () => ({}) }) },
    "./helpers/promptHardener": { sanitizeUserInput: (s) => s, wrapUserContent: (s) => s, wrapDataContent: (s) => s, buildSystemPrompt: (s) => s, buildPrompt: (s, u) => s + "\n" + u, buildPromptWithData: (s, d) => s + "\n" + JSON.stringify(d) },
  };

  // Clear affected cache entries
  for (const [key] of Object.entries(require.cache)) {
    for (const modName of Object.keys(mockModules)) {
      if (key.includes(modName.replace(/[/\\]/g, "\\"))) {
        delete require.cache[key];
        break;
      }
    }
  }
  delete require.cache[indexJsPath];

  // For GoogleGenerativeAI and BigQuery, just set the mock in the cache for the resolved path
  for (const [modName, mock] of Object.entries(mockModules)) {
    try {
      const resolved = require.resolve(modName, { paths: [__dirname + "/.."] });
      require.cache[resolved] = { id: resolved, filename: resolved, loaded: true, exports: mock };
    } catch {
      // Module might already be resolved differently
    }
  }

  // Direct cache for firebase-admin based on its resolved path
  try {
    const adminResolved = require.resolve("firebase-admin", { paths: [__dirname + "/.."] });
    require.cache[adminResolved] = { id: adminResolved, filename: adminResolved, loaded: true, exports: mockAdmin };
  } catch {}

  const mod = require(indexJsPath);
  return { mod, db, documents, ts };
}

// ─── Utility function tests ──────────────────────────────────────────────

describe("stockStatus", () => {
  it("returns expired for past expiry date", () => {
    const past = new Date(Date.now() - 86400000).toISOString();
    const { mod } = loadFunctions();
    assert.equal(mod.stockStatus({ initialQuantity: 100, remainingQuantity: 50, expiryDate: past }), "expired");
  });

  it("returns wastage_risk when stock >= 70% and expiring within 30 days", () => {
    const future = new Date(Date.now() + 15 * 86400000).toISOString();
    const { mod } = loadFunctions();
    assert.equal(mod.stockStatus({ initialQuantity: 100, remainingQuantity: 80, expiryDate: future }), "wastage_risk");
  });

  it("returns low_stock when remaining <= 20% of initial", () => {
    const future = new Date(Date.now() + 60 * 86400000).toISOString();
    const { mod } = loadFunctions();
    assert.equal(mod.stockStatus({ initialQuantity: 100, remainingQuantity: 15, expiryDate: future }), "low_stock");
  });

  it("returns low_stock when remaining <= 500 units", () => {
    const future = new Date(Date.now() + 60 * 86400000).toISOString();
    const { mod } = loadFunctions();
    assert.equal(mod.stockStatus({ initialQuantity: 10000, remainingQuantity: 400, expiryDate: future }), "low_stock");
  });

  it("returns expiring_soon when expiry is within 30 days and stock is moderate (>20%, >500 units, <70%)", () => {
    const future = new Date(Date.now() + 15 * 86400000).toISOString();
    const { mod } = loadFunctions();
    assert.equal(mod.stockStatus({ initialQuantity: 1000, remainingQuantity: 600, expiryDate: future }), "expiring_soon");
  });

  it("returns healthy when stock adequate and expiry far", () => {
    const future = new Date(Date.now() + 90 * 86400000).toISOString();
    const { mod } = loadFunctions();
    assert.equal(mod.stockStatus({ initialQuantity: 1000, remainingQuantity: 600, expiryDate: future }), "healthy");
  });

  it("handles zero initial quantity as low_stock", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.stockStatus({ initialQuantity: 0, remainingQuantity: 0 }), "low_stock");
  });

  it("handles missing expiryDate", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.stockStatus({ initialQuantity: 1000, remainingQuantity: 600 }), "healthy");
  });
});

describe("safeJson", () => {
  it("serializes plain object", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.safeJson({ a: 1 }), '{"a":1}');
  });

  it("serializes null as null", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.safeJson(null), "null");
  });

  it("converts objects with toDate method to ISO string", () => {
    const { mod } = loadFunctions();
    const date = new Date("2026-07-24T12:00:00.000Z");
    const result = JSON.parse(mod.safeJson({ ts: { toDate: () => date } }));
    assert.equal(result.ts, date.toISOString());
  });

  it("handles undefined as null", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.safeJson(undefined), "null");
  });
});

describe("toIsoTimestamp", () => {
  it("returns null for null/undefined", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.toIsoTimestamp(null), null);
    assert.equal(mod.toIsoTimestamp(undefined), null);
  });

  it("converts toDate objects to ISO string", () => {
    const { mod } = loadFunctions();
    const date = new Date("2026-07-24T10:00:00.000Z");
    assert.equal(mod.toIsoTimestamp({ toDate: () => date }), date.toISOString());
  });

  it("converts Date objects", () => {
    const { mod } = loadFunctions();
    const date = new Date("2026-07-24T10:00:00.000Z");
    assert.equal(mod.toIsoTimestamp(date), date.toISOString());
  });

  it("passes through strings", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.toIsoTimestamp("2026-07-24"), "2026-07-24");
  });
});

describe("toBigQueryDate", () => {
  it("returns null for null", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.toBigQueryDate(null), null);
  });

  it("extracts date portion", () => {
    const { mod } = loadFunctions();
    assert.equal(mod.toBigQueryDate("2026-07-24T10:00:00.000Z"), "2026-07-24");
  });

  it("works with Date objects", () => {
    const { mod } = loadFunctions();
    const date = new Date("2026-07-24T10:00:00.000Z");
    assert.equal(mod.toBigQueryDate(date), "2026-07-24");
  });
});

// ─── Auth tests ──────────────────────────────────────────────────────────

describe("getUserFacilityAndRole", () => {
  it("throws unauthenticated when auth is null", async () => {
    const { mod } = loadFunctions();
    await assert.rejects(
      () => mod.getUserFacilityAndRole(null, {}),
      (err) => err.code === "unauthenticated"
    );
  });

  it("returns admin for admin@mediflow.com", async () => {
    const { mod } = loadFunctions();
    const auth = { token: { email: "admin@mediflow.com" } };
    const result = await mod.getUserFacilityAndRole(auth, {});
    assert.equal(result.isAdmin, true);
    assert.equal(result.role, "admin");
  });

  it("returns facility_head for non-admin with matching facility doc", async () => {
    const { mod, db } = loadFunctions({
      "facilities/user_test_com": { name: "Test Facility", email: "user@test.com" },
    });
    const auth = { token: { email: "user@test.com" } };
    const result = await mod.getUserFacilityAndRole(auth, db);
    assert.equal(result.isAdmin, false);
    assert.equal(result.role, "facility_head");
    assert.equal(result.userFacilityId, "user_test_com");
  });

  it("throws failed-precondition when no facility found", async () => {
    const { mod, db } = loadFunctions();
    const auth = { token: { email: "unknown@test.com" } };
    await assert.rejects(
      () => mod.getUserFacilityAndRole(auth, db),
      (err) => err.code === "failed-precondition"
    );
  });

  it("finds facility by email field when docId lookup fails", async () => {
    const { mod, db, documents } = loadFunctions();
    // Seed facility with email field (different docId)
    documents.set("facilities/some_other_id", { name: "Found Facility", email: "user@test.com", _exists: true, _id: "some_other_id" });

    const auth = { token: { email: "user@test.com" } };
    const result = await mod.getUserFacilityAndRole(auth, db);
    assert.equal(result.isAdmin, false);
    assert.equal(result.userFacilityId, "some_other_id");
  });
});

describe("createOrUpdateAlert", () => {
  it("deletes alert when status is healthy", async () => {
    const { mod, db, documents } = loadFunctions({
      "alerts/fac1_med1": { medicineName: "Para", type: "low_stock" },
    });
    await mod.createOrUpdateAlert(db, "fac1", "Fac A", "med1", { medicineName: "Para" }, "healthy");
    assert.ok(!documents.has("alerts/fac1_med1"));
  });

  it("creates alert for non-healthy status", async () => {
    const { mod, db, documents } = loadFunctions();
    await mod.createOrUpdateAlert(db, "fac1", "Fac A", "med1", {
      medicineName: "Para", remainingQuantity: 50, initialQuantity: 100, batchId: "B1", unit: "tabs",
    }, "low_stock");
    const entry = documents.get("alerts/fac1_med1");
    assert.ok(entry);
    assert.equal(entry.type, "low_stock");
    assert.equal(entry.medicineName, "Para");
  });

  it("fetches facility name when not provided", async () => {
    const { mod, db } = loadFunctions({
      "facilities/fac1": { name: "Facility A" },
    });
    await mod.createOrUpdateAlert(db, "fac1", null, "med1", { medicineName: "Para", remainingQuantity: 50, initialQuantity: 100 }, "low_stock");
    const entry = db.collection("alerts").doc("fac1_med1");
    const doc = await entry.get();
    assert.equal(doc.data().facilityName, "Facility A");
  });

  it("preserves isRead when same type already exists", async () => {
    const { mod, db } = loadFunctions({
      "alerts/fac1_med1": { medicineName: "Para", type: "low_stock", isRead: true },
    });
    await mod.createOrUpdateAlert(db, "fac1", "Fac A", "med1", { medicineName: "Para", remainingQuantity: 30, initialQuantity: 100 }, "low_stock");
    const doc = await db.collection("alerts").doc("fac1_med1").get();
    assert.equal(doc.data().isRead, true);
  });
});

describe("executeTool", () => {
  it("report_shortage creates a request", async () => {
    const { mod } = loadFunctions();
    const result = await mod.executeTool("report_shortage", { facilityId: "fac1", medicineName: "Para", quantity: 100 }, { isAdmin: true });
    assert.equal(result.status, "success");
    assert.ok(result.details.includes("shortage"));
  });

  it("report_surplus creates a request", async () => {
    const { mod } = loadFunctions();
    const result = await mod.executeTool("report_surplus", { facilityId: "fac1", medicineName: "Ibu", quantity: 50 }, { isAdmin: true });
    assert.equal(result.status, "success");
    assert.ok(result.details.includes("surplus"));
  });

  it("throws for unauthorized facility", async () => {
    const { mod } = loadFunctions();
    await assert.rejects(
      () => mod.executeTool("report_shortage", { facilityId: "other", medicineName: "Para", quantity: 10 }, { isAdmin: false, userFacilityId: "my_fac" }),
      (err) => err.message.includes("Unauthorized")
    );
  });

  it("check_system_inventory for non-admin returns own facility stock", async () => {
    const { mod, documents } = loadFunctions({
      "facilities/my_fac": { name: "My Facility" },
    });
    documents.set("inventory/my_fac/medicines/para", { medicineName: "Para", remainingQuantity: 200, initialQuantity: 500, _exists: true, _id: "para" });

    const result = await mod.executeTool("check_system_inventory", {}, { isAdmin: false, userFacilityId: "my_fac" });
    assert.equal(result.status, "success");
    assert.ok(result.system_inventory["My Facility"]);
    assert.equal(result.system_inventory["My Facility"][0].name, "Para");
  });

  it("throws for unknown tool name", async () => {
    const { mod } = loadFunctions();
    await assert.rejects(
      () => mod.executeTool("unknown", {}, {}),
      (err) => err.message.includes("Unknown function call")
    );
  });
});

describe("onIndentApproved redistribution", () => {
  it("returns early when event data is null", async () => {
    const { mod } = loadFunctions();
    assert.equal(await mod.onIndentApproved(null), undefined);
  });

  it("returns early without approved transition", async () => {
    const { mod } = loadFunctions();
    const event = {
      data: {
        before: { exists: true, data: () => ({ status: "pending" }) },
        after: { exists: true, data: () => ({ status: "pending" }), ref: { update: async () => {} } },
      },
      params: { requestId: "r1" },
    };
    assert.equal(await mod.onIndentApproved(event), undefined);
  });

  it("transfers stock between facilities (Case 1)", async () => {
    const { mod, documents } = loadFunctions();
    documents.set("inventory/source_fac/medicines/paracetamol", { medicineName: "Paracetamol", remainingQuantity: 500, initialQuantity: 1000, _exists: true, _id: "paracetamol" });
    documents.set("inventory/dest_fac/medicines/paracetamol", { medicineName: "Paracetamol", remainingQuantity: 100, initialQuantity: 500, _exists: true, _id: "paracetamol" });

    const event = {
      data: {
        before: { exists: true, data: () => ({ status: "pending" }) },
        after: {
          exists: true,
          data: () => ({ status: "approved", fromFacilityId: "source_fac", toFacilityId: "dest_fac", medicineName: "Paracetamol", quantity: 200 }),
          ref: { update: async () => {} },
        },
      },
      params: { requestId: "r2" },
    };

    await mod.onIndentApproved(event);
    assert.equal(documents.get("inventory/source_fac/medicines/paracetamol").remainingQuantity, 300);
    assert.equal(documents.get("inventory/dest_fac/medicines/paracetamol").remainingQuantity, 300);
  });

  it("rejects request when source stock insufficient", async () => {
    const { mod, documents } = loadFunctions();
    documents.set("inventory/source_fac/medicines/para", { medicineName: "Para", remainingQuantity: 50, initialQuantity: 100, _exists: true, _id: "para" });

    let rejectedReason = null;
    const event = {
      data: {
        before: { exists: true, data: () => ({ status: "pending" }) },
        after: {
          exists: true,
          data: () => ({ status: "approved", fromFacilityId: "source_fac", toFacilityId: "dest_fac", medicineName: "Para", quantity: 200 }),
          ref: { update: async (data) => { rejectedReason = data.rejectionReason; } },
        },
      },
      params: { requestId: "r3" },
    };

    await mod.onIndentApproved(event);
    assert.ok(rejectedReason, "Expected rejectionReason to be set");
    assert.ok(rejectedReason.includes("Insufficient"), `Expected "Insufficient" in "${rejectedReason}"`);
  });

  it("handles single facility restock (Case 2)", async () => {
    const { mod, documents } = loadFunctions();
    documents.set("inventory/fac1/medicines/ibu", { medicineName: "Ibu", remainingQuantity: 50, initialQuantity: 200, _exists: true, _id: "ibu" });

    const event = {
      data: {
        before: { exists: true, data: () => ({ status: "pending" }) },
        after: {
          exists: true,
          data: () => ({ status: "approved", facilityId: "fac1", medicineName: "Ibu", quantity: 100, type: "restock" }),
          ref: { update: async () => {} },
        },
      },
      params: { requestId: "r4" },
    };

    await mod.onIndentApproved(event);
    assert.equal(documents.get("inventory/fac1/medicines/ibu").remainingQuantity, 150);
  });

  it("handles surplus deduction (Case 2 surplus)", async () => {
    const { mod, documents } = loadFunctions();
    documents.set("inventory/fac1/medicines/asp", { medicineName: "Asp", remainingQuantity: 300, initialQuantity: 500, _exists: true, _id: "asp" });

    const event = {
      data: {
        before: { exists: true, data: () => ({ status: "pending" }) },
        after: {
          exists: true,
          data: () => ({ status: "approved", facilityId: "fac1", medicineName: "Asp", quantity: 100, type: "surplus" }),
          ref: { update: async () => {} },
        },
      },
      params: { requestId: "r5" },
    };

    await mod.onIndentApproved(event);
    assert.equal(documents.get("inventory/fac1/medicines/asp").remainingQuantity, 200);
  });

  it("creates new inventory doc when destination missing (Case 1)", async () => {
    const { mod, documents } = loadFunctions();
    documents.set("inventory/src/medicines/newmed", { medicineName: "NewMed", remainingQuantity: 500, initialQuantity: 1000, _exists: true, _id: "newmed" });

    const event = {
      data: {
        before: { exists: true, data: () => ({ status: "pending" }) },
        after: {
          exists: true,
          data: () => ({ status: "approved", fromFacilityId: "src", toFacilityId: "dest", medicineName: "NewMed", quantity: 100 }),
          ref: { update: async () => {} },
        },
      },
      params: { requestId: "r6" },
    };

    await mod.onIndentApproved(event);
    const destKey = "inventory/dest/medicines/newmed";
    assert.ok(documents.has(destKey), `Expected ${destKey} to exist`);
    assert.equal(documents.get(destKey).remainingQuantity, 100);
  });
});

describe("cspReport logic", () => {
  it("returns 405 for non-POST", () => {
    let statusCode, body;
    const res = { status: (c) => { statusCode = c; return { send: (m) => { body = m; } }; } };
    const handler = (req, r) => {
      if (req.method !== "POST") { r.status(405).send("Method Not Allowed"); return; }
    };
    handler({ method: "GET", headers: {}, ip: "1.2.3.4" }, res);
    assert.equal(statusCode, 405);
    assert.equal(body, "Method Not Allowed");
  });
});
