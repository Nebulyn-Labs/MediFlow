const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { BigQuery } = require("@google-cloud/bigquery");
const { checkRateLimit, LIMITS } = require("./helpers/rateLimiter");
const { createBigQueryRecovery } = require("./helpers/bigQueryRecovery");

admin.initializeApp();

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

async function getUserFacilityAndRole(auth, db) {
  if (!auth) {
    throw new HttpsError("unauthenticated", "User must log in");
  }

  const userEmail = auth.token.email.toLowerCase();
  const isAdmin = userEmail === "admin@mediflow.com";
  let userFacilityId = null;

  if (!isAdmin) {
    const docId = userEmail.replace(/@/g, "_").replace(/\./g, "_");
    const facilityDoc = await db.collection("facilities").doc(docId).get();
    if (!facilityDoc.exists) {
      // Fallback query by email field
      const facilitiesSnapshot = await db.collection("facilities")
        .where("email", "==", userEmail)
        .limit(1)
        .get();
      if (facilitiesSnapshot.empty) {
        throw new HttpsError("failed-precondition", "No facility assigned to this user");
      }
      userFacilityId = facilitiesSnapshot.docs[0].id;
    } else {
      userFacilityId = docId;
    }
  }

  return {
    userEmail,
    userFacilityId,
    isAdmin,
    role: isAdmin ? "admin" : "facility_head",
  };
}


const bigquery = new BigQuery();
const BQ_DATASET = process.env.BQ_DATASET || "mediflow_analytics";
const BQ_LOCATION = process.env.BQ_LOCATION || "US";

// Initialize Gemini clients per-invocation using the GEMINI_API_KEY secret.
// NOTE: GEMINI_API_KEY must be set in Firebase Secrets
// Use: firebase functions:secrets:set GEMINI_API_KEY
function getGenAI() {
  return new GoogleGenerativeAI(GEMINI_API_KEY.value());
}

const BIGQUERY_TABLES = {
  ai_decisions: {
    schema: [
      { name: "decision_id", type: "STRING", mode: "REQUIRED" },
      { name: "occurred_at", type: "TIMESTAMP" },
      { name: "facility_id", type: "STRING" },
      { name: "medicine_name", type: "STRING" },
      { name: "decision_type", type: "STRING" },
      { name: "model", type: "STRING" },
      { name: "prediction", type: "INTEGER" },
      { name: "confidence", type: "STRING" },
      { name: "recommendation", type: "STRING" },
      { name: "reasoning", type: "STRING" },
      { name: "period_days", type: "INTEGER" },
      { name: "input_json", type: "STRING" },
      { name: "output_json", type: "STRING" },
    ],
  },
  transfer_requests: {
    schema: [
      { name: "request_id", type: "STRING", mode: "REQUIRED" },
      { name: "facility_id", type: "STRING" },
      { name: "medicine_name", type: "STRING" },
      { name: "request_type", type: "STRING" },
      { name: "quantity", type: "INTEGER" },
      { name: "status", type: "STRING" },
      { name: "request_date", type: "TIMESTAMP" },
      { name: "notes", type: "STRING" },
      { name: "captured_at", type: "TIMESTAMP" },
      { name: "payload_json", type: "STRING" },
    ],
  },
  inventory_snapshots: {
    schema: [
      { name: "snapshot_id", type: "STRING", mode: "REQUIRED" },
      { name: "facility_id", type: "STRING" },
      { name: "medicine_id", type: "STRING" },
      { name: "medicine_name", type: "STRING" },
      { name: "batch_id", type: "STRING" },
      { name: "initial_quantity", type: "INTEGER" },
      { name: "remaining_quantity", type: "INTEGER" },
      { name: "unit", type: "STRING" },
      { name: "expiry_date", type: "DATE" },
      { name: "arrival_date", type: "DATE" },
      { name: "stock_pct", type: "FLOAT" },
      { name: "status", type: "STRING" },
      { name: "captured_at", type: "TIMESTAMP" },
      { name: "payload_json", type: "STRING" },
    ],
  },
  usage_analytics: {
    schema: [
      { name: "usage_id", type: "STRING", mode: "REQUIRED" },
      { name: "facility_id", type: "STRING" },
      { name: "log_id", type: "STRING" },
      { name: "usage_date", type: "DATE" },
      { name: "medicine_name", type: "STRING" },
      { name: "units_distributed", type: "INTEGER" },
      { name: "total_patients", type: "INTEGER" },
      { name: "captured_at", type: "TIMESTAMP" },
      { name: "payload_json", type: "STRING" },
    ],
  },
  audit_events: {
    schema: [
      { name: "event_id", type: "STRING", mode: "REQUIRED" },
      { name: "occurred_at", type: "TIMESTAMP" },
      { name: "actor_id", type: "STRING" },
      { name: "source", type: "STRING" },
      { name: "entity_type", type: "STRING" },
      { name: "entity_id", type: "STRING" },
      { name: "action", type: "STRING" },
      { name: "facility_id", type: "STRING" },
      { name: "medicine_name", type: "STRING" },
      { name: "before_json", type: "STRING" },
      { name: "after_json", type: "STRING" },
      { name: "metadata_json", type: "STRING" },
    ],
  },
};

