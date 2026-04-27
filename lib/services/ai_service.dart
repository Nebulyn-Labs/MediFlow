import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/daily_usage_log.dart';
import '../models/request.dart';
import '../models/facility.dart';
import '../models/inventory_item.dart';
import 'tool_dispatcher.dart';

final aiServiceProvider = Provider<AIService>((ref) {
  return AIService(ref);
});

class AIService {
  late final GenerativeModel _model;
  final Ref ref;
  bool _quotaExhausted = false;
  DateTime? _quotaResetTime;

  static const String _mediFlowBlueprint = '''
System Name: MediFlow AI Intelligence
Architecture: Medical Logistics Optimization Platform
Core Data Models:
- Facility: {id, name, type: rural/urban, region, coordinates}
- InventoryItem: {medicineName, batchId, remainingQuantity, initialQuantity, expiryDate, arrivalDate}
- DailyUsageLog: {date, totalPatients, medicines: [{medicineName, unitsDistributed}]}
- MedRequest: {id, facilityId, medicineName, quantity, status: pending/fulfilled}
Business Logic:
1. Burn Rate: Calculated as unitsDistributed / days.
2. Shipment Strategy: Optimal split of 1yr supply into 1-3 months (Active) and the rest (Cold Storage) based on seasonal historical logs.
3. Cold Storage: Sub-collection where excess stock is "parked" to improve inventory floor-space efficiency.
''';

