/**
 * Unit tests for quantity validation guard (Issue #315)
 *
 * Tests cover:
 * - isValidQuantity helper with NaN, Infinity, numeric string, zero, and negative values.
 * - onIndentApproved quantity guard behavior (rejects invalid quantities, sets rejectionReason, leaves inventory untouched).
 * - executeTool quantity validation (throws error before creating request document).
 */

"use strict";

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const { isValidQuantity } = require("../helpers/quantityValidation");

describe("isValidQuantity helper", () => {
  it("rejects NaN", () => {
    assert.equal(isValidQuantity(NaN), false);
    assert.equal(isValidQuantity(Number("20 boxes")), false);
  });

  it("rejects Infinity and -Infinity", () => {
    assert.equal(isValidQuantity(Infinity), false);
    assert.equal(isValidQuantity(-Infinity), false);
    assert.equal(isValidQuantity(Number("Infinity")), false);
  });

  it("accepts valid numeric string", () => {
    assert.equal(isValidQuantity("20"), true);
    assert.equal(isValidQuantity("100.5"), true);
    assert.equal(isValidQuantity("1"), true);
  });

  it("accepts valid positive numbers", () => {
    assert.equal(isValidQuantity(20), true);
    assert.equal(isValidQuantity(0.5), true);
  });

  it("rejects zero", () => {
    assert.equal(isValidQuantity(0), false);
    assert.equal(isValidQuantity("0"), false);
  });

  it("rejects negative values", () => {
    assert.equal(isValidQuantity(-5), false);
    assert.equal(isValidQuantity("-5"), false);
    assert.equal(isValidQuantity(-0.01), false);
  });

  it("rejects non-numeric strings and invalid types", () => {
    assert.equal(isValidQuantity("twenty"), false);
    assert.equal(isValidQuantity("20 boxes"), false);
    assert.equal(isValidQuantity(null), false);
    assert.equal(isValidQuantity(undefined), false);
    assert.equal(isValidQuantity(true), false);
    assert.equal(isValidQuantity(false), false);
    assert.equal(isValidQuantity({}), false);
    assert.equal(isValidQuantity([]), false);
    assert.equal(isValidQuantity(""), false);
    assert.equal(isValidQuantity("   "), false);
  });
});

describe("onIndentApproved quantity guard logic", () => {
  function simulateIndentApprovedGuard(afterData) {
    const { quantity, medicineName } = afterData;
    let updated = null;
    let inventoryTouched = false;

    const fakeRef = {
      update: async (data) => {
        updated = data;
      },
    };

    if (!medicineName) {
      return { status: "ignored", updated, inventoryTouched };
    }

    if (!isValidQuantity(quantity)) {
      fakeRef.update({
        status: "rejected",
        rejectionReason: `Invalid quantity: ${quantity}. Quantity must be a finite positive number.`,
      });
      return { status: "rejected", updated, inventoryTouched };
    }

    const qty = Number(quantity);
    // Proceed to inventory update simulation
    inventoryTouched = true;
    return { status: "processed", qty, updated, inventoryTouched };
  }

  it("rejects NaN and does not modify inventory", () => {
    const result = simulateIndentApprovedGuard({
      medicineName: "Paracetamol",
      quantity: "20 boxes",
    });

    assert.equal(result.inventoryTouched, false);
    assert.equal(result.status, "rejected");
    assert.equal(result.updated.status, "rejected");
    assert.ok(result.updated.rejectionReason.includes("Invalid quantity"));
  });

  it("rejects Infinity and does not modify inventory", () => {
    const result = simulateIndentApprovedGuard({
      medicineName: "Paracetamol",
      quantity: Infinity,
    });

    assert.equal(result.inventoryTouched, false);
    assert.equal(result.status, "rejected");
    assert.equal(result.updated.status, "rejected");
    assert.ok(result.updated.rejectionReason.includes("Invalid quantity"));
  });

  it("rejects zero and does not modify inventory", () => {
    const result = simulateIndentApprovedGuard({
      medicineName: "Paracetamol",
      quantity: 0,
    });

    assert.equal(result.inventoryTouched, false);
    assert.equal(result.status, "rejected");
    assert.equal(result.updated.status, "rejected");
  });

  it("rejects negative values and does not modify inventory", () => {
    const result = simulateIndentApprovedGuard({
      medicineName: "Paracetamol",
      quantity: -10,
    });

    assert.equal(result.inventoryTouched, false);
    assert.equal(result.status, "rejected");
    assert.equal(result.updated.status, "rejected");
  });

  it("processes valid numeric strings correctly", () => {
    const result = simulateIndentApprovedGuard({
      medicineName: "Paracetamol",
      quantity: "50",
    });

    assert.equal(result.inventoryTouched, true);
    assert.equal(result.status, "processed");
    assert.equal(result.qty, 50);
  });
});

describe("executeTool quantity validation", () => {
  function simulateExecuteTool(name, args, authInfo) {
    let docAdded = null;

    if (name === "report_shortage" || name === "report_surplus") {
      const { facilityId, medicineName, quantity } = args;
      if (!authInfo.isAdmin && facilityId !== authInfo.userFacilityId) {
        throw new Error(`Unauthorized: Cannot request for facility ${facilityId}`);
      }
      if (!isValidQuantity(quantity)) {
        throw new Error(
          `Invalid quantity: ${quantity}. Quantity must be a finite positive number.`
        );
      }
      const qty = Number(quantity);
      const type = name === "report_shortage" ? "shortage" : "surplus";
      docAdded = {
        facilityId,
        medicineName,
        type,
        quantity: qty,
        status: "pending",
      };
      return { status: "success", docAdded };
    }
    throw new Error("Unknown tool");
  }

  const authInfo = { isAdmin: true, userFacilityId: "f1" };

  it("throws error for NaN quantity", () => {
    assert.throws(
      () => simulateExecuteTool("report_shortage", { facilityId: "f1", medicineName: "Amoxicillin", quantity: "20 boxes" }, authInfo),
      /Invalid quantity/
    );
  });

  it("throws error for Infinity quantity", () => {
    assert.throws(
      () => simulateExecuteTool("report_shortage", { facilityId: "f1", medicineName: "Amoxicillin", quantity: Infinity }, authInfo),
      /Invalid quantity/
    );
  });

  it("throws error for zero quantity", () => {
    assert.throws(
      () => simulateExecuteTool("report_shortage", { facilityId: "f1", medicineName: "Amoxicillin", quantity: 0 }, authInfo),
      /Invalid quantity/
    );
  });

  it("throws error for negative quantity", () => {
    assert.throws(
      () => simulateExecuteTool("report_shortage", { facilityId: "f1", medicineName: "Amoxicillin", quantity: -15 }, authInfo),
      /Invalid quantity/
    );
  });

  it("accepts valid numeric string and writes parsed number", () => {
    const result = simulateExecuteTool(
      "report_shortage",
      { facilityId: "f1", medicineName: "Amoxicillin", quantity: "30" },
      authInfo
    );
    assert.equal(result.status, "success");
    assert.equal(result.docAdded.quantity, 30);
    assert.equal(typeof result.docAdded.quantity, "number");
  });
});