function safeJson(value) {
  return JSON.stringify(value ?? null, (_, v) => {
    if (v && typeof v.toDate === "function") return v.toDate().toISOString();
    return v;
  });
}

function toIsoTimestamp(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return value;
}

function toBigQueryDate(value) {
  const iso = toIsoTimestamp(value);
  return iso ? iso.substring(0, 10) : null;
}

function stockStatus(data) {
  const initial = Number(data.initialQuantity || 0);
  const remaining = Number(data.remainingQuantity || 0);
  const pct = initial > 0 ? remaining / initial : 0;
  const expiry = toIsoTimestamp(data.expiryDate);
  const daysLeft = expiry ? Math.ceil((new Date(expiry).getTime() - Date.now()) / 86400000) : null;

  if (daysLeft !== null && daysLeft < 0) return "expired";
  if (pct >= 0.7 && daysLeft !== null && daysLeft <= 30) return "wastage_risk";
  if (pct <= 0.2 || remaining <= 500) return "low_stock";
  if (daysLeft !== null && daysLeft <= 30) return "expiring_soon";
  return "healthy";
}

const bigQueryRecovery = createBigQueryRecovery({
  bigquery,
  firestore: admin.firestore(),
  logger,
  tables: BIGQUERY_TABLES,
  datasetName: BQ_DATASET,
  location: BQ_LOCATION,
});

async function insertBigQuery(tableName, rows, source) {
  return bigQueryRecovery.insert(tableName, rows, { source });
}

async function auditEvent({ eventId, action, entityType, entityId, before, after, facilityId, medicineName, metadata, actorId = null }) {
  await insertBigQuery("audit_events", {
    event_id: eventId,
    occurred_at: new Date().toISOString(),
    actor_id: actorId,
    source: "firestore",
    entity_type: entityType,
    entity_id: entityId,
    action,
    facility_id: facilityId || after?.facilityId || before?.facilityId || null,
    medicine_name: medicineName || after?.medicineName || before?.medicineName || null,
    before_json: safeJson(before),
    after_json: safeJson(after),
    metadata_json: safeJson(metadata),
  }, "audit_event");
}

/**
 * 1. forecastDemand(facilityId, medicineNames[])
 * Calls Gemini to predict demand based on 90-day history.
 */
