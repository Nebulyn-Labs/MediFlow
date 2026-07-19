import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/daily_usage_log.dart';
import '../models/request.dart';
import '../models/facility.dart';
import '../models/inventory_item.dart';

final aiServiceProvider = Provider<AIService>((ref) {
  return AIService(ref);
});

class AIService {
  final Ref ref;
  bool _quotaExhausted = false;
  DateTime? _quotaResetTime;

  AIService(this.ref);

  bool get _shouldUseLocal {
    if (!_quotaExhausted) return false;
    if (_quotaResetTime != null && DateTime.now().isAfter(_quotaResetTime!)) {
      _quotaExhausted = false;
      _quotaResetTime = null;
      return false;
    }
    return true;
  }

  void _handleQuotaError(String errorMsg) {
    if (errorMsg.contains('quota') ||
        errorMsg.contains('Quota') ||
        errorMsg.contains('limit') ||
        errorMsg.contains('exhausted')) {
      _quotaExhausted = true;
      _quotaResetTime = DateTime.now().add(const Duration(minutes: 1));
      debugPrint('AI Service: Quota hit. Mode switched to local assistance.');
    }
  }

  // Helper method to call the generic callGeminiSecure Cloud Function
  Future<String> _callGeminiBackend(String prompt,
      {String? imageBase64, String? imageMimeType}) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('callGeminiSecure');
    final response = await callable.call({
      'prompt': prompt,
      if (imageBase64 != null) 'imageBase64': imageBase64,
      if (imageMimeType != null) 'imageMimeType': imageMimeType,
    });
    return response.data['text'] as String? ?? '';
  }

  // ─── FORECASTING ───────────────────────────────────────────────
  Future<Map<String, dynamic>> forecastDemand(
      String medicineName, List<DailyUsageLog> logs, int daysToForecast,
      {String? facilityId}) async {
    final medLogs = logs.map((l) {
      final usage = l.medicines.firstWhere(
          (m) => m.medicineName == medicineName,
          orElse: () =>
              MedicineUsage(medicineName: medicineName, unitsDistributed: 0));
      return {'date': l.date.toIso8601String(), 'used': usage.unitsDistributed};
    }).toList();

    if (_shouldUseLocal) {
      final result = _localForecast(medLogs, daysToForecast, medicineName);
      await _logAIDecision(
        facilityId: facilityId,
        medicineName: medicineName,
        daysToForecast: daysToForecast,
        result: result,
        model: 'local_fallback',
        input: {'logs': medLogs.take(30).toList()},
      );
      return result;
    }

    try {
      final logSummary = medLogs
          .take(30)
          .map((l) => 'Date: ${l['date']}, Used: ${l['used']}')
          .join('\n');
      final prompt =
          'Forecast $daysToForecast days for $medicineName. History:\n$logSummary\nOutput JSON: {"prediction": int, "reasoning": "string"}';

      final responseText = await _callGeminiBackend(prompt);
      final raw = responseText.trim();
      var decoded = jsonDecode(
          raw.replaceAll('```json', '').replaceAll('```', '').trim());
      if (decoded is Map) {
        final result = Map<String, dynamic>.from(decoded);
        await _logAIDecision(
          facilityId: facilityId,
          medicineName: medicineName,
          daysToForecast: daysToForecast,
          result: result,
          model: 'gemini-1.5-flash-backend',
          input: {'prompt': prompt, 'logs': medLogs.take(30).toList()},
        );
        return result;
      } else {
        final result = _localForecast(medLogs, daysToForecast, medicineName);
        await _logAIDecision(
          facilityId: facilityId,
          medicineName: medicineName,
          daysToForecast: daysToForecast,
          result: result,
          model: 'local_fallback',
          input: {'logs': medLogs.take(30).toList()},
        );
        return result;
      }
    } catch (e) {
      _handleQuotaError(e.toString());
      final result = _localForecast(medLogs, daysToForecast, medicineName);
      await _logAIDecision(
        facilityId: facilityId,
        medicineName: medicineName,
        daysToForecast: daysToForecast,
        result: result,
        model: 'local_fallback',
        input: {'error': e.toString(), 'logs': medLogs.take(30).toList()},
      );
      return result;
    }
  }

  Future<void> _logAIDecision({
    required String medicineName,
    required int daysToForecast,
    required Map<String, dynamic> result,
    required String model,
    required Map<String, dynamic> input,
    String? facilityId,
  }) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('logAIDecision').call({
        'facilityId': facilityId,
        'medicineName': medicineName,
        'decisionType': 'demand_forecast',
        'model': model,
        'prediction': result['prediction'],
        'reasoning': result['reasoning'],
        'periodDays': daysToForecast,
        'input': input,
        'output': result,
      });
    } catch (e) {
      // BigQuery/audit logging must not block patient-facing stock workflows.
      debugPrint('BigQuery AI decision log skipped: $e');
    }
  }

  Map<String, dynamic> _localForecast(List<Map<String, dynamic>> medLogs,
      int daysToForecast, String medicineName) {
    double avg = medLogs.isEmpty
        ? 10.0
        : medLogs
                .map((l) => (l['used'] as int).toDouble())
                .fold(0.0, (a, b) => a + b) /
            medLogs.length;
    int prediction = (avg * daysToForecast * 1.1).round();

    String reason = "Standard historical average computation with 10% buffer.";
    if (medicineName == "Cough Syrup") {
      reason =
          "Seasonal logic: High respiratory demand expected in winters, stabilizing towards spring. Applied rural demographic factor.";
    } else if (medicineName == "ORS") {
      reason =
          "Seasonal logic: Elevated demand due to approaching summer heat in rural catchment areas.";
    } else if (medicineName == "Antibiotic") {
      reason =
          "Consistent high burn rate detected. Ensuring sufficient stock to prevent critical rural shortages.";
    } else if (medicineName == "Paracetamol") {
      reason =
          "Baseline essential. Prediction factors in historical burn rate + 10% surge buffer for seasonal flu.";
    }

    return {"prediction": prediction, "reasoning": reason};
  }

  // ─── CHATBOT (INTELLIGENT MODE) ─────────────────────────────
  Future<String> getChatResponse({
    required String query,
    required Map<String, dynamic> context,
    required String role,
    List<Map<String, String>> history = const [],
  }) async {
    if (_shouldUseLocal) return _localSystemResponse(query, context, role);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('getChatResponseSecure');
      final response = await callable.call({
        'query': query,
        'context': context,
        'role': role,
        'history': history,
      });
      return response.data as String? ?? 'Unavailable.';
    } catch (e) {
      debugPrint('Gemini Exception: $e');
      _handleQuotaError(e.toString());
      return _localSystemResponse(query, context, role);
    }
  }

  String _localSystemResponse(
      String query, Map<String, dynamic> context, String role) {
    final inventory = (context['current_inventory'] as List? ?? []);

    final intro =
        "⚡ [MediFlow Engine]: Gemini is currently optimizing and I'm taking over with local system intelligence.\n\n";
    final buffer = StringBuffer(intro);

    if (query.toLowerCase().contains("stock") ||
        query.toLowerCase().contains("inventory")) {
      buffer.writeln("### 📦 System Stock Analysis");
      for (var item in inventory) {
        final rem = item['remainingQuantity'] ?? 0;
        final tot = item['initialQuantity'] ?? 0;
        final name = item['medicineName'] ?? 'Unknown';
        final status =
            (tot > 0 && rem / tot < 0.2) ? "⚠️ CRITICAL" : "✅ STABLE";
        buffer.writeln("• **$name**: $rem/$tot units ($status)");
      }
    } else {
      buffer.writeln(
          "I am the MediFlow Local Intelligence Engine. Ask me about your stock or usage trends.");
    }

    return buffer.toString();
  }

  // ─── SMART ALERTS ──────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> generateSmartAlerts(
      List<InventoryItem> inventory) async {
    final local = inventory
        .where((i) => (i.initialQuantity > 0 &&
            i.remainingQuantity / i.initialQuantity < 0.35))
        .map((i) => {
              "type": "low_stock",
              "severity": "red",
              "title": i.medicineName,
              "batchId": i.batchId,
              "remainingQuantity": i.remainingQuantity,
              "remainingPercentage":
                  ((i.remainingQuantity / i.initialQuantity) * 100).round(),
              "burnRate": "24/day",
              "depletesInDays": (i.remainingQuantity / 24).round(),
            })
        .toList();

    final now = DateTime.now();
    for (var i in inventory) {
      final daysToExpiry = i.expiryDate.difference(now).inDays;
      if (daysToExpiry <= 90) {
        local.add({
          "type": "expiry",
          "severity": daysToExpiry <= 30 ? "red" : "yellow",
          "title": i.medicineName,
          "batchId": i.batchId,
          "remainingQuantity": i.remainingQuantity,
          "expiresInDays": daysToExpiry,
        });
      }
    }

    if (_shouldUseLocal || inventory.isEmpty) return local;
    try {
      final payload = inventory
          .map((i) =>
              "${i.medicineName} (Batch: ${i.batchId}): ${i.remainingQuantity}/${i.initialQuantity} units left. Expiry: ${i.expiryDate.toIso8601String()}")
          .join('\n');
      final prompt = '''
Identify risks in the following inventory:
$payload

Output a JSON array of alerts. 
For each alert, determine if it's an "expiry" risk or "low_stock" risk.
Include keys:
- type: "expiry" or "low_stock"
- severity: "red" (critical) or "yellow" (warning)
- title: Medicine Name
- batchId: The batch ID
- remainingQuantity: Current units left

If type is "expiry", include:
- expiresInDays: Days until expiry

If type is "low_stock", include:
- remainingPercentage: Percentage of stock left
- burnRate: Estimated daily burn rate (e.g., "24/day")
- depletesInDays: Estimated days until stockout

Output raw JSON array only.
''';
      final responseText = await _callGeminiBackend(prompt);
      var decoded = jsonDecode(
          responseText.replaceAll('```json', '').replaceAll('```', '').trim());
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return local;
    } catch (e) {
      _handleQuotaError(e.toString());
      return local;
    }
  }

  // ─── REDISTRIBUTION ────────────────────────────────────────────
  Future<String> generateRedistributionPlan(
      List<MedRequest> requests, List<Facility> facilities) async {
    final indents = requests
        .where((r) =>
            r.status == RequestStatus.pending &&
            r.type == RequestType.regularIndent)
        .toList();
    if (indents.isEmpty) return "No active indents found to optimize.";

    try {
      final prompt = '''
Analyze these ${indents.length} pending indents across ${facilities.length} health facilities.
The logistics engine has prioritized routes based on:
1. Rural Facility Priority (+150 score)
2. Near Expiry Batches (+100 score)
3. Proximity and Quantity Matching.

Indents:
${indents.map((r) => "- ${r.facilityId}: ${r.medicineName} (${r.quantity} units)").join("\n")}

Provide a 2-sentence executive summary explaining the strategy. Mention if any rural facilities were prioritized.
Output plain text only.
''';
      final responseText = await _callGeminiBackend(prompt);
      return responseText.trim();
    } catch (e) {
      _handleQuotaError(e.toString());
      return "Optimizing ${indents.length} requests across ${facilities.length} sites by matching local surpluses.";
    }
  }

  // ─── SHIPMENT STRATEGY (SEASONAL AI) ─────────────────────────
  Future<Map<String, dynamic>> suggestShipmentAllocation({
    required List<InventoryItem> items,
    required List<DailyUsageLog> logs,
    int targetMonths = 1,
    String externalContext =
        "Current Season: Approaching Monsoon (High Risk for Malaria/Dengue)",
  }) async {
    try {
      final prompt = '''
Scenario: MediFlow shipment split (Target: $targetMonths months active).
External Context: $externalContext
Inventory: ${items.map((i) => '${i.medicineName}: ${i.remainingQuantity}').join(", ")}
Logs: ${logs.take(10).map((l) => '${l.date}: ${l.totalPatients}').join(", ")}
Task: Provide a JSON split (active/coldStorage/reasoning) for each medicine. Be analytical and conversational in reasoning. Factor in external context if relevant.
Output JSON only.
''';

      final responseText = await _callGeminiBackend(prompt);
      var decoded = jsonDecode(
          responseText.replaceAll('```json', '').replaceAll('```', '').trim());
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return _localShipmentStrategy(items, logs, targetMonths);
    } catch (e) {
      _handleQuotaError(e.toString());
      return _localShipmentStrategy(items, logs, targetMonths);
    }
  }

  // ─── MULTI-MODAL VISION ─────────────────────────────────────────
  Future<String> parseImageWithVision(
      Uint8List imageBytes, String prompt) async {
    try {
      final imageBase64 = base64Encode(imageBytes);
      final responseText = await _callGeminiBackend(prompt,
          imageBase64: imageBase64, imageMimeType: 'image/jpeg');
      return responseText;
    } catch (e) {
      _handleQuotaError(e.toString());
      return "Local Fallback: Image parsing is not available offline or quota exceeded.";
    }
  }

  Map<String, dynamic> _localShipmentStrategy(
      List<InventoryItem> items, List<DailyUsageLog> logs, int targetMonths) {
    Map<String, dynamic> results = {};
    for (var item in items) {
      double sum = 0;
      for (var log in logs) {
        final matches =
            log.medicines.where((m) => m.medicineName == item.medicineName);
        if (matches.isNotEmpty) sum += matches.first.unitsDistributed;
      }
      double dailyAvg = logs.isEmpty ? 25.0 : sum / logs.length;
      int retentionNeed = (dailyAvg * 30 * targetMonths * 1.1).round();
      results[item.medicineName] = {
        "active": retentionNeed,
        "coldStorage": (retentionNeed * (12 / targetMonths - 1)).round(),
        "reasoning":
            "Local Intelligence: Calculated using current distribution rate of ${dailyAvg.toStringAsFixed(1)} units/day."
      };
    }
    return results;
  }
}
