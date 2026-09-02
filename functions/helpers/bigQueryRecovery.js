const crypto = require("node:crypto");

const FAILURE_COLLECTION = "bigquery_insert_failures";
const RETRYABLE_STATUS_CODES = new Set([408, 429, 500, 502, 503, 504]);
const RETRYABLE_ERROR_CODES = new Set([
  "ECONNRESET",
  "ECONNREFUSED",
  "EAI_AGAIN",
  "ETIMEDOUT",
]);
const RETRYABLE_REASONS = new Set([
  "backendError",
  "internalError",
  "rateLimitExceeded",
  "tableUnavailable",
]);
const CLAIM_TIMEOUT_MS = 10 * 60 * 1000;

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function serializeError(error) {
  const nestedErrors = Array.isArray(error?.errors) ? error.errors : [];
  return {
    name: error?.name || "Error",
    message: error?.message || String(error),
    code: error?.code || null,
    reasons: nestedErrors
      .map((entry) => entry?.reason || entry?.errors?.[0]?.reason)
      .filter(Boolean),
  };
}

function isRetryableError(error) {
  const numericCode = Number(error?.code);
  if (RETRYABLE_STATUS_CODES.has(numericCode)) return true;
  if (RETRYABLE_ERROR_CODES.has(error?.code)) return true;

  const details = serializeError(error);
  return details.reasons.some((reason) => RETRYABLE_REASONS.has(reason));
}

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

function insertionId(tableName, row, index, dedupeKey) {
  // When a caller supplies a stable dedupeKey (e.g. a Firestore CloudEvent's
  // event.id), base the insertId on that instead of the row's own content.
  // Content-based hashing breaks deduplication whenever a row embeds a
  // wall-clock value (captured_at, etc.), since retries/redeliveries of the
  // same logical event then produce a different hash - and therefore a
  // different insertId - defeating BigQuery's insertId-based dedup.
  const basis = dedupeKey != null
    ? `dedupe:${dedupeKey}`
    : `content:${index}:${canonicalJson(row)}`;
  return crypto
    .createHash("sha256")
    .update(`${tableName}:${basis}`)
    .digest("hex");
}

function retryDelay(baseDelayMs, attempt) {
  return baseDelayMs * (2 ** Math.max(0, attempt - 1));
}

function toDate(value) {
  if (value && typeof value.toDate === "function") return value.toDate();
  return value instanceof Date ? value : new Date(value);
}