exports.forecastDemand = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must log in');

  const { facilityId, medicineNames } = request.data;
  const db = admin.firestore();

  const authInfo = await getUserFacilityAndRole(request.auth, db);
  if (!authInfo.isAdmin && facilityId !== authInfo.userFacilityId) {
    throw new HttpsError('permission-denied', 'Unauthorized facility access');
  }

  await checkRateLimit(
    request.auth.uid,
    "forecastDemand",
    LIMITS.AI
  );

  // 1. Fetch facility details
  const facilityDoc = await db.collection("facilities").doc(facilityId).get();
  const facility = facilityDoc.data();

  // 2. Fetch last 90 days of usage_logs
  const ninetyDaysAgo = new Date();
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

  const usageQuery = await db.collection("facilities")
    .doc(facilityId)
    .collection("usage_logs")
    .where("loggedAt", ">=", admin.firestore.Timestamp.fromDate(ninetyDaysAgo))
    .get();

  const usageHistory = usageQuery.docs.map(doc => doc.data());

  // 3. Fetch current stock levels
  const stocksQuery = await db.collection("facilities")
    .doc(facilityId)
    .collection("stocks")
    .get();

  const currentStocks = stocksQuery.docs.map(doc => ({
    medicineName: doc.data().medicineName,
    qtyRemaining: doc.data().qtyRemaining
  }));

  // 4. Construct Gemini Prompt
  const genAI = getGenAI();
  const model = genAI.getGenerativeModel({ model: "gemini-1.5-pro" });
  const prompt = `
    SYSTEM: You are a medical supply chain forecasting AI. Analyze the provided 90-day usage history for a healthcare facility and predict demand for the next 30 days per medicine. Be conservative. Account for seasonal spikes. Return ONLY valid JSON matching the schema.

    USER: 
    Facility: ${facility.name}. District: ${facility.district}.
    Historical Usage Data (last 90 days): ${JSON.stringify(usageHistory)}
    Current Stock Levels: ${JSON.stringify(currentStocks)}
    Target Medicines: ${medicineNames.join(", ")}

    JSON Schema response (enforce strictly):
    {
      "forecasts": [
        {
          "medicineName": "string",
          "predictedQty30Days": "integer",
          "reorderRecommended": "boolean",
          "confidence": "low|medium|high",
          "rationale": "string (max 30 words)"
        }
      ],
      "overallRiskLevel": "low|medium|critical",
      "summary": "string (max 50 words)"
    }
  `;

  try {
    const result = await model.generateContent(prompt);
    const responseText = result.response.text();
    // Use regex to extract JSON if Gemini wraps it in markdown blocks
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    return JSON.parse(jsonMatch ? jsonMatch[0] : responseText);
  } catch (error) {
    logger.error("Gemini Error:", error);
    throw new HttpsError('internal', 'AI forecasting failed');
  }
});

/**
 * 1b. logAIDecision()
 * Explicit audit hook for client-side AI forecasts and stock-analysis decisions.
 */
exports.logAIDecision = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must log in");

  const db = admin.firestore();
  const authInfo = await getUserFacilityAndRole(request.auth, db);
  const data = request.data;
  const { facilityId } = data;
  if (!authInfo.isAdmin && facilityId !== authInfo.userFacilityId) {
    throw new HttpsError("permission-denied", "Unauthorized facility access");
  }

  await checkRateLimit(
    request.auth.uid,
    "logAIDecision",
    LIMITS.GENERAL
  );

  const decisionId = data.decisionId || `${Date.now()}_${Math.random().toString(36).slice(2)}`;
  await insertBigQuery("ai_decisions", {
    decision_id: decisionId,
    occurred_at: new Date().toISOString(),
    facility_id: data.facilityId || null,
    medicine_name: data.medicineName || null,
    decision_type: data.decisionType || "stock_analysis",
    model: data.model || "client_ai",
    prediction: Number.isFinite(Number(data.prediction)) ? Number(data.prediction) : null,
    confidence: data.confidence || null,
    recommendation: data.recommendation || null,
    reasoning: data.reasoning || null,
    period_days: Number.isFinite(Number(data.periodDays)) ? Number(data.periodDays) : null,
    input_json: safeJson(data.input),
    output_json: safeJson(data.output),
  }, "log_ai_decision");

  await auditEvent({
    eventId: `ai_${decisionId}`,
    action: "ai_decision_logged",
    entityType: "ai_decision",
    entityId: decisionId,
    facilityId: data.facilityId,
    medicineName: data.medicineName,
    after: data,
    actorId: request.auth.uid,
  });

  return { ok: true, decisionId };
});

/**
 * 1c. Firestore -> BigQuery mirrors for analytics, transfer decisions, and audit.
 */
exports.mirrorRequestToBigQuery = onDocumentWritten("requests/{requestId}", async (event) => {
  const change = event.data;
  const before = change.before.exists ? change.before.data() : null;
  const after = change.after.exists ? change.after.data() : null;
  const requestId = event.params.requestId;
  const rowData = after || before || {};
  const action = !before && after ? "created" : before && after ? "updated" : "deleted";

  await insertBigQuery("transfer_requests", {
    request_id: requestId,
    facility_id: rowData.facilityId || null,
    medicine_name: rowData.medicineName || null,
    request_type: rowData.type || null,
    quantity: Number(rowData.quantity || 0),
    status: after ? rowData.status || null : "deleted",
    request_date: toIsoTimestamp(rowData.requestDate),
    notes: rowData.notes || null,
    captured_at: new Date().toISOString(),
    payload_json: safeJson(rowData),
  }, "mirror_request");

  await auditEvent({
    eventId: `request_${requestId}_${Date.now()}`,
    action: `request_${action}`,
    entityType: "request",
    entityId: requestId,
    before,
    after,
    facilityId: rowData.facilityId,
    medicineName: rowData.medicineName,
  });

  if (after?.notes && String(after.notes).toLowerCase().includes("ai predicted")) {
    await insertBigQuery("ai_decisions", {
      decision_id: `request_${requestId}_${Date.now()}`,
      occurred_at: new Date().toISOString(),
      facility_id: after.facilityId || null,
      medicine_name: after.medicineName || null,
      decision_type: after.type === "surplus" ? "redistribution_recommendation" : "restock_recommendation",
      model: "mediflow_stock_analysis",
      prediction: null,
      confidence: null,
      recommendation: after.type || null,
      reasoning: after.notes || null,
      period_days: null,
      input_json: null,
      output_json: safeJson(after),
    }, "mirror_ai_request");
  }
});

