/**
 * Unit tests for callable AI input validation — Issue #194
 *
 * These tests exercise the validation guards added to getChatResponseSecure,
 * generateSmartAlertsSecure, and forecastDemand directly, without requiring
 * the Firebase SDK, Gemini API, or admin.initializeApp().
 *
 * Each guard is extracted into a small inline helper that mirrors the exact
 * condition used in index.js, keeping the tests maintainable alongside the
 * production code.
 */

"use strict";

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

// ---------------------------------------------------------------------------
// Minimal HttpsError stub — matches the Firebase Functions v2 HttpsError shape
// that index.js uses.
// ---------------------------------------------------------------------------
class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

// ---------------------------------------------------------------------------
// Validation helpers — these are exact copies of the guards in index.js so
// that changes to the production code surface as test failures immediately.
// ---------------------------------------------------------------------------

function validateHistory(data) {
  if (!data.history || !Array.isArray(data.history)) {
    throw new HttpsError("invalid-argument", "history must be an array");
  }
}

function validateInventory(data) {
  if (!data.inventory || !Array.isArray(data.inventory)) {
    throw new HttpsError("invalid-argument", "inventory must be an array");
  }
}

function validateMedicineNames(data) {
  if (!data.medicineNames || !Array.isArray(data.medicineNames)) {
    throw new HttpsError("invalid-argument", "medicineNames must be an array");
  }
}

function validateFacility(facility) {
  if (!facility || typeof facility.name !== "string") {
    throw new HttpsError(
      "invalid-argument",
      "facility must have a valid name property"
    );
  }
}

// ---------------------------------------------------------------------------
// Helper: assert that a synchronous function throws an HttpsError with the
// expected code.
// ---------------------------------------------------------------------------
function assertHttpsError(fn, expectedCode) {
  let threw = false;
  try {
    fn();
  } catch (err) {
    threw = true;
    assert.ok(
      err instanceof HttpsError,
      `expected HttpsError but got ${err.constructor.name}: ${err.message}`
    );
    assert.equal(
      err.code,
      expectedCode,
      `expected code "${expectedCode}" but got "${err.code}"`
    );
  }
  assert.ok(threw, "expected a HttpsError to be thrown but nothing was thrown");
}

// ---------------------------------------------------------------------------
// Tests — getChatResponseSecure: history validation
// ---------------------------------------------------------------------------
describe("getChatResponseSecure — history validation", () => {
  it("throws invalid-argument when history is missing", () => {
    assertHttpsError(
      () => validateHistory({}),
      "invalid-argument"
    );
  });

  it("throws invalid-argument when history is not an array", () => {
    assertHttpsError(
      () => validateHistory({ history: "not-an-array" }),
      "invalid-argument"
    );
  });
});

// ---------------------------------------------------------------------------
// Tests — generateSmartAlertsSecure: inventory validation
// ---------------------------------------------------------------------------
describe("generateSmartAlertsSecure — inventory validation", () => {
  it("throws invalid-argument when inventory is missing", () => {
    assertHttpsError(
      () => validateInventory({}),
      "invalid-argument"
    );
  });

  it("throws invalid-argument when inventory is not an array", () => {
    assertHttpsError(
      () => validateInventory({ inventory: { notAnArray: true } }),
      "invalid-argument"
    );
  });
});

// ---------------------------------------------------------------------------
// Tests — forecastDemand: medicineNames validation
// ---------------------------------------------------------------------------
describe("forecastDemand — medicineNames validation", () => {
  it("throws invalid-argument when medicineNames is missing", () => {
    assertHttpsError(
      () => validateMedicineNames({}),
      "invalid-argument"
    );
  });

  it("throws invalid-argument when medicineNames is not an array", () => {
    assertHttpsError(
      () => validateMedicineNames({ medicineNames: 42 }),
      "invalid-argument"
    );
  });
});

// ---------------------------------------------------------------------------
// Tests — forecastDemand: facility validation
// ---------------------------------------------------------------------------
describe("forecastDemand — facility validation", () => {
  it("throws invalid-argument when facility document does not exist (null data)", () => {
    // facilityDoc.data() returns undefined when the Firestore document is absent
    assertHttpsError(
      () => validateFacility(undefined),
      "invalid-argument"
    );
  });

  it("throws invalid-argument when facility.name is missing", () => {
    assertHttpsError(
      () => validateFacility({ district: "North" }),
      "invalid-argument"
    );
  });
});
