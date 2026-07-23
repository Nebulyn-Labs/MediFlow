const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const {
  FAILURE_COLLECTION,
  createBigQueryRecovery,
  isRetryableError,
} = require("../helpers/bigQueryRecovery");

function createLogger() {
  return { info() {}, warn() {}, error() {} };
}

function createBigQuery(insert) {
  const table = {
    exists: async () => [true],
    insert,
  };
  const dataset = {
    exists: async () => [true],
    table: () => table,
    createTable: async () => {},
  };
  return {
    table,
    client: {
      dataset: () => dataset,
      createDataset: async () => {},
    },
  };
}

function createFirestore() {
  const documents = new Map();
  let nextId = 1;

  function snapshot(ref) {
    return {
      id: ref.id,
      ref,
      get exists() {
        return documents.has(ref.id);
      },
      data: () => documents.get(ref.id),
    };
  }

  function documentReference(id) {
    const ref = {
      id,
      set: async (value) => documents.set(id, { ...value }),
      update: async (value) => {
        documents.set(id, { ...documents.get(id), ...value });
      },
    };
    return ref;
  }

  const firestore = {
    collection: (name) => {
      assert.equal(name, FAILURE_COLLECTION);
      const query = {
        doc: () => documentReference(`failure-${nextId++}`),
        where: () => query,
        orderBy: () => query,
        limit: () => query,
        get: async () => {
          const docs = [...documents.keys()].map((id) =>
            snapshot(documentReference(id))
          );
          return { docs, size: docs.length };
        },
      };
      return query;
    },
    runTransaction: async (callback) => callback({
      get: async (ref) => snapshot(ref),
      update: (ref, value) => {
        documents.set(ref.id, { ...documents.get(ref.id), ...value });
      },
    }),
  };

  return { firestore, documents };
}

function createRecovery({ insert, firestore, overrides = {} }) {
  const bigquery = createBigQuery(insert);
  return {
    bigquery,
    recovery: createBigQueryRecovery({
      bigquery: bigquery.client,
      firestore,
      logger: createLogger(),
      tables: { events: { schema: [{ name: "event_id", type: "STRING" }] } },
      datasetName: "analytics",
      location: "US",
      wait: async () => {},
      ...overrides,
    }),
  };
}

describe("BigQuery recovery", () => {
  it("keeps successful inserts on the direct path", async () => {
    const calls = [];
    const { firestore, documents } = createFirestore();
    const { recovery } = createRecovery({
      firestore,
      insert: async (...args) => calls.push(args),
    });

    const result = await recovery.insert("events", { event_id: "evt-1" });

    assert.equal(result.ok, true);
    assert.equal(result.attempts, 1);
    assert.equal(documents.size, 0);
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0][0].json.event_id, "evt-1");
    assert.equal(calls[0][1].raw, true);
  });

  it("retries transient failures with a stable insertion ID", async () => {
    const insertionIds = [];
    const delays = [];
    let calls = 0;
    const { firestore, documents } = createFirestore();
    const bigquery = createBigQuery(async (rows) => {
      calls += 1;
      insertionIds.push(rows[0].insertId);
      if (calls === 1) {
        const error = new Error("temporarily unavailable");
        error.code = 503;
        throw error;
      }
    });
    const recovery = createBigQueryRecovery({
      bigquery: bigquery.client,
      firestore,
      logger: createLogger(),
      tables: { events: { schema: [] } },
      datasetName: "analytics",
      location: "US",
      wait: async (delay) => delays.push(delay),
    });

    const result = await recovery.insert("events", { event_id: "evt-2" });

    assert.equal(result.ok, true);
    assert.equal(result.attempts, 2);
    assert.deepEqual(delays, [250]);
    assert.equal(insertionIds[0], insertionIds[1]);
    assert.equal(documents.size, 0);
  });

  it("queues an observable failure after a non-retryable error", async () => {
    const { firestore, documents } = createFirestore();
    const schemaError = new Error("invalid field");
    schemaError.code = 400;
    const { recovery } = createRecovery({
      firestore,
      insert: async () => {
        throw schemaError;
      },
    });

    const result = await recovery.insert(
      "events",
      { event_id: "evt-3" },
      { source: "unit_test" }
    );

    assert.equal(result.ok, false);
    assert.equal(result.queued, true);
    assert.equal(result.attempts, 1);
    const failure = documents.get(result.failureId);
    assert.equal(failure.status, "pending");
    assert.equal(failure.source, "unit_test");
    assert.equal(failure.lastError.code, 400);
  });

  it("replays queued rows and marks them recovered", async () => {
    let shouldFail = true;
    let currentTime = new Date("2026-07-22T00:00:00.000Z");
    const { firestore, documents } = createFirestore();
    const { recovery } = createRecovery({
      firestore,
      insert: async () => {
        if (shouldFail) {
          const error = new Error("service unavailable");
          error.code = 503;
          throw error;
        }
      },
      overrides: {
        maxAttempts: 1,
        now: () => currentTime,
      },
    });

    const queued = await recovery.insert("events", { event_id: "evt-4" });
    shouldFail = false;
    currentTime = new Date("2026-07-22T00:01:00.000Z");

    const summary = await recovery.recoverPending();

    assert.equal(summary.recovered, 1);
    assert.equal(documents.get(queued.failureId).status, "recovered");
    assert.equal(documents.get(queued.failureId).recoveryAttempts, 1);
  });
});

describe("isRetryableError", () => {
  it("distinguishes temporary failures from schema failures", () => {
    assert.equal(isRetryableError({ code: 429 }), true);
    assert.equal(isRetryableError({ code: "ETIMEDOUT" }), true);
    assert.equal(isRetryableError({ code: 400 }), false);
  });
});