function createBigQueryRecovery({
  bigquery,
  firestore,
  logger,
  tables,
  datasetName,
  location,
  maxAttempts = 3,
  maxRecoveryAttempts = 10,
  baseDelayMs = 250,
  resolvedRetentionMs = 7 * 24 * 60 * 60 * 1000,
  wait = sleep,
  now = () => new Date(),
}) {
  const tableReady = new Map();

  async function ensureTable(tableName) {
    if (!tables[tableName]) {
      throw new Error(`Unknown BigQuery table: ${tableName}`);
    }
    if (tableReady.has(tableName)) return tableReady.get(tableName);

    const promise = (async () => {
      const dataset = bigquery.dataset(datasetName);
      const [datasetExists] = await dataset.exists();
      if (!datasetExists) {
        await bigquery.createDataset(datasetName, { location });
      }

      const table = dataset.table(tableName);
      const [tableExists] = await table.exists();
      if (!tableExists) {
        await dataset.createTable(tableName, {
          schema: { fields: tables[tableName].schema },
          timePartitioning: { type: "DAY" },
        });
      }
      return table;
    })();

    tableReady.set(tableName, promise);
    try {
      return await promise;
    } catch (error) {
      tableReady.delete(tableName);
      throw error;
    }
  }

  async function tryInsert(tableName, rows, dedupeKeys) {
    let lastError;
    let attempts = 0;
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      attempts = attempt;
      try {
        const table = await ensureTable(tableName);
        const rawRows = rows.map((row, index) => ({
          insertId: insertionId(tableName, row, index, dedupeKeys?.[index]),
          json: row,
        }));
        await table.insert(rawRows, {
          ignoreUnknownValues: true,
          skipInvalidRows: true,
          raw: true,
        });
        return { ok: true, attempts: attempt };
      } catch (error) {
        lastError = error;
        tableReady.delete(tableName);
        const willRetry = attempt < maxAttempts && isRetryableError(error);
        if (!willRetry) break;

        const delayMs = retryDelay(baseDelayMs, attempt);
        logger.warn("Retrying BigQuery insertion", {
          tableName,
          attempt,
          delayMs,
          error: serializeError(error),
        });
        await wait(delayMs);
      }
    }
    return { ok: false, attempts, error: lastError };
  }

  async function queueFailure(tableName, rows, source, result, dedupeKeys) {
    const failureRef = firestore.collection(FAILURE_COLLECTION).doc();
    const failedAt = now();
    const failure = {
      tableName,
      rows,
      source,
      // Persisted so a later recoverPending() replay reuses the same
      // insertId basis as the original attempt, instead of falling back to
      // content hashing.
      dedupeKeys: dedupeKeys || null,
      status: "pending",
      insertionAttempts: result.attempts,
      recoveryAttempts: 0,
      firstFailedAt: failedAt,
      lastFailedAt: failedAt,
      nextRetryAt: new Date(failedAt.getTime() + retryDelay(baseDelayMs, 1)),
      lastError: serializeError(result.error),
    };

    try {
      await failureRef.set(failure);
    } catch (queueError) {
      logger.error("BigQuery insertion and fallback persistence both failed", {
        tableName,
        source,
        insertError: failure.lastError,
        queueError: serializeError(queueError),
      });
      throw result.error;
    }

    logger.error("BigQuery insertion queued for recovery", {
      failureId: failureRef.id,
      tableName,
      source,
      attempts: result.attempts,
      error: failure.lastError,
    });
    return failureRef.id;
  }

  async function insert(tableName, rows, { source = "unspecified", dedupeKeys } = {}) {
    if (!tables[tableName]) {
      throw new Error(`Unknown BigQuery table: ${tableName}`);
    }
    const rowList = Array.isArray(rows) ? rows : [rows];
    const keyList = dedupeKeys == null
      ? undefined
      : (Array.isArray(dedupeKeys) ? dedupeKeys : [dedupeKeys]);
    if (rowList.length === 0) return { ok: true, attempts: 0 };

    const result = await tryInsert(tableName, rowList, keyList);
    if (result.ok) return result;

    const failureId = await queueFailure(tableName, rowList, source, result, keyList);
    return { ...result, queued: true, failureId };
  }

  async function claimFailure(document) {
    return firestore.runTransaction(async (transaction) => {
      const currentSnapshot = await transaction.get(document.ref);
      const current = currentSnapshot.data();
      if (!currentSnapshot.exists) return null;

      const currentTime = now();
      const isDue = current.status === "pending" &&
        toDate(current.nextRetryAt).getTime() <= currentTime.getTime();
      const claimExpired = current.status === "retrying" &&
        toDate(current.retryStartedAt).getTime() <=
          currentTime.getTime() - CLAIM_TIMEOUT_MS;
      if (!isDue && !claimExpired) return null;

      transaction.update(document.ref, {
        status: "retrying",
        retryStartedAt: currentTime,
      });
      return current;
    });
  }

  async function recoverPending({ limit = 100 } = {}) {
    const currentTime = now();
    const staleClaimTime = new Date(currentTime.getTime() - CLAIM_TIMEOUT_MS);
    const pendingQuery = firestore
      .collection(FAILURE_COLLECTION)
      .where("status", "==", "pending")
      .where("nextRetryAt", "<=", currentTime)
      .orderBy("nextRetryAt")
      .limit(limit);
    const staleQuery = firestore
      .collection(FAILURE_COLLECTION)
      .where("status", "==", "retrying")
      .where("retryStartedAt", "<=", staleClaimTime)
      .orderBy("retryStartedAt")
      .limit(limit);
    const [pendingSnapshot, staleSnapshot] = await Promise.all([
      pendingQuery.get(),
      staleQuery.get(),
    ]);
    const documents = [...pendingSnapshot.docs, ...staleSnapshot.docs]
      .slice(0, limit);

    const summary = { found: documents.length, recovered: 0, pending: 0, dead: 0 };
    for (const document of documents) {
      const failure = await claimFailure(document);
      if (!failure) continue;

      const recoveryAttempts = Number(failure.recoveryAttempts || 0) + 1;
      const result = await tryInsert(
        failure.tableName,
        failure.rows,
        failure.dedupeKeys || undefined
      );
      if (result.ok) {
        await document.ref.update({
          status: "recovered",
          recoveryAttempts,
          recoveredAt: now(),
          lastError: null,
        });
        summary.recovered += 1;
        continue;
      }

      const permanentlyFailed = recoveryAttempts >= maxRecoveryAttempts ||
        !isRetryableError(result.error);
      await document.ref.update({
        status: permanentlyFailed ? "dead" : "pending",
        recoveryAttempts,
        lastFailedAt: now(),
        nextRetryAt: permanentlyFailed ? null : new Date(
          now().getTime() + retryDelay(baseDelayMs, recoveryAttempts)
        ),
        lastError: serializeError(result.error),
      });
      summary[permanentlyFailed ? "dead" : "pending"] += 1;
    }

    logger.info("BigQuery recovery run completed", summary);
    return summary;
  }

  /**
   * Deletes resolved (recovered/dead) failure documents once they're older
   * than the retention window. Recovered/dead records are terminal - nothing
   * ever reads them again after the fact - so left alone they accumulate in
   * bigquery_insert_failures forever (#240).
   */
  async function cleanupResolved({ retentionMs = resolvedRetentionMs, limit = 500 } = {}) {
    const currentTime = now();
    const cutoff = new Date(currentTime.getTime() - retentionMs);

    const recoveredQuery = firestore
      .collection(FAILURE_COLLECTION)
      .where("status", "==", "recovered")
      .where("recoveredAt", "<=", cutoff)
      .limit(limit);
    const deadQuery = firestore
      .collection(FAILURE_COLLECTION)
      .where("status", "==", "dead")
      .where("lastFailedAt", "<=", cutoff)
      .limit(limit);
    const [recoveredSnapshot, deadSnapshot] = await Promise.all([
      recoveredQuery.get(),
      deadQuery.get(),
    ]);
    const candidates = [...recoveredSnapshot.docs, ...deadSnapshot.docs].slice(0, limit);

    const summary = { scanned: candidates.length, deleted: 0 };
    const seen = new Set();
    let batch = firestore.batch();
    let opsInBatch = 0;

    for (const document of candidates) {
      if (seen.has(document.id)) continue;
      seen.add(document.id);

      const data = document.data();
      if (!data) continue;

      // Defensive re-check against the document itself, in case the query
      // layer ever returns something broader than what was asked for - we
      // never want to delete a record that isn't actually resolved and past
      // retention.
      const resolvedAt = data.status === "recovered"
        ? toDate(data.recoveredAt)
        : data.status === "dead"
          ? toDate(data.lastFailedAt)
          : null;
      const isResolved = data.status === "recovered" || data.status === "dead";
      if (!isResolved || !resolvedAt || resolvedAt.getTime() > cutoff.getTime()) {
        continue;
      }

      batch.delete(document.ref);
      opsInBatch += 1;
      summary.deleted += 1;

      if (opsInBatch >= 500) {
        await batch.commit();
        batch = firestore.batch();
        opsInBatch = 0;
      }
    }

    if (opsInBatch > 0) {
      await batch.commit();
    }

    logger.info("BigQuery failure cleanup run completed", summary);
    return summary;
  }

  return { insert, recoverPending, cleanupResolved };
}

module.exports = {
  FAILURE_COLLECTION,
  createBigQueryRecovery,
  isRetryableError,
  serializeError,
};