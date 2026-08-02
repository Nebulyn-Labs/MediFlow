"use strict";

const APPROVAL_REJECTION_REASONS = Object.freeze({
  SOURCE_STOCK_NOT_FOUND:
    "The requested medicine is unavailable at the donor facility.",
  INSUFFICIENT_DONOR_STOCK:
    "The donor facility does not have enough stock to fulfill this request.",
});

class ApprovalBusinessRuleError extends Error {
  constructor(reasonCode) {
    const rejectionReason = APPROVAL_REJECTION_REASONS[reasonCode];
    if (!rejectionReason) {
      throw new TypeError(`Unknown approval rejection reason: ${reasonCode}`);
    }
    super(rejectionReason);
    this.name = "ApprovalBusinessRuleError";
    this.reasonCode = reasonCode;
  }
}

// gRPC status codes that represent genuinely transient Firestore/infra
// conditions worth Cloud Functions' automatic retry. Anything NOT in this
// set (PERMISSION_DENIED, NOT_FOUND, INVALID_ARGUMENT, or a plain bug like
// a TypeError with no .code at all) is a permanent failure — retrying it
// just strands the request in "approved" limbo with no error surfaced.
const RETRYABLE_FIRESTORE_CODES = new Set([
  4,  // DEADLINE_EXCEEDED
  8,  // RESOURCE_EXHAUSTED
  10, // ABORTED (transaction/contention conflict)
  14, // UNAVAILABLE
]);

function isTransientFirestoreError(error) {
  return (
    typeof error?.code === "number" && RETRYABLE_FIRESTORE_CODES.has(error.code)
  );
}

async function handleApprovalFailure({
  error,
  requestRef,
  logger,
  requestId,
  operation,
}) {
  if (error instanceof ApprovalBusinessRuleError) {
    const rejectionReason =
      APPROVAL_REJECTION_REASONS[error.reasonCode];

    logger.warn(
      `${operation} rejected for request ${requestId}: ${error.reasonCode}`
    );

    await requestRef.update({
      status: "rejected",
      rejectionReason,
    });

    return;
  }

  if (isTransientFirestoreError(error)) {
    logger.warn(
      `${operation} hit a transient Firestore error for request ${requestId} (code ${error.code}); retrying`,
      error
    );
    throw error; // only this path should hit Cloud Functions' retry:true
  }

  logger.error(
    `${operation} failed for request ${requestId} with a non-retryable error; ` +
    `flagging for manual review instead of retrying indefinitely`,
    error
  );
  await requestRef.update({
    status: "approval_failed",
    needsManualReview: true,
  });
}

module.exports = {
  APPROVAL_REJECTION_REASONS,
  ApprovalBusinessRuleError,
  isTransientFirestoreError,
  handleApprovalFailure,
};
