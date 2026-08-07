"use strict";

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const {
  APPROVAL_REJECTION_REASONS,
  ApprovalBusinessRuleError,
  isTransientFirestoreError,
  handleApprovalFailure,
} = require("../helpers/approvalErrors");

function createLogger() {
  return {
    warnings: [],
    errors: [],

    warn(...args) {
      this.warnings.push(args);
    },

    error(...args) {
      this.errors.push(args);
    },
  };
}

describe("isTransientFirestoreError", () => {
  it("returns true for ABORTED (10)", () => {
    const err = Object.assign(new Error("10 ABORTED"), { code: 10 });
    assert.equal(isTransientFirestoreError(err), true);
  });

  it("returns true for UNAVAILABLE (14)", () => {
    const err = Object.assign(new Error("14 UNAVAILABLE"), { code: 14 });
    assert.equal(isTransientFirestoreError(err), true);
  });

  it("returns true for DEADLINE_EXCEEDED (4)", () => {
    const err = Object.assign(new Error("4 DEADLINE_EXCEEDED"), { code: 4 });
    assert.equal(isTransientFirestoreError(err), true);
  });

  it("returns true for RESOURCE_EXHAUSTED (8)", () => {
    const err = Object.assign(new Error("8 RESOURCE_EXHAUSTED"), { code: 8 });
    assert.equal(isTransientFirestoreError(err), true);
  });

  it("returns false for PERMISSION_DENIED (7)", () => {
    const err = Object.assign(new Error("7 PERMISSION_DENIED"), { code: 7 });
    assert.equal(isTransientFirestoreError(err), false);
  });

  it("returns false for errors with no gRPC code", () => {
    const err = new TypeError("Cannot read properties of undefined");
    assert.equal(isTransientFirestoreError(err), false);
  });

  it("returns false for generic errors with an unknown code", () => {
    const err = Object.assign(new Error("Something else"), { code: 42 });
    assert.equal(isTransientFirestoreError(err), false);
  });
});

describe("approval failure handling", () => {
  it("rejects insufficient donor stock with a curated reason", async () => {
    const updates = [];
    const requestRef = {
      async update(data) {
        updates.push(data);
      },
    };
    const logger = createLogger();

    const error = new ApprovalBusinessRuleError(
      "INSUFFICIENT_DONOR_STOCK"
    );

    await handleApprovalFailure({
      error,
      requestRef,
      logger,
      requestId: "request-314",
      operation: "Redistribution",
    });

    assert.deepEqual(updates, [
      {
        status: "rejected",
        rejectionReason:
          APPROVAL_REJECTION_REASONS.INSUFFICIENT_DONOR_STOCK,
      },
    ]);

    assert.equal(logger.warnings.length, 1);
    assert.equal(logger.errors.length, 0);
  });

  it("rethrows transient failures without changing request status", async () => {
    const updates = [];
    const requestRef = {
      async update(data) {
        updates.push(data);
      },
    };
    const logger = createLogger();

    const transientError = Object.assign(
      new Error(
        "10 ABORTED: projects/internal-project/databases/(default)"
      ),
      { code: 10 }
    );

    await assert.rejects(
      handleApprovalFailure({
        error: transientError,
        requestRef,
        logger,
        requestId: "request-314",
        operation: "Redistribution",
      }),
      (error) => error === transientError
    );

    assert.deepEqual(updates, []);
    assert.equal(logger.warnings.length, 1);
    assert.equal(logger.errors.length, 0);
  });

  it("flags non-retryable Firestore errors for manual review instead of retrying", async () => {
    const updates = [];
    const requestRef = {
      async update(data) {
        updates.push(data);
      },
    };
    const logger = createLogger();

    const permanentError = Object.assign(
      new Error("7 PERMISSION_DENIED: Missing or insufficient permissions"),
      { code: 7 }
    );

    await handleApprovalFailure({
      error: permanentError,
      requestRef,
      logger,
      requestId: "request-314",
      operation: "Redistribution",
    });

    assert.deepEqual(updates, [
      {
        status: "approval_failed",
        needsManualReview: true,
      },
    ]);

    assert.equal(logger.warnings.length, 0);
    assert.equal(logger.errors.length, 1);
  });

  it("flags errors with no gRPC code (bugs) for manual review instead of retrying", async () => {
    const updates = [];
    const requestRef = {
      async update(data) {
        updates.push(data);
      },
    };
    const logger = createLogger();

    // A plain bug — e.g. a TypeError from bad field access — has no .code
    // at all. This must NOT be treated as retryable.
    const bugError = new TypeError("Cannot read properties of undefined");

    await handleApprovalFailure({
      error: bugError,
      requestRef,
      logger,
      requestId: "request-314",
      operation: "Redistribution",
    });

    assert.deepEqual(updates, [
      {
        status: "approval_failed",
        needsManualReview: true,
      },
    ]);

    assert.equal(logger.warnings.length, 0);
    assert.equal(logger.errors.length, 1);
  });

  it("does not accept arbitrary rejection messages", () => {
    assert.throws(
      () => new ApprovalBusinessRuleError("projects/secret/document/id"),
      {
        name: "TypeError",
        message:
          "Unknown approval rejection reason: projects/secret/document/id",
      }
    );
  });
});
