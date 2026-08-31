const admin = require("firebase-admin");

async function runForecastEvaluation(bigquery, logger, dataset = "mediflow_analytics") {
  logger.info("Starting forecast evaluation query against BigQuery...");
  
  const query = `
    WITH decisions AS (
      SELECT
        decision_id,
        facility_id,
        medicine_name,
        prediction,
        period_days,
        CAST(occurred_at AS DATE) AS decision_date
      FROM \`${dataset}.ai_decisions\`
      WHERE decision_type = 'demand_forecast'
        AND CAST(occurred_at AS DATE) = DATE_SUB(CURRENT_DATE(), INTERVAL period_days DAY)
    )
    SELECT
      d.decision_id,
      d.facility_id,
      d.medicine_name,
      d.prediction,
      d.period_days,
      d.decision_date,
      COALESCE((
        SELECT SUM(units_distributed)
        FROM \`${dataset}.usage_analytics\` u
        WHERE (u.facility_id = d.facility_id OR d.facility_id IS NULL)
          AND u.medicine_name = d.medicine_name
          AND u.usage_date > d.decision_date
          AND u.usage_date <= DATE_ADD(d.decision_date, INTERVAL d.period_days DAY)
      ), 0) as actual_usage
    FROM decisions d
  `;

  try {
    const [rows] = await bigquery.query({ query });
    logger.info(`Found ${rows.length} forecast decisions to evaluate.`);

    const db = admin.firestore();
    const batch = db.batch();
    
    for (const row of rows) {
      const {
        decision_id,
        facility_id,
        medicine_name,
        prediction,
        period_days,
        decision_date,
        actual_usage
      } = row;

      const pred = Number(prediction || 0);
      const actual = Number(actual_usage || 0);
      const absoluteError = Math.abs(pred - actual);
      const mape = actual > 0 ? (absoluteError / actual) * 100 : (pred > 0 ? 100 : 0);
      const bias = pred - actual; // Positive means over-predicted, negative means under-predicted

      const docRef = db.collection("forecast_evaluations").doc(decision_id);
      batch.set(docRef, {
        decisionId: decision_id,
        facilityId: facility_id || 'global',
        medicineName: medicine_name,
        prediction: pred,
        actualUsage: actual,
        absoluteError,
        mape,
        bias,
        periodDays: period_days,
        decisionDate: decision_date.value || decision_date, // BQ Date handling
        evaluatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (rows.length > 0) {
      await batch.commit();
      logger.info(`Successfully committed ${rows.length} evaluations to Firestore.`);
    }
  } catch (error) {
    logger.error("Error evaluating forecast accuracy", error);
    throw error;
  }
}

module.exports = {
  runForecastEvaluation,
};
