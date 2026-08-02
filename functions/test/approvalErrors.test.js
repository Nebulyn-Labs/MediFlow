"use strict";

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const {
  APPROVAL_REJECTION_REASONS,
  ApprovalBusinessRuleError,
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