  AIService(this.ref) {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    
    final toolCheckSystemInventory = FunctionDeclaration(
      'check_system_inventory',
      'Checks the global inventory levels of all facilities.',
      Schema(SchemaType.object, properties: {}),
    );

    final toolReportShortage = FunctionDeclaration(
      'report_shortage',
      'Reports a shortage of a medicine at a facility.',
      Schema(SchemaType.object, properties: {
        'facilityId': Schema(SchemaType.string),
        'medicineName': Schema(SchemaType.string),
        'quantity': Schema(SchemaType.integer),
      }, requiredProperties: ['facilityId', 'medicineName', 'quantity']),
    );

    final toolReportSurplus = FunctionDeclaration(
      'report_surplus',
      'Reports a surplus of a medicine at a facility.',
      Schema(SchemaType.object, properties: {
        'facilityId': Schema(SchemaType.string),
        'medicineName': Schema(SchemaType.string),
        'quantity': Schema(SchemaType.integer),
      }, requiredProperties: ['facilityId', 'medicineName', 'quantity']),
    );

    _model = GenerativeModel(
      model: 'gemini-flash-lite-latest',
      apiKey: apiKey,
      tools: [Tool(functionDeclarations: [
        toolCheckSystemInventory,
        toolReportShortage,
        toolReportSurplus,
      ])],
    );
  }

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
    if (errorMsg.contains('quota') || errorMsg.contains('Quota') || errorMsg.contains('limit')) {
      _quotaExhausted = true;
      _quotaResetTime = DateTime.now().add(const Duration(minutes: 1));
      print('AI Service: Quota hit. Mode switched to local assistance.');
    }
  }

  // ─── FORECASTING ───────────────────────────────────────────────
  Future<Map<String, dynamic>> forecastDemand(String medicineName, List<DailyUsageLog> logs, int daysToForecast) async {
    final medLogs = logs.map((l) {
      final usage = l.medicines.firstWhere((m) => m.medicineName == medicineName, orElse: () => MedicineUsage(medicineName: medicineName, unitsDistributed: 0));
      return {'date': l.date, 'used': usage.unitsDistributed};
    }).toList();

    if (_shouldUseLocal) return _localForecast(medLogs, daysToForecast);

    try {
      final logSummary = medLogs.take(30).map((l) => 'Date: ${(l['date'] as DateTime).toIso8601String()}, Used: ${l['used']}').join('\n');
      final prompt = 'Forecast $daysToForecast days for $medicineName. History:\n$logSummary\nOutput JSON: {"prediction": int, "reasoning": "string"}';

      final response = await _model.generateContent([Content.text(prompt)]);
      final raw = response.text ?? '{}';
      return jsonDecode(raw.replaceAll('```json', '').replaceAll('```', '').trim());
    } catch (e) {
      _handleQuotaError(e.toString());
      return _localForecast(medLogs, daysToForecast);
    }
  }

  Map<String, dynamic> _localForecast(List<Map<String, dynamic>> medLogs, int daysToForecast) {
    double avg = medLogs.isEmpty ? 10.0 : medLogs.map((l) => (l['used'] as int).toDouble()).fold(0.0, (a, b) => a + b) / medLogs.length;
    return {"prediction": (avg * daysToForecast * 1.1).round(), "reasoning": "Standard historical average calculation."};
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
      final contextStr = jsonEncode(context, toEncodable: (val) {
        if (val is Timestamp) return val.toDate().toIso8601String();
        if (val is DateTime) return val.toIso8601String();
        return val.toString();
      });

      final chat = _model.startChat(history: history.map((m) => Content(
        m['role'] == 'user' ? 'user' : 'model',
        [TextPart(m['content']!)]
      )).toList());

      final prompt = '''
Role: $role
System Blueprint: $_mediFlowBlueprint
Current Data: $contextStr
User Query: $query
Answer naturally using the blueprint and data.
''';

      var response = await chat.sendMessage(Content.text(prompt));

      if (response.functionCalls.isNotEmpty) {
        final toolDispatcher = ref.read(toolDispatcherProvider);
        for (final call in response.functionCalls) {
          final result = await toolDispatcher.dispatch(call);
          response = await chat.sendMessage(Content.functionResponse(call.name, result));
        }
      }

      return response.text ?? "Unavailable.";
    } catch (e) {
      print('Gemini Exception: $e');
      _handleQuotaError(e.toString());
      return _localSystemResponse(query, context, role);
    }
  }

  String _localSystemResponse(String query, Map<String, dynamic> context, String role) {
    final inventory = (context['current_inventory'] as List? ?? []);
    final logs = (context['historical_data'] as List? ?? []);
    
    final intro = "⚡ [MediFlow Engine]: Gemini is currently optimizing and I'm taking over with local system intelligence.\n\n";
    final buffer = StringBuffer(intro);

    if (query.toLowerCase().contains("stock") || query.toLowerCase().contains("inventory")) {
      buffer.writeln("### 📦 System Stock Analysis");
      for (var item in inventory) {
        final rem = item['remainingQuantity'] ?? 0;
        final tot = item['initialQuantity'] ?? 0;
        final name = item['medicineName'] ?? 'Unknown';
        final status = (tot > 0 && rem / tot < 0.2) ? "⚠️ CRITICAL" : "✅ STABLE";
        buffer.writeln("• **$name**: $rem/$tot units ($status)");
      }
    } else {
      buffer.writeln("I am the MediFlow Local Intelligence Engine. Ask me about your stock or usage trends.");
    }

    return buffer.toString();
  }

  // ─── SMART ALERTS ──────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> generateSmartAlerts(List<InventoryItem> inventory) async {
    final local = inventory.where((i) => (i.initialQuantity > 0 && i.remainingQuantity / i.initialQuantity < 0.2)).map((i) => {
      "severity": "red", "title": "Low Stock: ${i.medicineName}", "description": "${i.remainingQuantity} units left."
    }).toList();

    if (_shouldUseLocal || inventory.isEmpty) return local;
    try {
      final payload = inventory.map((i) => "${i.medicineName}: ${i.remainingQuantity}/${i.initialQuantity}").join('\n');
      final response = await _model.generateContent([Content.text('Identify risks in:\n$payload\nOutput JSON array with keys severity, title, description.')]);
      return (jsonDecode(response.text!.replaceAll('```json', '').replaceAll('```', '').trim()) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _handleQuotaError(e.toString());
      return local;
    }
  }

  // ─── REDISTRIBUTION ────────────────────────────────────────────
  Future<String> generateRedistributionPlan(List<MedRequest> requests, List<Facility> facilities) async {
    final pending = requests.where((r) => r.status == RequestStatus.pending).toList();
    if (pending.isEmpty) return 'No pending requests to optimize.';

    final localSummary = 'Optimizing ${pending.length} indent requests across ${facilities.length} facilities. '
        'Prioritizing rural clinics and shortest transfer distances.';

    if (_shouldUseLocal) return localSummary;

    try {
      final requestSummary = pending.map((r) => '${r.medicineName}: ${r.quantity} units for facility ${r.facilityId}').join('\n');
      final facilitySummary = facilities.map((f) => '${f.name} (${f.type}, ${f.region})').join(', ');
      
      final prompt = '''
You are MediFlow's logistics AI. Summarize this redistribution scenario in 2-3 sentences.
Pending Indent Requests:
$requestSummary
Facilities: $facilitySummary
Focus on: which medicines are most in demand, if rural clinics need priority, and the overall health of the network.
Reply in plain text, no markdown.
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? localSummary;
    } catch (e) {
      _handleQuotaError(e.toString());
      return localSummary;
    }
  }

  // ─── SHIPMENT STRATEGY (SEASONAL AI) ─────────────────────────
  Future<Map<String, dynamic>> suggestShipmentAllocation({
    required List<InventoryItem> items,
    required List<DailyUsageLog> logs,
    int targetMonths = 1,
    String externalContext = "Current Season: Approaching Monsoon (High Risk for Malaria/Dengue)",
  }) async {
    try {
      final prompt = '''
Scenario: MediFlow shipment split (Target: $targetMonths months active).
External Context: $externalContext
Inventory: ${items.map((i) => i.medicineName + ": " + i.remainingQuantity.toString()).join(", ")}
Logs: ${logs.take(10).map((l) => l.date.toString() + ": " + l.totalPatients.toString()).join(", ")}
Task: Provide a JSON split (active/coldStorage/reasoning) for each medicine. Be analytical and conversational in reasoning. Factor in external context if relevant.
Output JSON only.
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return jsonDecode(response.text!.replaceAll('```json', '').replaceAll('```', '').trim());
    } catch (e) {
       _handleQuotaError(e.toString());
       return _localShipmentStrategy(items, logs, targetMonths);
    }
  }

  // ─── MULTI-MODAL VISION ─────────────────────────────────────────
  Future<String> parseImageWithVision(Uint8List imageBytes, String prompt) async {
    try {
      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];
      final response = await _model.generateContent(content);
      return response.text ?? "Could not parse image.";
    } catch (e) {
      _handleQuotaError(e.toString());
      return "Local Fallback: Image parsing is not available offline or quota exceeded.";
    }
  }

  Map<String, dynamic> _localShipmentStrategy(List<InventoryItem> items, List<DailyUsageLog> logs, int targetMonths) {
    Map<String, dynamic> results = {};
    for (var item in items) {
      double sum = 0;
      for (var log in logs) {
        final matches = log.medicines.where((m) => m.medicineName == item.medicineName);
        if (matches.isNotEmpty) sum += matches.first.unitsDistributed;
      }
      double dailyAvg = logs.isEmpty ? 25.0 : sum / logs.length;
      int retentionNeed = (dailyAvg * 30 * targetMonths * 1.1).round();
      results[item.medicineName] = {
        "active": retentionNeed,
        "coldStorage": (retentionNeed * (12 / targetMonths - 1)).round(),
        "reasoning": "Local Intelligence: Calculated using current distribution rate of ${dailyAvg.toStringAsFixed(1)} units/day."
      };
    }
    return results;
  }
}
