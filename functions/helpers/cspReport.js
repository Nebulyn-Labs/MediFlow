const CSP_REPORT_MAX_BODY_BYTES = 10 * 1024; // 10KB
const CSP_REPORT_MIN_INTERVAL_MS = 5000; // 1 report per IP per 5s
const CSP_REPORT_MAP_MAX_SIZE = 5000; // hard cap to bound memory

const ALLOWED_CSP_CONTENT_TYPES = [
  "application/csp-report",
  "application/reports+json",
  "application/json",
];

const CSP_REPORT_KNOWN_KEYS = new Set([
  "document-uri",
  "blocked-uri",
  "violated-directive",
  "effective-directive",
  "original-policy",
  "source-file",
  "line-number",
  "column-number",
  "disposition",
  "status-code",
  "referrer",
  "script-sample",
  "sample",
  "type",
  "url",
  "body",
]);

function getClientIp(req) {
  // Cloud Run / GFE APPENDS the real client IP as the LAST entry in
  // X-Forwarded-For; every entry before that can be spoofed by the client.
  const xff = req.headers["x-forwarded-for"];
  if (xff) {
    const xffStr = Array.isArray(xff) ? xff.join(",") : String(xff);
    const parts = xffStr.split(",").map((p) => p.trim()).filter(Boolean);
    if (parts.length > 0) return parts[parts.length - 1];
  }
  return req.ip || "unknown";
}

function pruneCspReportMap(now, lastSeenMap) {
  // Periodic sweep: drop stale entries, and if we're still oversized
  // (e.g. distinct-IP flood), drop the oldest entries outright.
  for (const [ip, ts] of lastSeenMap) {
    if (now - ts >= CSP_REPORT_MIN_INTERVAL_MS) {
      lastSeenMap.delete(ip);
    }
  }
  if (lastSeenMap.size > CSP_REPORT_MAP_MAX_SIZE) {
    const excess = lastSeenMap.size - CSP_REPORT_MAP_MAX_SIZE;
    const oldestKeys = Array.from(lastSeenMap.keys()).slice(0, excess);
    for (const key of oldestKeys) {
      lastSeenMap.delete(key);
    }
  }
}

/**
 * Validates whether the incoming payload conforms to a CSP report schema.
 * Supports legacy W3C CSP report-uri format {"csp-report": {...}},
 * W3C Reporting API report-to format array/object, and direct violation JSON.
 *
 * @param {unknown} body Parsed request body
 * @returns {boolean} True if body is a valid CSP report payload
 */
function isValidCspReportPayload(body) {
  if (!body || typeof body !== "object") {
    return false;
  }

  // Legacy format: { "csp-report": { ... } }
  if (
    body["csp-report"] &&
    typeof body["csp-report"] === "object" &&
    !Array.isArray(body["csp-report"])
  ) {
    const report = body["csp-report"];
    const keys = Object.keys(report);
    if (keys.length === 0) return false;
    return keys.some((k) => CSP_REPORT_KNOWN_KEYS.has(k.toLowerCase()));
  }

  // W3C Reporting API array format: [ { "type": "csp-violation", "body": { ... } } ]
  if (Array.isArray(body)) {
    if (body.length === 0) return false;
    return (
      body.every(
        (item) => item && typeof item === "object" && !Array.isArray(item)
      ) &&
      body.some((item) => {
        if (item.type === "csp-violation" || item.type === "csp") return true;
        const keys = Object.keys(item);
        return keys.some((k) => CSP_REPORT_KNOWN_KEYS.has(k.toLowerCase()));
      })
    );
  }

  // Direct violation object format
  const keys = Object.keys(body);
  if (keys.length === 0) return false;
  return keys.some((k) => CSP_REPORT_KNOWN_KEYS.has(k.toLowerCase()));
}

/**
 * Handles incoming CSP report request with validation, size limits, and rate limiting.
 *
 * @param {import("express").Request} req Express request
 * @param {import("express").Response} res Express response
 * @param {object} logger Functions logger
 * @param {Map<string, number>} lastSeenMap In-memory IP rate limiting map
 */
async function handleCspReport(req, res, logger, lastSeenMap) {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const headerContentType = req.headers["content-type"];
  const rawContentType = Array.isArray(headerContentType)
    ? headerContentType[0]
    : headerContentType || "";
  const contentType = rawContentType.split(";")[0].trim().toLowerCase();
  if (!contentType || !ALLOWED_CSP_CONTENT_TYPES.includes(contentType)) {
    res.status(415).send("Unsupported Media Type");
    return;
  }

  const rawContentLength = req.headers["content-length"];
  if (rawContentLength !== undefined) {
    const contentLength = Number(rawContentLength);
    if (
      Number.isNaN(contentLength) ||
      contentLength < 0 ||
      contentLength > CSP_REPORT_MAX_BODY_BYTES
    ) {
      res.status(413).send("Payload Too Large");
      return;
    }
  }

  let bodyString = "";
  if (typeof req.body === "string") {
    bodyString = req.body;
  } else if (Buffer.isBuffer(req.body)) {
    bodyString = req.body.toString("utf8");
  } else if (req.body && typeof req.body === "object") {
    try {
      bodyString = JSON.stringify(req.body);
    } catch {
      res.status(400).send("Bad Request");
      return;
    }
  }

  if (Buffer.byteLength(bodyString, "utf8") > CSP_REPORT_MAX_BODY_BYTES) {
    res.status(413).send("Payload Too Large");
    return;
  }

  let parsedBody = req.body;
  if (typeof req.body === "string" || Buffer.isBuffer(req.body)) {
    const str =
      typeof req.body === "string" ? req.body : req.body.toString("utf8");
    try {
      parsedBody = JSON.parse(str);
    } catch {
      res.status(400).send("Bad Request");
      return;
    }
  }

  if (!isValidCspReportPayload(parsedBody)) {
    res.status(400).send("Bad Request");
    return;
  }

  const ip = getClientIp(req);
  const now = Date.now();

  if (lastSeenMap.size > CSP_REPORT_MAP_MAX_SIZE) {
    pruneCspReportMap(now, lastSeenMap);
  }

  const lastSeen = lastSeenMap.get(ip);
  if (lastSeen && now - lastSeen < CSP_REPORT_MIN_INTERVAL_MS) {
    res.status(429).send("Too Many Requests");
    return;
  }
  lastSeenMap.set(ip, now);

  if (logger && typeof logger.warn === "function") {
    logger.warn("CSP Violation Report", { report: parsedBody });
  }
  res.status(204).send();
}

module.exports = {
  handleCspReport,
  isValidCspReportPayload,
  getClientIp,
  pruneCspReportMap,
  CSP_REPORT_MAX_BODY_BYTES,
  CSP_REPORT_MIN_INTERVAL_MS,
  CSP_REPORT_MAP_MAX_SIZE,
  ALLOWED_CSP_CONTENT_TYPES,
};
