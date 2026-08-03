const assert = require("node:assert/strict");
const { describe, it, beforeEach } = require("node:test");
const {
  handleCspReport,
  isValidCspReportPayload,
} = require("../helpers/cspReport");

function mockResponse() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    send(data) {
      this.body = data;
      return this;
    },
  };
  return res;
}

function mockLogger() {
  return {
    warn() {},
    error() {},
    info() {},
  };
}

describe("CSP Report Handler Security & Validation", () => {
  let lastSeenMap;
  let logger;

  beforeEach(() => {
    lastSeenMap = new Map();
    logger = mockLogger();
  });

  it("rejects non-POST HTTP methods with 405 Method Not Allowed", async () => {
    for (const method of ["GET", "PUT", "DELETE", "PATCH"]) {
      const req = {
        method,
        headers: { "content-type": "application/csp-report" },
        body: { "csp-report": { "document-uri": "https://example.com" } },
      };
      const res = mockResponse();

      await handleCspReport(req, res, logger, lastSeenMap);

      assert.equal(res.statusCode, 405);
      assert.equal(res.body, "Method Not Allowed");
    }
  });

  it("rejects invalid or missing Content-Type with 415 Unsupported Media Type", async () => {
    const invalidContentTypes = [
      "",
      "text/plain",
      "text/html",
      "application/x-www-form-urlencoded",
      "multipart/form-data",
    ];

    for (const contentType of invalidContentTypes) {
      const req = {
        method: "POST",
        headers: contentType ? { "content-type": contentType } : {},
        body: { "csp-report": { "document-uri": "https://example.com" } },
      };
      const res = mockResponse();

      await handleCspReport(req, res, logger, lastSeenMap);

      assert.equal(res.statusCode, 415);
      assert.equal(res.body, "Unsupported Media Type");
    }
  });

  it("rejects oversized Content-Length headers with 413 Payload Too Large", async () => {
    const req = {
      method: "POST",
      headers: {
        "content-type": "application/csp-report",
        "content-length": "20000",
      },
      body: { "csp-report": { "document-uri": "https://example.com" } },
    };
    const res = mockResponse();

    await handleCspReport(req, res, logger, lastSeenMap);

    assert.equal(res.statusCode, 413);
    assert.equal(res.body, "Payload Too Large");
  });

  it("rejects oversized payload bodies (>10KB) with 413 Payload Too Large", async () => {
    const largePadding = "a".repeat(11 * 1024);
    const req = {
      method: "POST",
      headers: { "content-type": "application/csp-report" },
      body: {
        "csp-report": {
          "document-uri": "https://example.com",
          "script-sample": largePadding,
        },
      },
    };
    const res = mockResponse();

    await handleCspReport(req, res, logger, lastSeenMap);

    assert.equal(res.statusCode, 413);
    assert.equal(res.body, "Payload Too Large");
  });

  it("rejects missing, empty, or unparseable bodies with 400 Bad Request", async () => {
    const invalidBodies = [
      null,
      undefined,
      "",
      "not-json-format",
      {},
      [],
      { invalid: "data" },
      { "csp-report": {} },
    ];

    for (const body of invalidBodies) {
      const req = {
        method: "POST",
        headers: { "content-type": "application/csp-report" },
        body,
      };
      const res = mockResponse();

      await handleCspReport(req, res, logger, lastSeenMap);

      assert.equal(res.statusCode, 400);
      assert.equal(res.body, "Bad Request");
    }
  });

  it("accepts valid legacy W3C CSP report format with 204 No Content", async () => {
    const req = {
      method: "POST",
      headers: { "content-type": "application/csp-report" },
      ip: "192.168.1.1",
      body: {
        "csp-report": {
          "document-uri": "https://example.com/page",
          "referrer": "https://google.com",
          "blocked-uri": "https://evil.com/malicious.js",
          "violated-directive": "script-src 'self'",
          "original-policy": "default-src 'self'",
        },
      },
    };
    const res = mockResponse();

    await handleCspReport(req, res, logger, lastSeenMap);

    assert.equal(res.statusCode, 204);
  });

  it("accepts valid modern W3C Reporting API array format with 204 No Content", async () => {
    const req = {
      method: "POST",
      headers: { "content-type": "application/reports+json" },
      ip: "192.168.1.2",
      body: [
        {
          type: "csp-violation",
          age: 10,
          url: "https://example.com/app",
          user_agent: "Mozilla/5.0",
          body: {
            blockedURL: "inline",
            effectiveDirective: "script-src-elem",
          },
        },
      ],
    };
    const res = mockResponse();

    await handleCspReport(req, res, logger, lastSeenMap);

    assert.equal(res.statusCode, 204);
  });

  it("accepts valid direct violation object format with 204 No Content", async () => {
    const req = {
      method: "POST",
      headers: { "content-type": "application/json; charset=utf-8" },
      ip: "192.168.1.3",
      body: JSON.stringify({
        "blocked-uri": "https://untrusted.cdn.com/lib.js",
        "document-uri": "https://mediflow.app/dashboard",
        "violated-directive": "script-src",
      }),
    };
    const res = mockResponse();

    await handleCspReport(req, res, logger, lastSeenMap);

    assert.equal(res.statusCode, 204);
  });

  it("enforces rate limits per client IP with 429 Too Many Requests", async () => {
    const req = {
      method: "POST",
      headers: {
        "content-type": "application/csp-report",
        "x-forwarded-for": "203.0.113.195",
      },
      body: {
        "csp-report": {
          "document-uri": "https://example.com",
          "blocked-uri": "https://tracker.com",
        },
      },
    };

    // First request -> Success (204)
    const res1 = mockResponse();
    await handleCspReport(req, res1, logger, lastSeenMap);
    assert.equal(res1.statusCode, 204);

    // Immediate second request from same IP -> Rate limited (429)
    const res2 = mockResponse();
    await handleCspReport(req, res2, logger, lastSeenMap);
    assert.equal(res2.statusCode, 429);
    assert.equal(res2.body, "Too Many Requests");
  });

  it("handles array headers for X-Forwarded-For and Content-Type gracefully", async () => {
    const req = {
      method: "POST",
      headers: {
        "content-type": ["application/csp-report; charset=utf-8"],
        "x-forwarded-for": ["192.168.1.10", "203.0.113.50"],
      },
      body: {
        "csp-report": {
          "document-uri": "https://example.com",
        },
      },
    };
    const res = mockResponse();
    await handleCspReport(req, res, logger, lastSeenMap);
    assert.equal(res.statusCode, 204);
  });

  it("rejects malformed non-numeric Content-Length headers with 413 Payload Too Large", async () => {
    const req = {
      method: "POST",
      headers: {
        "content-type": "application/csp-report",
        "content-length": "invalid-length",
      },
      body: {
        "csp-report": {
          "document-uri": "https://example.com",
        },
      },
    };
    const res = mockResponse();
    await handleCspReport(req, res, logger, lastSeenMap);
    assert.equal(res.statusCode, 413);
  });

  it("rejects circular JSON structures with 400 Bad Request", async () => {
    const circularObj = {};
    circularObj.self = circularObj;
    const req = {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: circularObj,
    };
    const res = mockResponse();
    await handleCspReport(req, res, logger, lastSeenMap);
    assert.equal(res.statusCode, 400);
  });

  it("accepts valid Buffer payloads with 204 No Content", async () => {
    const payload = JSON.stringify({
      "csp-report": {
        "document-uri": "https://example.com",
        "blocked-uri": "https://evil.com/script.js",
      },
    });
    const req = {
      method: "POST",
      headers: { "content-type": "application/csp-report" },
      body: Buffer.from(payload),
    };
    const res = mockResponse();
    await handleCspReport(req, res, logger, lastSeenMap);
    assert.equal(res.statusCode, 204);
  });
});

describe("isValidCspReportPayload helper", () => {
  it("returns false for non-objects or empty structures", () => {
    assert.equal(isValidCspReportPayload(null), false);
    assert.equal(isValidCspReportPayload(undefined), false);
    assert.equal(isValidCspReportPayload("string"), false);
    assert.equal(isValidCspReportPayload(123), false);
    assert.equal(isValidCspReportPayload({}), false);
    assert.equal(isValidCspReportPayload([]), false);
  });

  it("identifies legacy, reporting API, and direct CSP payloads", () => {
    assert.equal(
      isValidCspReportPayload({
        "csp-report": { "blocked-uri": "http://example.com" },
      }),
      true
    );
    assert.equal(
      isValidCspReportPayload([
        { type: "csp-violation", url: "https://example.com" },
      ]),
      true
    );
    assert.equal(
      isValidCspReportPayload({ "effective-directive": "script-src" }),
      true
    );
  });
});
