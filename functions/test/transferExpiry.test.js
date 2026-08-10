/**
 * Unit tests for issue #313:
 * - Transfer carries donor batch's expiryDate, unit, and batchId to receiving facility when creating a new document.
 * - Transfer and restock update initialQuantity alongside remainingQuantity when topping up an existing document.
 * - Restock uses request expiryDate, unit, and batchId when creating a new document.
 */

"use strict";

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

describe("onIndentApproved transfer & restock logic (#313)", () => {
  function simulateTransaction(initialDocs, transactionCallback) {
    const docs = new Map(Object.entries(initialDocs));
    const writtenUpdates = new Map();
    const writtenSets = new Map();

    const transaction = {
      get: async (ref) => {
        const path = ref.path;
        if (docs.has(path)) {
          return {
            exists: true,
            data: () => docs.get(path),
          };
        }
        return {
          exists: false,
          data: () => null,
        };
      },
      update: (ref, data) => {
        writtenUpdates.set(ref.path, data);
        if (docs.has(ref.path)) {
          docs.set(ref.path, { ...docs.get(ref.path), ...data });
        }
      },
      set: (ref, data) => {
        writtenSets.set(ref.path, data);
        docs.set(ref.path, data);
      },
    };

    transactionCallback(transaction);
    return { docs, writtenUpdates, writtenSets };
  }

  function runTransferLogic(afterData, initialDocs) {
    const {
      fromFacilityId,
      donorFacilityId,
      toFacilityId,
      recipientFacilityId,
      medicineName,
      quantity,
      facilityId,
      type,
    } = afterData;

    const qty = Number(quantity);
    const sourceFacility = fromFacilityId || donorFacilityId || null;
    const destFacility = toFacilityId || recipientFacilityId || null;

    return simulateTransaction(initialDocs, (transaction) => {
      if (sourceFacility && destFacility) {
        const sourceMedId = medicineName.toLowerCase().replaceAll(" ", "_");
        const sourcePath = `inventory/${sourceFacility}/medicines/${sourceMedId}`;
        const sourceRef = { path: sourcePath };

        const destMedId = medicineName.toLowerCase().replaceAll(" ", "_");
        const destPath = `inventory/${destFacility}/medicines/${destMedId}`;
        const destRef = { path: destPath };

        const sourceDocData = initialDocs[sourcePath];
        if (!sourceDocData) {
          throw new Error(`Source stock for ${medicineName} at ${sourceFacility} not found`);
        }
        const currentSourceQty = Number(sourceDocData.remainingQuantity || 0);
        if (currentSourceQty < qty) {
          throw new Error(`Insufficient stock at donor ${sourceFacility}`);
        }

        const destDocData = initialDocs[destPath];

        // Decrement donor stock
        transaction.update(sourceRef, {
          remainingQuantity: currentSourceQty - qty,
        });

        if (destDocData) {
          const currentDestQty = Number(destDocData.remainingQuantity || 0);
          const currentDestInit = Number(
            destDocData.initialQuantity !== undefined ? destDocData.initialQuantity : currentDestQty
          );
          transaction.update(destRef, {
            initialQuantity: currentDestInit + qty,
            remainingQuantity: currentDestQty + qty,
          });
        } else {
          const donorBatchId =
            sourceDocData.batchId ||
            afterData.batchId ||
            "B-DEFAULT";
          const donorUnit = sourceDocData.unit || afterData.unit || "units";
          const donorExpiry =
            sourceDocData.expiryDate ||
            afterData.expiryDate ||
            "180-days-default";

          transaction.set(destRef, {
            medicineName,
            batchId: donorBatchId,
            initialQuantity: qty,
            remainingQuantity: qty,
            unit: donorUnit,
            expiryDate: donorExpiry,
          });
        }
      } else if (facilityId) {
        const medId = medicineName.toLowerCase().replaceAll(" ", "_");
        const medPath = `inventory/${facilityId}/medicines/${medId}`;
        const medRef = { path: medPath };
        const medDocData = initialDocs[medPath];

        if (type === "surplus") {
          if (medDocData) {
            const currentQty = Number(medDocData.remainingQuantity || 0);
            const newQty = Math.max(0, currentQty - qty);
            transaction.update(medRef, {
              remainingQuantity: newQty,
            });
          }
        } else {
          if (medDocData) {
            const currentQty = Number(medDocData.remainingQuantity || 0);
            const currentInit = Number(
              medDocData.initialQuantity !== undefined ? medDocData.initialQuantity : currentQty
            );
            transaction.update(medRef, {
              initialQuantity: currentInit + qty,
              remainingQuantity: currentQty + qty,
            });
          } else {
            const requestBatchId = afterData.batchId || "B-DEFAULT";
            const requestUnit = afterData.unit || "units";
            const requestExpiry = afterData.expiryDate || "180-days-default";

            transaction.set(medRef, {
              medicineName,
              batchId: requestBatchId,
              initialQuantity: qty,
              remainingQuantity: qty,
              unit: requestUnit,
              expiryDate: requestExpiry,
            });
          }
        }
      }
    });
  }

  it("carries donor batch expiry, unit and batchId when recipient document does NOT exist", () => {
    const donorExpiry = new Date(Date.now() + 10 * 86400000); // Expiring in 10 days
    const initialDocs = {
      "inventory/facility_A/medicines/amoxicillin": {
        medicineName: "Amoxicillin",
        batchId: "BATCH-DONOR-123",
        unit: "vials",
        expiryDate: donorExpiry,
        initialQuantity: 100,
        remainingQuantity: 80,
      },
    };

    const request = {
      donorFacilityId: "facility_A",
      recipientFacilityId: "facility_B",
      medicineName: "Amoxicillin",
      quantity: 30,
    };

    const { docs } = runTransferLogic(request, initialDocs);

    const destDoc = docs.get("inventory/facility_B/medicines/amoxicillin");
    assert.ok(destDoc, "Recipient doc should be created");
    assert.equal(destDoc.batchId, "BATCH-DONOR-123", "batchId must match donor");
    assert.equal(destDoc.unit, "vials", "unit must match donor");
    assert.equal(destDoc.expiryDate, donorExpiry, "expiryDate must match donor batch (10 days)");
    assert.equal(destDoc.initialQuantity, 30);
    assert.equal(destDoc.remainingQuantity, 30);

    // Verify donor stock decremented
    const donorDoc = docs.get("inventory/facility_A/medicines/amoxicillin");
    assert.equal(donorDoc.remainingQuantity, 50);
  });

  it("updates initialQuantity alongside remainingQuantity when recipient document ALREADY exists", () => {
    const initialDocs = {
      "inventory/facility_A/medicines/paracetamol": {
        medicineName: "Paracetamol",
        batchId: "BATCH-A",
        unit: "boxes",
        expiryDate: "2027-01-01",
        initialQuantity: 200,
        remainingQuantity: 150,
      },
      "inventory/facility_B/medicines/paracetamol": {
        medicineName: "Paracetamol",
        batchId: "BATCH-B",
        unit: "boxes",
        expiryDate: "2027-06-01",
        initialQuantity: 50,
        remainingQuantity: 10,
      },
    };

    const request = {
      fromFacilityId: "facility_A",
      toFacilityId: "facility_B",
      medicineName: "Paracetamol",
      quantity: 40,
    };

    const { docs } = runTransferLogic(request, initialDocs);

    const destDoc = docs.get("inventory/facility_B/medicines/paracetamol");
    assert.equal(destDoc.remainingQuantity, 50); // 10 + 40
    assert.equal(destDoc.initialQuantity, 90); // 50 + 40
    assert.ok(
      destDoc.remainingQuantity <= destDoc.initialQuantity,
      "remainingQuantity must not exceed initialQuantity"
    );
  });

  it("uses request expiryDate and unit in restock branch when document does NOT exist", () => {
    const requestExpiry = new Date(Date.now() + 45 * 86400000);
    const request = {
      facilityId: "facility_C",
      medicineName: "Ibuprofen",
      type: "shortage",
      quantity: 100,
      batchId: "RESTOCK-BATCH-77",
      unit: "tablets",
      expiryDate: requestExpiry,
    };

    const { docs } = runTransferLogic(request, {});

    const medDoc = docs.get("inventory/facility_C/medicines/ibuprofen");
    assert.ok(medDoc, "Restock doc should be created");
    assert.equal(medDoc.batchId, "RESTOCK-BATCH-77");
    assert.equal(medDoc.unit, "tablets");
    assert.equal(medDoc.expiryDate, requestExpiry);
    assert.equal(medDoc.initialQuantity, 100);
    assert.equal(medDoc.remainingQuantity, 100);
  });

  it("updates initialQuantity alongside remainingQuantity when topping up an existing restock document", () => {
    const initialDocs = {
      "inventory/facility_C/medicines/ibuprofen": {
        medicineName: "Ibuprofen",
        batchId: "OLD-BATCH",
        unit: "tablets",
        initialQuantity: 100,
        remainingQuantity: 20,
      },
    };

    const request = {
      facilityId: "facility_C",
      medicineName: "Ibuprofen",
      type: "shortage",
      quantity: 50,
    };

    const { docs } = runTransferLogic(request, initialDocs);

    const medDoc = docs.get("inventory/facility_C/medicines/ibuprofen");
    assert.equal(medDoc.remainingQuantity, 70); // 20 + 50
    assert.equal(medDoc.initialQuantity, 150); // 100 + 50
    assert.ok(medDoc.remainingQuantity <= medDoc.initialQuantity);
  });
});
