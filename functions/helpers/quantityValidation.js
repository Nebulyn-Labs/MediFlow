"use strict";

/**
 * Validates whether a given quantity input is a finite positive number.
 *
 * Handles numbers, numeric strings (e.g. "20", "20.5"), and rejects:
 * - NaN / non-numeric strings (e.g. "20 boxes")
 * - Infinity / -Infinity
 * - Zero (0, "0")
 * - Negative numbers (-5, "-5")
 * - null, undefined, booleans, arrays, objects
 *
 * @param {*} quantity
 * @returns {boolean} True if quantity is a finite positive number, false otherwise.
 */
function isValidQuantity(quantity) {
  if (quantity === null || quantity === undefined || typeof quantity === "boolean") {
    return false;
  }
  if (typeof quantity !== "number" && typeof quantity !== "string") {
    return false;
  }
  if (typeof quantity === "string" && quantity.trim() === "") {
    return false;
  }
  const qty = Number(quantity);
  return Number.isFinite(qty) && qty > 0;
}

module.exports = {
  isValidQuantity,
};
