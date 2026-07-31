/**
 * Low-stock detection and alert-sync logic.
 *
 * Pulled out of index.js so it can be exercised directly in tests with a
 * fake Firestore/messaging layer, the same way helpers/bigQueryRecovery.js is
 * tested (see functions/test/lowStock.test.js).
 *
 * `createLowStockService` is a small dependency-injection factory:
 * `serverTimestamp` is passed in instead of importing firebase-admin here
 * directly, so tests can supply a plain sentinel value instead of a real
 * Firestore server-timestamp marker.
 */

function toIsoTimestamp(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return value;
}

const thresholds = require("./inventory_thresholds.json");

function stockStatus(data) {
  const initial = Number(data.initialQuantity || 0);
  const remaining = Number(data.remainingQuantity || 0);
  const pct = initial > 0 ? remaining / initial : 0;
  const expiry = toIsoTimestamp(data.expiryDate);
  const daysLeft = expiry
    ? Math.ceil((new Date(expiry).getTime() - Date.now()) / 86400000)
    : null;

  if (daysLeft !== null && daysLeft < 0) return "expired";
  if (pct >= 0.7 && daysLeft !== null && daysLeft <= 30) return "wastage_risk";
  if (pct <= thresholds.lowStockPercentage || remaining <= thresholds.lowStockAbsolute) return "low_stock";
  if (daysLeft !== null && daysLeft <= 30) return "expiring_soon";
  return "healthy";
}

function createLowStockService({ serverTimestamp }) {
  /**
   * Creates, updates, or deletes the alert doc for a single medicine so
   * that `alerts` always reflects the medicine's current status.
   * Returns { status, existed } where `existed` is whether an alert for
   * this medicine was already present *before* this call - callers (e.g.
   * the scheduled sweep) use that to avoid re-notifying about a low_stock
   * alert that isn't new.
   */
  async function syncAlertForMedicine(db, facilityId, medicineId, data, facilityName, sendNotification) {
    const alertId = `${facilityId}_${medicineId}`;
    const alertRef = db.collection("alerts").doc(alertId);

    if (!data) {
      const alertDoc = await alertRef.get();
      const existed = alertDoc.exists;
      if (existed) {
        await alertRef.delete();
      }
      return { status: "deleted", existed };
    }

    const status = stockStatus(data);
    const alertDoc = await alertRef.get();
    const existed = alertDoc.exists;

    if (status === "healthy") {
      if (existed) {
        await alertRef.delete();
      }
      return { status, existed };
    }

    let resolvedFacilityName = facilityName;
    if (!resolvedFacilityName) {
      const facilityDoc = await db.collection("facilities").doc(facilityId).get();
      resolvedFacilityName = facilityDoc.exists ? facilityDoc.data().name || "" : "";
    }

    const alertData = {
      facilityId,
      facilityName: resolvedFacilityName,
      stockId: medicineId,
      medicineName: data.medicineName || "",
      qtyRemaining: Number(data.remainingQuantity || 0),
      initialQuantity: Number(data.initialQuantity || 0),
      batchId: data.batchId || "",
      unit: data.unit || "units",
      expiryDate: data.expiryDate,
      type: status,
      isRead: existed ? alertDoc.data()?.isRead ?? false : false,
    };
    if (!existed) {
      alertData.createdAt = serverTimestamp();
    }

    await alertRef.set(alertData, { merge: true });

    if (status === "low_stock" && !existed) {
      // Write to real-time notification feed subcollection
      const notifRef = db
        .collection("notifications")
        .doc(facilityId)
        .collection("items")
        .doc();
      
      await notifRef.set({
        facilityId: facilityId,
        type: "low_stock",
        message: `${data.medicineName} is below reorder level (${data.remainingQuantity} left).`,
        isRead: false,
        createdAt: serverTimestamp(),
      });

      const userQuery = await db
        .collection("users")
        .where("facilityId", "==", facilityId)
        .where("role", "==", "facility_head")
        .limit(1)
        .get();

      if (!userQuery.empty) {
        const user = userQuery.docs[0].data();
        if (user.fcmToken && sendNotification) {
          await sendNotification(user.fcmToken, {
            title: "Low Stock Alert",
            body: `${data.medicineName} is below reorder level (${data.remainingQuantity} left).`,
          });
        }
      }
    }

    return { status, existed };
  }

  /**
   * Sweeps every facility's current inventory (inventory/{facilityId}/medicines)
   * syncing alerts and firing an FCM notification for medicines that just
   * became low_stock. Intended to back the nightly `checkLowStock` schedule;
   * real-time updates are handled separately via syncAlertForMedicine being
   * called from the inventory-write trigger.
   */
  async function runLowStockSweep({ db, sendNotification }) {
    const facilities = await db.collection("facilities").get();

    for (const facilityDoc of facilities.docs) {
      const facilityName = facilityDoc.data().name || "";
      const medicinesSnapshot = await db
        .collection("inventory")
        .doc(facilityDoc.id)
        .collection("medicines")
        .get();

      for (const medDoc of medicinesSnapshot.docs) {
        const data = medDoc.data();
        const { status, existed } = await syncAlertForMedicine(
          db,
          facilityDoc.id,
          medDoc.id,
          data,
          facilityName,
          sendNotification
        );
      }
    }

    return null;
  }

  return { stockStatus, syncAlertForMedicine, runLowStockSweep };
}

module.exports = { createLowStockService, stockStatus, toIsoTimestamp };