exports.mirrorInventoryToBigQuery = onDocumentWritten("inventory/{facilityId}/medicines/{medicineId}", async (event) => {
  const change = event.data;
  const before = change.before.exists ? change.before.data() : null;
  const after = change.after.exists ? change.after.data() : null;
  const data = after || before || {};
  const facilityId = event.params.facilityId;
  const medicineId = event.params.medicineId;
  const initial = Number(data.initialQuantity || 0);
  const remaining = Number(data.remainingQuantity || 0);
  const action = !before && after ? "created" : before && after ? "updated" : "deleted";

  await insertBigQuery("inventory_snapshots", {
    snapshot_id: `${facilityId}_${medicineId}_${Date.now()}`,
    facility_id: facilityId,
    medicine_id: medicineId,
    medicine_name: data.medicineName || null,
    batch_id: data.batchId || null,
    initial_quantity: initial,
    remaining_quantity: remaining,
    unit: data.unit || null,
    expiry_date: toBigQueryDate(data.expiryDate),
    arrival_date: toBigQueryDate(data.arrivalDate),
    stock_pct: initial > 0 ? remaining / initial : null,
    status: after ? stockStatus(data) : "deleted",
    captured_at: new Date().toISOString(),
    payload_json: safeJson(data),
  }, "mirror_inventory");

  await auditEvent({
    eventId: `inventory_${facilityId}_${medicineId}_${Date.now()}`,
    action: `inventory_${action}`,
    entityType: "inventory",
    entityId: medicineId,
    before,
    after,
    facilityId,
    medicineName: data.medicineName,
  });
});

exports.mirrorUsageLogToBigQuery = onDocumentWritten("daily_usage_logs/{facilityId}/logs/{logId}", async (event) => {
  const change = event.data;
  const before = change.before.exists ? change.before.data() : null;
  const after = change.after.exists ? change.after.data() : null;
  const data = after || before || {};
  const facilityId = event.params.facilityId;
  const logId = event.params.logId;
  const medicines = Array.isArray(data.medicines) ? data.medicines : [];
  const action = !before && after ? "created" : before && after ? "updated" : "deleted";

  await insertBigQuery("usage_analytics", medicines.map((medicine, index) => ({
    usage_id: `${facilityId}_${logId}_${index}_${Date.now()}`,
    facility_id: facilityId,
    log_id: logId,
    usage_date: toBigQueryDate(data.date),
    medicine_name: medicine.medicineName || null,
    units_distributed: Number(medicine.unitsDistributed || 0),
    total_patients: Number(data.totalPatients || 0),
    captured_at: new Date().toISOString(),
    payload_json: safeJson(data),
  })), "mirror_usage_log");

  await auditEvent({
    eventId: `usage_${facilityId}_${logId}_${Date.now()}`,
    action: `usage_log_${action}`,
    entityType: "daily_usage_log",
    entityId: logId,
    before,
    after,
    facilityId,
  });
});

/**
 * Replays BigQuery writes that exhausted their immediate retry attempts.
 * The dead-letter documents remain available for operational investigation.
 */
exports.retryFailedBigQueryInsertions = onSchedule("every 5 minutes", async () => {
  await bigQueryRecovery.recoverPending();
});

/**
 * 2. checkLowStock() - Scheduled daily CRON
 * Scans all facilities and creates alerts.
 */
