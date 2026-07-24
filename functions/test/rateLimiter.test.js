const assert = require("node:assert/strict");
const { describe, it, before, after } = require("node:test");
const path = require("path");

function createMockTimestamp() {
  return {
    now: () => {
      const ms = Date.now();
      return { toMillis: () => ms, seconds: Math.floor(ms / 1000), nanoseconds: 0 };
    },
    fromMillis: (ms) => ({ toMillis: () => ms, seconds: Math.floor(ms / 1000), nanoseconds: 0 }),
  };
}

function createMockFirestore() {
  const documents = new Map();
  return {
    collection: () => ({
      doc: (id) => ({
        id,
        path: `rate_limits/${id}`,
      }),
      where: () => ({
        limit: () => ({
          get: async () => {
            const now = Date.now();
            const expired = [];
            for (const [id, data] of documents) {
              if (data.ttl && data.ttl.toMillis() < now) {
                expired.push({ id, ref: { id }, data: () => data });
              }
            }
            const docs = expired.slice(0, 100);
            return { empty: docs.length === 0, docs, size: docs.length };
          },
        }),
      }),
    }),
    batch: () => {
      let ops = [];
      return {
        delete: (ref) => ops.push({ type: "delete", ref }),
        commit: async () => {
          for (const op of ops) {
            if (op.type === "delete") documents.delete(op.ref.id);
          }
          ops = [];
        },
      };
    },
    runTransaction: async (fn) => {
      const transaction = {
        get: async (ref) => ({
          exists: documents.has(ref.id),
          data: () => documents.get(ref.id),
        }),
        set: (ref, data) => documents.set(ref.id, { ...data }),
        update: (ref, data) => {
          documents.set(ref.id, { ...documents.get(ref.id), ...data });
        },
      };
      await fn(transaction);
    },
    documents,
  };
}

function loadRateLimiter() {
  const mockFs = createMockFirestore();
  const ts = createMockTimestamp();
  const firestoreFn = () => mockFs;
  firestoreFn.Timestamp = ts;

  const mockAdmin = { firestore: firestoreFn };

  const rateLimiterPath = path.resolve(__dirname, "..", "helpers", "rateLimiter.js");
  const resolvedAdmin = require.resolve("firebase-admin");

  delete require.cache[rateLimiterPath];
  Object.keys(require.cache).forEach((key) => {
    if (key.includes("firebase-admin")) {
      delete require.cache[key];
    }
  });

  require.cache[resolvedAdmin] = {
    id: resolvedAdmin,
    filename: resolvedAdmin,
    loaded: true,
    exports: mockAdmin,
  };

  return { mod: require(rateLimiterPath), mockFs };
}

describe("Rate limiter constants", () => {
  it("exports expected LIMITS", () => {
    const { mod } = loadRateLimiter();
    assert.equal(mod.LIMITS.AI.limit, 20);
    assert.equal(mod.LIMITS.GENERAL.limit, 100);
    assert.equal(mod.LIMITS.AI.windowMs, 3600000);
  });

  it("exports COLLECTION constant", () => {
    const { mod } = loadRateLimiter();
    assert.equal(mod.COLLECTION, "rate_limits");
  });

  it("exports CLEANUP_BATCH_SIZE constant", () => {
    const { mod } = loadRateLimiter();
    assert.equal(mod.CLEANUP_BATCH_SIZE, 100);
  });
});

describe("checkRateLimit", () => {
  it("creates a new document with ttl on first call", async () => {
    const { mod, mockFs } = loadRateLimiter();
    await mod.checkRateLimit("user1", "testEndpoint", mod.LIMITS.GENERAL);

    const key = "user1_testEndpoint";
    assert.ok(mockFs.documents.has(key));
    const doc = mockFs.documents.get(key);
    assert.equal(doc.count, 1);
    assert.ok(doc.windowStart);
    assert.ok(doc.ttl);
    assert.ok(doc.ttl.toMillis() > doc.windowStart.toMillis());
  });

  it("resets count and updates ttl when window expired", async () => {
    const { mod, mockFs } = loadRateLimiter();
    const key = "user1_testEndpoint";
    const pastStart = Date.now() - 2 * mod.LIMITS.GENERAL.windowMs;

    mockFs.documents.set(key, {
      count: 50,
      windowStart: { toMillis: () => pastStart },
      ttl: { toMillis: () => pastStart + 7200000 },
    });

    await mod.checkRateLimit("user1", "testEndpoint", mod.LIMITS.GENERAL);
    const doc = mockFs.documents.get(key);
    assert.equal(doc.count, 1);
    assert.ok(doc.windowStart.toMillis() > pastStart);
  });

  it("throws resource-exhausted when limit exceeded", async () => {
    const { mod, mockFs } = loadRateLimiter();
    const key = "user1_testEndpoint";

    mockFs.documents.set(key, {
      count: 100,
      windowStart: { toMillis: () => Date.now() },
      ttl: { toMillis: () => Date.now() + 3600000 },
    });

    await assert.rejects(
      () => mod.checkRateLimit("user1", "testEndpoint", mod.LIMITS.GENERAL),
      (err) => err.code === "resource-exhausted"
    );
  });

  it("increments count within the same window", async () => {
    const { mod, mockFs } = loadRateLimiter();
    const key = "user1_testEndpoint";

    mockFs.documents.set(key, {
      count: 5,
      windowStart: { toMillis: () => Date.now() },
      ttl: { toMillis: () => Date.now() + 3600000 },
    });

    await mod.checkRateLimit("user1", "testEndpoint", mod.LIMITS.GENERAL);
    assert.equal(mockFs.documents.get(key).count, 6);
  });
});

describe("cleanupExpiredRateLimits", () => {
  it("returns 0 when no expired documents exist", async () => {
    const { mod, mockFs } = loadRateLimiter();
    const future = Date.now() + 7200000;

    mockFs.documents.set("active_doc", {
      count: 1,
      windowStart: { toMillis: () => Date.now() },
      ttl: { toMillis: () => future },
    });

    const result = await mod.cleanupExpiredRateLimits();
    assert.equal(result.deletedCount, 0);
    assert.ok(mockFs.documents.has("active_doc"));
  });

  it("removes documents with expired ttl", async () => {
    const { mod, mockFs } = loadRateLimiter();
    const past = Date.now() - 7200000;

    mockFs.documents.set("expired_doc", {
      count: 1,
      windowStart: { toMillis: () => past },
      ttl: { toMillis: () => past },
    });

    const result = await mod.cleanupExpiredRateLimits();
    assert.equal(result.deletedCount, 1);
    assert.ok(!mockFs.documents.has("expired_doc"));
  });

  it("handles empty collection gracefully", async () => {
    const { mod } = loadRateLimiter();
    const result = await mod.cleanupExpiredRateLimits();
    assert.equal(result.deletedCount, 0);
  });

  it("removes only expired documents, leaves active ones", async () => {
    const { mod, mockFs } = loadRateLimiter();
    const past = Date.now() - 7200000;
    const future = Date.now() + 7200000;

    mockFs.documents.set("expired_doc", {
      count: 1,
      windowStart: { toMillis: () => past },
      ttl: { toMillis: () => past },
    });

    mockFs.documents.set("active_doc", {
      count: 1,
      windowStart: { toMillis: () => Date.now() },
      ttl: { toMillis: () => future },
    });

    const result = await mod.cleanupExpiredRateLimits();
    assert.equal(result.deletedCount, 1);
    assert.ok(!mockFs.documents.has("expired_doc"));
    assert.ok(mockFs.documents.has("active_doc"));
  });
});
