const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const { createLowStockService, stockStatus } = require("../helpers/lowStock");

const SERVER_TIMESTAMP = Symbol("SERVER_TIMESTAMP");

/**
 * Minimal in-memory Firestore fake supporting the handful of operations
 * lowStock.js relies on: nested collection/doc paths, simple equality
 * `.where()` filters, `.limit()`, and basic doc get/set/delete.
 * Modeled after functions/test/bigQueryRecovery.test.js's fake, generalized
 * to handle the facilities/inventory/alerts/users collections this module
 * touches.
 */
function createFakeFirestore(seed = {}) {
  // path (e.g. "facilities/f1" or "inventory/f1/medicines/m1") -> data
  const docs = new Map();
  for (const [collectionPath, entries] of Object.entries(seed)) {
    for (const [id, data] of Object.entries(entries)) {
      docs.set(`${collectionPath}/${id}`, { ...data });
    }
  }

  function docRef(path, id) {
    const fullPath = `${path}/${id}`;
    return {
      id,
      get: async () => ({
        id,
        exists: docs.has(fullPath),
        data: () => docs.get(fullPath),
      }),
      set: async (value, options = {}) => {
        const existing = options.merge ? docs.get(fullPath) || {} : {};
        docs.set(fullPath, { ...existing, ...value });
      },
      delete: async () => {
        docs.delete(fullPath);
      },
      collection: (subName) => collectionRef(`${fullPath}/${subName}`),
    };
  }

  function collectionRef(path) {
    let filters = [];
    let limitCount = null;

    const query = {
      doc: (id) => docRef(path, id),
      where: (field, op, value) => {
        assert.equal(op, "==", "fake firestore only supports == filters");
        filters = [...filters, { field, value }];
        return { ...query, where: query.where };
      },
      limit: (count) => {
        limitCount = count;
        return query;
      },
      get: async () => {
        const prefix = `${path}/`;
        let matches = [...docs.entries()]
          .filter(([key]) => key.startsWith(prefix) && key.slice(prefix.length).indexOf("/") === -1)
          .map(([key, data]) => ({
            id: key.slice(prefix.length),
            data: () => data,
          }));

        for (const { field, value } of filters) {
          matches = matches.filter((d) => d.data()[field] === value);
        }
        if (limitCount !== null) {
          matches = matches.slice(0, limitCount);
        }

        return { docs: matches, empty: matches.length === 0, size: matches.length };
      },
    };

    return query;
  }

  const firestore = {
    collection: (name) => collectionRef(name),
  };

  return { firestore, docs };
}

function medicine({ initialQuantity = 100, remainingQuantity = 100, medicineName = "Paracetamol" } = {}) {
  return {
    medicineName,
    batchId: "batch-1",
    initialQuantity,
    remainingQuantity,
    unit: "units",
    expiryDate: null,
  };
}

describe("stockStatus", () => {
  it("flags low_stock when remaining percentage drops to 20% or below", () => {
    const data = medicine({ initialQuantity: 100, remainingQuantity: 20 });
    assert.equal(stockStatus(data), "low_stock");
  });

  it("flags low_stock via the absolute floor even with a high percentage remaining", () => {
    const data = medicine({ initialQuantity: 100000, remainingQuantity: 500 });
    assert.equal(stockStatus(data), "low_stock");
  });

  it("reports healthy when well above both thresholds", () => {
    const data = medicine({ initialQuantity: 10000, remainingQuantity: 8000 });
    assert.equal(stockStatus(data), "healthy");
  });
});