exports.checkLowStock = onSchedule("every 24 hours", async () => {
  const db = admin.firestore();
  const facilities = await db.collection("facilities").get();

  for (const facilityDoc of facilities.docs) {
    const stocks = await db.collection("facilities")
      .doc(facilityDoc.id)
      .collection("stocks")
      .where("qtyRemaining", "<=", "reorderLevel") // Note: Firestore doesn't support field-to-field comparison natively, so we fetch and filter
      .get();

    for (const stockDoc of stocks.docs) {
      const stock = stockDoc.data();
      if (stock.qtyRemaining <= stock.reorderLevel) {
        // Create an alert document
        await db.collection("alerts").add({
          facilityId: facilityDoc.id,
          facilityName: facilityDoc.data().name,
          stockId: stockDoc.id,
          medicineName: stock.medicineName,
          qtyRemaining: stock.qtyRemaining,
          reorderLevel: stock.reorderLevel,
          type: "low_stock",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false
        });

        // Trigger FCM Notification (Assuming FCM token is stored in the facility's user doc)
        const userQuery = await db.collection("users")
          .where("facilityId", "==", facilityDoc.id)
          .where("role", "==", "facility_head")
          .limit(1)
          .get();

        if (!userQuery.empty) {
          const user = userQuery.docs[0].data();
          if (user.fcmToken) {
            await admin.messaging().send({
              token: user.fcmToken,
              notification: {
                title: "Low Stock Alert",
                body: `${stock.medicineName} is below reorder level (${stock.qtyRemaining} left).`
              }
            });
          }
        }
      }
    }
  }
  return null;
});

/**
 * 3. autoRedistribute(requestId)
 * Atomic stock transfer when a request is approved.
 */
