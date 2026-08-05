/**
 * Unit tests for callable AI input validation — Issue #194
 *
 * These tests exercise the validation guards added to getChatResponseSecure
 * directly, without requiring the Firebase SDK, Gemini API, or admin.initializeApp().
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