describe("createLowStockService().syncAlertForMedicine", () => {
  it("creates a new low_stock alert with existed=false", async () => {
    const { firestore } = createFakeFirestore({
      facilities: { f1: { name: "Rural PHC" } },
    });
    const service = createLowStockService({ serverTimestamp: () => SERVER_TIMESTAMP });

    const result = await service.syncAlertForMedicine(
      firestore,
      "f1",
      "m1",
      medicine({ remainingQuantity: 10 })
    );

    assert.equal(result.status, "low_stock");
    assert.equal(result.existed, false);

    const alertDoc = await firestore.collection("alerts").doc("f1_m1").get();
    assert.equal(alertDoc.exists, true);
    assert.equal(alertDoc.data().facilityName, "Rural PHC");
    assert.equal(alertDoc.data().isRead, false);
    assert.equal(alertDoc.data().createdAt, SERVER_TIMESTAMP);
  });

  it("reports existed=true and preserves isRead on a repeat low_stock sync", async () => {
    const { firestore } = createFakeFirestore({
      facilities: { f1: { name: "Rural PHC" } },
      alerts: {
        f1_m1: {
          type: "low_stock",
          isRead: true,
          createdAt: "already-set",
        },
      },
    });
    const service = createLowStockService({ serverTimestamp: () => SERVER_TIMESTAMP });

    const result = await service.syncAlertForMedicine(
      firestore,
      "f1",
      "m1",
      medicine({ remainingQuantity: 10 })
    );

    assert.equal(result.existed, true);
    const alertDoc = await firestore.collection("alerts").doc("f1_m1").get();
    assert.equal(alertDoc.data().isRead, true, "should not reset isRead on an existing alert");
    assert.equal(alertDoc.data().createdAt, "already-set", "should not overwrite createdAt");
  });

  it("deletes the alert once the medicine is healthy again", async () => {
    const { firestore } = createFakeFirestore({
      alerts: { f1_m1: { type: "low_stock", isRead: false } },
    });
    const service = createLowStockService({ serverTimestamp: () => SERVER_TIMESTAMP });

    const result = await service.syncAlertForMedicine(
      firestore,
      "f1",
      "m1",
      medicine({ initialQuantity: 10000, remainingQuantity: 9000 })
    );

    assert.equal(result.status, "healthy");
    const alertDoc = await firestore.collection("alerts").doc("f1_m1").get();
    assert.equal(alertDoc.exists, false);
  });
});

describe("createLowStockService().runLowStockSweep", () => {
  it("regression: sweeps the current inventory/{facilityId}/medicines schema without crashing", async () => {
    // This is the exact scenario that used to crash: checkLowStock previously
    // queried the legacy facilities/{facilityId}/stocks path with an invalid
    // field-to-field where() clause, and later (after an unrelated refactor)
    // called a helper function that no longer existed. Both bugs meant the
    // scheduled sweep threw and never completed.
    const { firestore } = createFakeFirestore({
      facilities: { f1: { name: "Rural PHC" } },
      "inventory/f1/medicines": {
        m1: medicine({ remainingQuantity: 10 }),
      },
      users: {
        u1: { facilityId: "f1", role: "facility_head", fcmToken: "token-123" },
      },
    });
    const service = createLowStockService({ serverTimestamp: () => SERVER_TIMESTAMP });
    const sentNotifications = [];

    await assert.doesNotReject(() =>
      service.runLowStockSweep({
        db: firestore,
        sendNotification: async (token, notification) => {
          sentNotifications.push({ token, notification });
        },
      })
    );

    const alertDoc = await firestore.collection("alerts").doc("f1_m1").get();
    assert.equal(alertDoc.exists, true);
    assert.equal(alertDoc.data().type, "low_stock");
    assert.equal(sentNotifications.length, 1);
    assert.equal(sentNotifications[0].token, "token-123");
  });

  it("does not re-notify for a low_stock alert that already existed", async () => {
    const { firestore } = createFakeFirestore({
      facilities: { f1: { name: "Rural PHC" } },
      "inventory/f1/medicines": {
        m1: medicine({ remainingQuantity: 10 }),
      },
      alerts: {
        f1_m1: { type: "low_stock", isRead: false },
      },
      users: {
        u1: { facilityId: "f1", role: "facility_head", fcmToken: "token-123" },
      },
    });
    const service = createLowStockService({ serverTimestamp: () => SERVER_TIMESTAMP });
    const sentNotifications = [];

    await service.runLowStockSweep({
      db: firestore,
      sendNotification: async (token, notification) => {
        sentNotifications.push({ token, notification });
      },
    });

    assert.equal(sentNotifications.length, 0);
  });

  it("covers multiple facilities independently", async () => {
    const { firestore } = createFakeFirestore({
      facilities: {
        f1: { name: "Rural PHC" },
        f2: { name: "Urban Hospital" },
      },
      "inventory/f1/medicines": {
        m1: medicine({ remainingQuantity: 10 }),
      },
      "inventory/f2/medicines": {
        m2: medicine({ initialQuantity: 10000, remainingQuantity: 9000 }),
      },
    });
    const service = createLowStockService({ serverTimestamp: () => SERVER_TIMESTAMP });

    await service.runLowStockSweep({ db: firestore, sendNotification: async () => {} });

    const lowAlert = await firestore.collection("alerts").doc("f1_m1").get();
    const healthyAlert = await firestore.collection("alerts").doc("f2_m2").get();
    assert.equal(lowAlert.exists, true);
    assert.equal(healthyAlert.exists, false);
  });
});