exports.onIndentApproved = onDocumentUpdated("requests/{requestId}", async (event) => {
  if (!event || !event.data || !event.data.after || !event.data.after.exists) return;

  const beforeSnap = event.data.before;
  const afterSnap = event.data.after;

  const beforeData = beforeSnap && beforeSnap.exists ? beforeSnap.data() : null;
  const afterData = afterSnap ? afterSnap.data() : null;

  if (!afterData) return;

  const beforeStatus = beforeData ? beforeData.status : null;
  const afterStatus = afterData.status;

  // Execute only when request transitions to 'approved' status
  if (beforeStatus !== "approved" && afterStatus === "approved") {
    const db = admin.firestore();
    const requestId = event.params.requestId;

    const {
      facilityId,
      fromFacilityId,
      toFacilityId,
      donorFacilityId,
      recipientFacilityId,
      medicineName,
      quantity,
      type,
    } = afterData;

    const qty = Number(quantity || 0);
    if (!medicineName || qty <= 0) return;

    const sourceFacility = fromFacilityId || donorFacilityId || null;
    const destFacility = toFacilityId || recipientFacilityId || null;

    // Case 1: Inter-facility redistribution transfer (both donor and recipient specified)
    if (sourceFacility && destFacility) {
      const sourceMedId = medicineName.toLowerCase().replaceAll(" ", "_");
      const sourceRef = db
        .collection("inventory")
        .doc(sourceFacility)
        .collection("medicines")
        .doc(sourceMedId);

      const destMedId = medicineName.toLowerCase().replaceAll(" ", "_");
      const destRef = db
        .collection("inventory")
        .doc(destFacility)
        .collection("medicines")
        .doc(destMedId);

      try {
        await db.runTransaction(async (transaction) => {
          const sourceDoc = await transaction.get(sourceRef);
          if (!sourceDoc.exists) {
            throw new Error(
              `Source stock for ${medicineName} at ${sourceFacility} not found`
            );
          }
          const currentSourceQty = Number(sourceDoc.data()?.remainingQuantity || 0);
          if (currentSourceQty < qty) {
            throw new Error(
              `Insufficient stock at donor ${sourceFacility}: available ${currentSourceQty}, requested ${qty}`
            );
          }

          const destDoc = await transaction.get(destRef);

          // Decrement donor stock
          transaction.update(sourceRef, {
            remainingQuantity: currentSourceQty - qty,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Increment or initialize recipient stock
          if (destDoc.exists) {
            const currentDestQty = Number(destDoc.data()?.remainingQuantity || 0);
            transaction.update(destRef, {
              remainingQuantity: currentDestQty + qty,
              lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            });
          } else {
            transaction.set(destRef, {
              medicineName: medicineName,
              batchId: `B-${Math.floor(1000 + Math.random() * 9000)}`,
              initialQuantity: qty,
              remainingQuantity: qty,
              unit: "units",
              arrivalDate: admin.firestore.FieldValue.serverTimestamp(),
              expiryDate: admin.firestore.Timestamp.fromDate(
                new Date(Date.now() + 180 * 86400000)
              ),
              lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          transaction.update(event.data.after.ref, {
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });
        logger.log(
          `Redistribution successful: ${qty} units of ${medicineName} from ${sourceFacility} to ${destFacility}`
        );
      } catch (err) {
        logger.error(`Redistribution failed for request ${requestId}:`, err);
        await event.data.after.ref.update({
          status: "rejected",
          rejectionReason: err.message,
        });
      }
    } else if (facilityId) {
      // Case 2: Facility restock / shortage / surplus request (single target facility)
      const medId = medicineName.toLowerCase().replaceAll(" ", "_");
      const medRef = db
        .collection("inventory")
        .doc(facilityId)
        .collection("medicines")
        .doc(medId);

      try {
        await db.runTransaction(async (transaction) => {
          const medDoc = await transaction.get(medRef);

          if (type === "surplus") {
            // Surplus approved: deduct surplus from local active stock
            if (medDoc.exists) {
              const currentQty = Number(medDoc.data()?.remainingQuantity || 0);
              const newQty = Math.max(0, currentQty - qty);
              transaction.update(medRef, {
                remainingQuantity: newQty,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          } else {
            // Indent / Shortage approved: add stock to facility
            if (medDoc.exists) {
              const currentQty = Number(medDoc.data()?.remainingQuantity || 0);
              transaction.update(medRef, {
                remainingQuantity: currentQty + qty,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
              });
            } else {
              transaction.set(medRef, {
                medicineName: medicineName,
                batchId: `B-${Math.floor(1000 + Math.random() * 9000)}`,
                initialQuantity: qty,
                remainingQuantity: qty,
                unit: "units",
                arrivalDate: admin.firestore.FieldValue.serverTimestamp(),
                expiryDate: admin.firestore.Timestamp.fromDate(
                  new Date(Date.now() + 180 * 86400000)
                ),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          }

          transaction.update(event.data.after.ref, {
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });
        logger.log(
          `Stock updated for request ${requestId} at ${facilityId}: ${type || "indent"} of ${qty} ${medicineName}`
        );
      } catch (err) {
        logger.error(`Stock update failed for request ${requestId}:`, err);
      }
    }
  }
});

async function executeTool(name, args, authInfo) {
  const db = admin.firestore();
  if (name === "report_shortage" || name === "report_surplus") {
    const { facilityId, medicineName, quantity } = args;
    if (!authInfo.isAdmin && facilityId !== authInfo.userFacilityId) {
      throw new Error(`Unauthorized: Cannot request for facility ${facilityId}`);
    }
    const type = name === "report_shortage" ? "shortage" : "surplus";
    await db.collection("requests").add({
      facilityId: facilityId,
      medicineName: medicineName,
      type: type,
      quantity: Number(quantity),
      requestDate: admin.firestore.Timestamp.now(),
      status: "pending",
      notes: `AI generated ${type} report via Cloud Function`,
    });
    return { status: "success", details: `${type} reported for ${quantity} of ${medicineName}` };
  } else if (name === "check_system_inventory") {
    if (!authInfo.isAdmin) {
      const facilityDoc = await db.collection("facilities").doc(authInfo.userFacilityId).get();
      const fac = facilityDoc.data();
      const systemStock = {};
      const invSnapshot = await db.collection("inventory")
        .doc(authInfo.userFacilityId)
        .collection("medicines")
        .get();
      systemStock[fac.name || authInfo.userFacilityId] = invSnapshot.docs.map((medDoc) => {
        const item = medDoc.data();
        return {
          name: item.medicineName,
          remaining: item.remainingQuantity,
          initial: item.initialQuantity,
        };
      });
      return { status: "success", system_inventory: systemStock };
    }
    const facilitiesSnapshot = await db.collection("facilities").get();
    const systemStock = {};
    for (const doc of facilitiesSnapshot.docs) {
      const fac = doc.data();
      const facId = doc.id;
      const invSnapshot = await db.collection("inventory")
        .doc(facId)
        .collection("medicines")
        .get();
      systemStock[fac.name || facId] = invSnapshot.docs.map((medDoc) => {
        const item = medDoc.data();
        return {
          name: item.medicineName,
          remaining: item.remainingQuantity,
          initial: item.initialQuantity,
        };
      });
    }
    return { status: "success", system_inventory: systemStock };
  }
  throw new Error(`Unknown function call: ${name}`);
}

exports.getForecastSecure = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must log in');

  const db = admin.firestore();
  await getUserFacilityAndRole(request.auth, db);

  await checkRateLimit(
    request.auth.uid,
    "getForecastSecure",
    LIMITS.AI
  );

  const { medicineName, logs, daysToForecast } = request.data;
  const logSummary = logs
    .map(l => `Date: ${l.date}, Used: ${l.used}`)
    .join('\n');
  const prompt = `Forecast ${daysToForecast} days for ${medicineName}. History:\n${logSummary}\nOutput JSON: {"prediction": int, "reasoning": "string"}`;

  try {
    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
    const result = await model.generateContent(prompt);
    const responseText = result.response.text();
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    return JSON.parse(jsonMatch ? jsonMatch[0] : responseText);
  } catch (error) {
    logger.error("Gemini Error:", error);
    throw new HttpsError('internal', 'AI forecasting failed');
  }
});

exports.generateSmartAlertsSecure = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must log in');

  const db = admin.firestore();
  await getUserFacilityAndRole(request.auth, db);

  const { inventory } = request.data;
  await checkRateLimit(
    request.auth.uid,
    "generateSmartAlertsSecure",
    LIMITS.AI
  );

  const payload = inventory
    .map(i => `${i.medicineName} (Batch: ${i.batchId}): ${i.remainingQuantity}/${i.initialQuantity} units left. Expiry: ${i.expiryDate}`)
    .join('\n');

  const prompt = `Identify risks in the following inventory:\n${payload}\n\nOutput a JSON array of alerts. For each alert, determine if it's an "expiry" risk or "low_stock" risk. Include keys: type, severity, title, batchId, remainingQuantity, and either expiresInDays (for expiry) or remainingPercentage, burnRate, and depletesInDays (for low_stock). Output raw JSON array only.`;

  try {
    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
    const result = await model.generateContent(prompt);
    const responseText = result.response.text();
    const jsonMatch = responseText.match(/\[[\s\S]*\]/);
    return JSON.parse(jsonMatch ? jsonMatch[0] : responseText);
  } catch (error) {
    logger.error("Gemini Error:", error);
    throw new HttpsError('internal', 'AI alert generation failed');
  }
});

exports.getChatResponseSecure = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must log in');

  const { query, context: clientContext, role, history } = request.data;
  const db = admin.firestore();
  const authInfo = await getUserFacilityAndRole(request.auth, db);

  if (!authInfo.isAdmin && clientContext && clientContext.current_facility_id && clientContext.current_facility_id !== authInfo.userFacilityId) {
    throw new HttpsError('permission-denied', 'Unauthorized facility access in chat context');
  }
  await checkRateLimit(
    request.auth.uid,
    "getChatResponseSecure",
    LIMITS.AI
  );

  const contextStr = JSON.stringify(clientContext);

  const prompt = `Role: ${role}\nSystem Blueprint: System Name: MediFlow AI Intelligence\nArchitecture: Medical Logistics Optimization Platform\nCore Data Models:\n- Facility: {id, name, type: rural/urban, region, coordinates}\n- InventoryItem: {medicineName, batchId, remainingQuantity, initialQuantity, expiryDate, arrivalDate}\n- DailyUsageLog: {date, totalPatients, medicines: [{medicineName, unitsDistributed}]}\n- MedRequest: {id, facilityId, medicineName, quantity, status: pending/fulfilled}\nBusiness Logic:\n1. Burn Rate: Calculated as unitsDistributed / days.\n2. Shipment Strategy: Optimal split of 1yr supply into 1-3 months (Active) and the rest (Cold Storage) based on seasonal historical logs.\n3. Cold Storage: Sub-collection where excess stock is "parked" to improve inventory floor-space efficiency.\n\nCurrent Data: ${contextStr}\nUser Query: ${query}\nAnswer naturally using the blueprint and data.`;

  const genAI = getGenAI();
  const model = genAI.getGenerativeModel({
    model: "gemini-1.5-flash",
    tools: [{
      functionDeclarations: [
        {
          name: "check_system_inventory",
          description: "Checks the global inventory levels of all facilities."
        },
        {
          name: "report_shortage",
          description: "Reports a shortage of a medicine at a facility.",
          parameters: {
            type: "OBJECT",
            properties: {
              facilityId: { type: "STRING" },
              medicineName: { type: "STRING" },
              quantity: { type: "INTEGER" }
            },
            required: ["facilityId", "medicineName", "quantity"]
          }
        },
        {
          name: "report_surplus",
          description: "Reports a surplus of a medicine at a facility.",
          parameters: {
            type: "OBJECT",
            properties: {
              facilityId: { type: "STRING" },
              medicineName: { type: "STRING" },
              quantity: { type: "INTEGER" }
            },
            required: ["facilityId", "medicineName", "quantity"]
          }
        }
      ]
    }]
  });

  try {
    const formattedHistory = history.map(h => ({
      role: h.role === 'user' ? 'user' : 'model',
      parts: [{ text: h.content }]
    }));

    const chat = model.startChat({
      history: formattedHistory
    });

    let result = await chat.sendMessage(prompt);

    while (result.response.functionCalls && result.response.functionCalls.length > 0) {
      const functionResponses = [];
      for (const call of result.response.functionCalls) {
        let executionResult;
        try {
          executionResult = await executeTool(call.name, call.args, authInfo);
        } catch (e) {
          executionResult = { error: e.message };
        }
        functionResponses.push({
          functionResponse: {
            name: call.name,
            response: executionResult
          }
        });
      }
      result = await chat.sendMessage(functionResponses);
    }

    return result.response.text();
  } catch (error) {
    logger.error("Chat Error:", error);
    throw new HttpsError('internal', 'AI chat failed');
  }
});

exports.callGeminiSecure = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must log in');

  const db = admin.firestore();
  await getUserFacilityAndRole(request.auth, db);

  await checkRateLimit(
    request.auth.uid,
    "callGeminiSecure",
    LIMITS.AI
  );

  const { prompt, imageBase64, imageMimeType } = request.data;
  try {
    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

    let content;
    if (imageBase64) {
      content = [
        prompt,
        {
          inlineData: {
            data: imageBase64,
            mimeType: imageMimeType || "image/jpeg"
          }
        }
      ];
    } else {
      content = [prompt];
    }

    const result = await model.generateContent(content);
    return { text: result.response.text() };
  } catch (error) {
    logger.error("Gemini callGeminiSecure Error:", error);
    throw new HttpsError('internal', 'AI generation failed');
  }
});

const cspReportLastSeen = new Map();
const CSP_REPORT_MAX_BODY_BYTES = 10 * 1024; // 10KB
const CSP_REPORT_MIN_INTERVAL_MS = 5000; // 1 report per IP per 5s
const CSP_REPORT_MAP_MAX_SIZE = 5000; // hard cap to bound memory

function getClientIp(req) {
  // Cloud Run / GFE APPENDS the real client IP as the LAST entry in
  // X-Forwarded-For; every entry before that can be spoofed by the client.
  const xff = req.headers["x-forwarded-for"];
  if (xff) {
    const parts = xff.split(",").map((p) => p.trim()).filter(Boolean);
    if (parts.length > 0) return parts[parts.length - 1];
  }
  return req.ip || "unknown";
}

function pruneCspReportMap(now) {
  // Periodic sweep: drop stale entries, and if we're still oversized
  // (e.g. distinct-IP flood), drop the oldest entries outright.
  for (const [ip, ts] of cspReportLastSeen) {
    if (now - ts >= CSP_REPORT_MIN_INTERVAL_MS) {
      cspReportLastSeen.delete(ip);
    }
  }
  if (cspReportLastSeen.size > CSP_REPORT_MAP_MAX_SIZE) {
    const excess = cspReportLastSeen.size - CSP_REPORT_MAP_MAX_SIZE;
    const oldestKeys = Array.from(cspReportLastSeen.keys()).slice(0, excess);
    for (const key of oldestKeys) {
      cspReportLastSeen.delete(key);
    }
  }
}

exports.cspReport = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const contentLength = Number(req.headers["content-length"] || 0);
  if (contentLength > CSP_REPORT_MAX_BODY_BYTES) {
    res.status(413).send("Payload Too Large");
    return;
  }

  const ip = getClientIp(req);
  const now = Date.now();

  if (cspReportLastSeen.size > CSP_REPORT_MAP_MAX_SIZE) {
    pruneCspReportMap(now);
  }

  const lastSeen = cspReportLastSeen.get(ip);
  if (lastSeen && now - lastSeen < CSP_REPORT_MIN_INTERVAL_MS) {
    res.status(429).send("Too Many Requests");
    return;
  }
  cspReportLastSeen.set(ip, now);

  logger.warn("CSP Violation Report", { report: req.body });
  res.status(204).send();
});
