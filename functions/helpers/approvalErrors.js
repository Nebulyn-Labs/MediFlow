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

  logger.error(
    `${operation} failed for request ${requestId}; retrying`,
    error
  );

  throw error;
}

module.exports = {
  APPROVAL_REJECTION_REASONS,
  ApprovalBusinessRuleError,
  handleApprovalFailure,
};
