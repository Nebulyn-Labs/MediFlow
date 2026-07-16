import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({required this.text, required this.isUser, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class ChatService {
  GenerativeModel? _model;
  GenerativeModel? _fallbackModel;
  ChatSession? _chat;
  ChatSession? _fallbackChat;
  bool _usingFallback = false;
  bool _offlineMode = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cached data for offline responses
  Map<String, dynamic>? _facilityData;
  List<Map<String, dynamic>> _inventoryData = [];
  List<Map<String, dynamic>> _usageLogs = [];
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _allFacilities = [];

  static const String _primaryModelName = 'gemini-2.0-flash';
  static const String _fallbackModelName = 'gemini-2.0-flash-lite';

  ChatService() {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isNotEmpty) {
      _model = GenerativeModel(
        model: _primaryModelName,
        apiKey: apiKey,
      );
      _fallbackModel = GenerativeModel(
        model: _fallbackModelName,
        apiKey: apiKey,
      );
    }
  }

  bool get isAvailable => _model != null || _offlineMode;

  String get activeModelName => _offlineMode
      ? 'Offline Analytics'
      : (_usingFallback ? _fallbackModelName : _primaryModelName);

  Future<void> _loadData(String? facilityId) async {
    try {
      if (facilityId != null) {
        final facilityDoc =
            await _firestore.collection('facilities').doc(facilityId).get();
        if (facilityDoc.exists) {
          _facilityData = facilityDoc.data();
        }

        final invSnapshot = await _firestore
            .collection('inventory')
            .doc(facilityId)
            .collection('medicines')
            .get();
        _inventoryData = invSnapshot.docs.map((doc) => doc.data()).toList();

        final logsSnapshot = await _firestore
            .collection('daily_usage_logs')
            .doc(facilityId)
            .collection('logs')
            .orderBy('date', descending: true)
            .limit(7)
            .get();
        _usageLogs = logsSnapshot.docs.map((doc) => doc.data()).toList();
      } else {
        final facilitiesSnapshot =
            await _firestore.collection('facilities').get();
        _allFacilities = facilitiesSnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        // Load inventory for all facilities
        for (var fDoc in facilitiesSnapshot.docs) {
          final invSnap = await _firestore
              .collection('inventory')
              .doc(fDoc.id)
              .collection('medicines')
              .get();
          for (var doc in invSnap.docs) {
            final d = doc.data();
            d['facilityId'] = fDoc.id;
            d['facilityName'] = fDoc.data()['name'];
            _inventoryData.add(d);
          }
        }
      }

      final requestsSnapshot = await _firestore.collection('requests').get();
      _requests = requestsSnapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('ChatService: Error loading data: $e');
    }
  }

  Future<String> _buildContext(String? facilityId) async {
    String context = '''
You are MediFlow AI Assistant — a helpful, concise, and professional healthcare supply chain analyst.
You help facility heads and CMS admins understand their inventory, usage patterns, and medicine logistics.
Keep responses short (2-4 sentences max unless asked for detail). Use bullet points for lists.
Be conversational and friendly. Use emojis sparingly for warmth.
If you don't have enough data, say so honestly.

Current Date: ${DateTime.now().toIso8601String()}

''';

    try {
      if (facilityId != null) {
        if (_facilityData != null) {
          final data = _facilityData!;
          context += '''
=== FACILITY PROFILE ===
Name: ${data['name'] ?? 'Unknown'}
Type: ${data['type'] ?? 'Unknown'}
Region: ${data['region'] ?? 'Unknown'}
Location: (${data['latitude']}, ${data['longitude']})

''';
        }

        if (_inventoryData.isNotEmpty) {
          context += '=== CURRENT INVENTORY ===\n';
          for (var d in _inventoryData) {
            final remaining = d['remainingQuantity'] ?? 0;
            final initial = d['initialQuantity'] ?? 1;
            final pct = ((remaining / initial) * 100).round();
            final expiry = (d['expiryDate'] as Timestamp).toDate();
            final daysToExpiry = expiry.difference(DateTime.now()).inDays;
            context +=
                '- ${d['medicineName']}: $remaining/$initial units ($pct%) | Expires in $daysToExpiry days | Batch: ${d['batchId']}\n';
          }
          context += '\n';
        }

        if (_usageLogs.isNotEmpty) {
          context += '=== RECENT USAGE (Last 7 days) ===\n';
          for (var d in _usageLogs) {
            final date = (d['date'] as Timestamp).toDate();
            final dateStr = '${date.day}/${date.month}/${date.year}';
            final patients = d['totalPatients'] ?? 0;
            final meds = (d['medicines'] as List<dynamic>?) ?? [];
            final medSummary = meds
                .map((m) => '${m['medicineName']}:${m['unitsDistributed']}')
                .join(', ');
            context +=
                '- $dateStr | Patients: $patients | Usage: $medSummary\n';
          }
          context += '\n';
        }
      } else {
        if (_allFacilities.isNotEmpty) {
          context += '=== ALL FACILITIES ===\n';
          for (var d in _allFacilities) {
            context +=
                '- ${d['name']} (${d['type']}) | Region: ${d['region']} | ID: ${d['id']}\n';
          }
          context += '\n';
        }

        if (_inventoryData.isNotEmpty) {
          final grouped = <String, List<Map<String, dynamic>>>{};
          for (var d in _inventoryData) {
            final fname = d['facilityName'] ?? 'Unknown';
            grouped.putIfAbsent(fname, () => []).add(d);
          }
          for (var entry in grouped.entries) {
            context += '=== INVENTORY: ${entry.key} ===\n';
            for (var d in entry.value) {
              final remaining = d['remainingQuantity'] ?? 0;
              final initial = d['initialQuantity'] ?? 1;
              final pct = ((remaining / initial) * 100).round();
              context +=
                  '- ${d['medicineName']}: $remaining/$initial ($pct%)\n';
            }
            context += '\n';
          }
        }
      }

      if (_requests.isNotEmpty) {
        context += '=== PENDING REQUESTS ===\n';
        for (var d in _requests) {
          context +=
              '- ${d['medicineName']}: ${d['quantity']} units | Status: ${d['status']} | Priority: ${d['priority']}\n';
        }
        context += '\n';
      }
    } catch (e) {
      context += '\n[Note: Some data could not be loaded: $e]\n';
    }

    return context;
  }

  Future<void> startChat(String? facilityId) async {
    // Always load data first (needed for both online and offline modes)
    await _loadData(facilityId);

    if (_model == null) {
      _offlineMode = true;
      return;
    }

    final systemContext = await _buildContext(facilityId);

    final history = [
      Content.text(systemContext),
      Content.model([
        TextPart(
            'Understood! I have access to the facility data. How can I help you today? 🏥')
      ]),
    ];

    _chat = _model!.startChat(history: history);

    if (_fallbackModel != null) {
      _fallbackChat = _fallbackModel!.startChat(history: [
        Content.text(systemContext),
        Content.model([
          TextPart(
              'Understood! I have access to the facility data. How can I help you today? 🏥')
        ]),
      ]);
    }
  }

  bool _isQuotaError(String errorMessage) {
    final lower = errorMessage.toLowerCase();
    return lower.contains('quota') ||
        lower.contains('rate limit') ||
        lower.contains('resource exhausted') ||
        lower.contains('429') ||
        lower.contains('exceeded');
  }

  Future<String> sendMessage(String message) async {
    // If already in offline mode, respond locally
    if (_offlineMode) {
      return _generateOfflineResponse(message);
    }

    if (_chat == null || _model == null) {
      return _generateOfflineResponse(message);
    }

    // Try primary model
    if (!_usingFallback) {
      try {
        final response = await _chat!.sendMessage(Content.text(message));
        return response.text ??
            'I couldn\'t generate a response. Please try again.';
      } catch (e) {
        final errorStr = e.toString();
        if (_isQuotaError(errorStr)) {
          debugPrint(
              'ChatService: $_primaryModelName quota exceeded, trying $_fallbackModelName...');
          _usingFallback = true;
        } else {
          return _generateOfflineResponse(message);
        }
      }
    }

    // Try fallback model
    if (_usingFallback && _fallbackChat != null) {
      try {
        final response =
            await _fallbackChat!.sendMessage(Content.text(message));
        return response.text ??
            'I couldn\'t generate a response. Please try again.';
      } catch (e) {
        final errorStr = e.toString();
        if (_isQuotaError(errorStr)) {
          debugPrint(
              'ChatService: Both models exhausted, switching to offline mode.');
          _offlineMode = true;
          return _generateOfflineResponse(message);
        }
        return _generateOfflineResponse(message);
      }
    }

    _offlineMode = true;
    return _generateOfflineResponse(message);
  }

  // ─── Offline Intelligence Engine ───────────────────────────────────────

  String _generateOfflineResponse(String message) {
    final query = message.toLowerCase().trim();

    if (_matchesAny(query, ['hi', 'hello', 'hey', 'help', 'what can you do'])) {
      return _greetingResponse();
    }
    if (_matchesAny(query, [
      'inventory',
      'stock',
      'summary',
      'medicine',
      'medicines',
      'show inventory'
    ])) {
      return _inventorySummary();
    }
    if (_matchesAny(query,
        ['low stock', 'alert', 'alerts', 'critical', 'shortage', 'warning'])) {
      return _lowStockAlerts();
    }
    if (_matchesAny(query, [
      'usage',
      'trend',
      'trends',
      'used most',
      'consumption',
      'usage trend'
    ])) {
      return _usageTrends();
    }
    if (_matchesAny(query,
        ['request', 'requests', 'pending', 'indent', 'supply request'])) {
      return _requestsSummary();
    }
    if (_matchesAny(
        query, ['expir', 'expiry', 'expire', 'expired', 'shelf life'])) {
      return _expiryReport();
    }
    if (_matchesAny(
        query, ['forecast', 'predict', 'demand', 'next month', 'projection'])) {
      return _demandForecast();
    }
    if (_matchesAny(
        query, ['facility', 'facilities', 'clinic', 'hospital', 'center'])) {
      return _facilityInfo();
    }
    if (_matchesAny(query, ['top', 'most used', 'highest', 'popular'])) {
      return _topMedicines();
    }
    if (_matchesAny(
        query, ['redistribute', 'redistribution', 'transfer', 'rebalance'])) {
      return _redistributionAdvice();
    }

    return _generalResponse(message);
  }

  bool _matchesAny(String query, List<String> keywords) {
    return keywords.any((k) => query.contains(k));
  }

  String _greetingResponse() {
    final itemCount = _inventoryData.length;
    final logCount = _usageLogs.length;
    return '👋 Hello! I\'m MediFlow AI running in **offline analytics mode**.\n\n'
        'I have access to:\n'
        '• **$itemCount** medicine records in inventory\n'
        '• **$logCount** recent usage logs\n'
        '• **${_requests.length}** supply requests\n\n'
        'Ask me about inventory, low stock alerts, usage trends, expiry reports, or demand forecasts! 📊';
  }

  String _inventorySummary() {
    if (_inventoryData.isEmpty) {
      return '📦 No inventory data found. Please add medicines to your inventory first.';
    }

    String response = '📦 **Inventory Summary**\n\n';
    int critical = 0, warning = 0, healthy = 0;

    for (var d in _inventoryData) {
      final remaining = (d['remainingQuantity'] ?? 0) as num;
      final initial = (d['initialQuantity'] ?? 1) as num;
      final pct = initial > 0 ? ((remaining / initial) * 100).round() : 0;
      final facilityLabel =
          d['facilityName'] != null ? ' _(${d['facilityName']})_' : '';
      final status = pct <= 15 ? '🔴' : (pct <= 40 ? '🟡' : '🟢');

      if (pct <= 15) {
        critical++;
      } else if (pct <= 40) {
        warning++;
      } else {
        healthy++;
      }

      response +=
          '$status **${d['medicineName']}**$facilityLabel: $remaining/$initial units ($pct%)\n';
    }

    response +=
        '\n📊 Overall: **$critical** critical · **$warning** warning · **$healthy** healthy';
    return response;
  }

  String _lowStockAlerts() {
    if (_inventoryData.isEmpty) {
      return '⚠️ No inventory data available to check for low stock.';
    }

    final lowStock = <Map<String, dynamic>>[];
    for (var d in _inventoryData) {
      final remaining = (d['remainingQuantity'] ?? 0) as num;
      final initial = (d['initialQuantity'] ?? 1) as num;
      final pct = initial > 0 ? ((remaining / initial) * 100).round() : 0;
      if (pct <= 40) {
        lowStock.add({...d, 'pct': pct});
      }
    }

    if (lowStock.isEmpty) {
      return '✅ Great news! All medicines are above 40% stock level. No alerts at this time. 🎉';
    }

    lowStock.sort((a, b) => (a['pct'] as int).compareTo(b['pct'] as int));

    String response = '⚠️ **Low Stock Alerts** (${lowStock.length} items)\n\n';
    for (var d in lowStock) {
      final status = (d['pct'] as int) <= 15 ? '🔴 CRITICAL' : '🟡 WARNING';
      final facilityLabel =
          d['facilityName'] != null ? ' at ${d['facilityName']}' : '';
      response += '$status — **${d['medicineName']}**$facilityLabel\n'
          '   ${d['remainingQuantity']}/${d['initialQuantity']} units (${d['pct']}% remaining)\n\n';
    }

    response += '💡 _Consider creating indent requests for critical items._';
    return response;
  }

  String _usageTrends() {
    if (_usageLogs.isEmpty) {
      return '📈 No usage data available yet. Log daily usage to see trends.';
    }

    String response =
        '📈 **Usage Trends (Last ${_usageLogs.length} days)**\n\n';
    int totalPatients = 0;
    Map<String, int> medUsage = {};

    for (var d in _usageLogs) {
      final date = (d['date'] as Timestamp).toDate();
      final dateStr = '${date.day}/${date.month}';
      final patients = (d['totalPatients'] ?? 0) as int;
      totalPatients += patients;

      final meds = (d['medicines'] as List<dynamic>?) ?? [];
      String medInfo = meds.map((m) {
        final name = m['medicineName'] as String;
        final units = (m['unitsDistributed'] ?? 0) as int;
        medUsage[name] = (medUsage[name] ?? 0) + units;
        return '$name: $units';
      }).join(', ');

      response += '📅 **$dateStr** — $patients patients | $medInfo\n';
    }

    final avgPatients = (totalPatients / _usageLogs.length).round();
    response += '\n👥 Avg patients/day: **$avgPatients**\n';

    if (medUsage.isNotEmpty) {
      final sorted = medUsage.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      response +=
          '💊 Top medicine: **${sorted.first.key}** (${sorted.first.value} total units)\n';
    }

    return response;
  }

  String _requestsSummary() {
    if (_requests.isEmpty) {
      return '📋 No supply requests found in the system.';
    }

    String response = '📋 **Supply Requests** (${_requests.length} total)\n\n';
    for (var d in _requests) {
      final priority = d['priority'] ?? 'normal';
      final icon = priority == 'high' || priority == 'urgent' ? '🔴' : '🟡';
      response += '$icon **${d['medicineName']}**: ${d['quantity']} units\n'
          '   Status: ${d['status']} | Priority: $priority\n\n';
    }
    return response;
  }

  String _expiryReport() {
    if (_inventoryData.isEmpty) {
      return '📅 No inventory data to check for expiring medicines.';
    }

    final now = DateTime.now();
    final expiring = <Map<String, dynamic>>[];

    for (var d in _inventoryData) {
      if (d['expiryDate'] != null) {
        final expiry = (d['expiryDate'] as Timestamp).toDate();
        final daysLeft = expiry.difference(now).inDays;
        if (daysLeft <= 90) {
          expiring.add({...d, 'daysLeft': daysLeft});
        }
      }
    }

    if (expiring.isEmpty) {
      return '✅ No medicines expiring within 90 days. All good! 🎉';
    }

    expiring
        .sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));

    String response =
        '📅 **Expiry Report** (${expiring.length} items within 90 days)\n\n';
    for (var d in expiring) {
      final days = d['daysLeft'] as int;
      final icon = days <= 30 ? '🔴' : (days <= 60 ? '🟡' : '🟠');
      final facilityLabel =
          d['facilityName'] != null ? ' at ${d['facilityName']}' : '';
      response +=
          '$icon **${d['medicineName']}**$facilityLabel — **$days days** left\n'
          '   Remaining: ${d['remainingQuantity']} units | Batch: ${d['batchId'] ?? 'N/A'}\n\n';
    }
    return response;
  }

  String _demandForecast() {
    if (_usageLogs.isEmpty && _inventoryData.isEmpty) {
      return '🔮 Not enough data for forecasting. Log daily usage for at least 7 days.';
    }

    String response = '🔮 **30-Day Demand Forecast**\n\n';

    Map<String, List<int>> medHistory = {};
    for (var d in _usageLogs) {
      final meds = (d['medicines'] as List<dynamic>?) ?? [];
      for (var m in meds) {
        final name = m['medicineName'] as String;
        final units = (m['unitsDistributed'] ?? 0) as int;
        medHistory.putIfAbsent(name, () => []).add(units);
      }
    }

    if (medHistory.isEmpty) {
      // Estimate from inventory levels
      for (var d in _inventoryData) {
        final remaining = (d['remainingQuantity'] ?? 0) as num;
        final initial = (d['initialQuantity'] ?? 1) as num;
        final used = initial - remaining;
        final forecast = (used * 1.1).round();
        response +=
            '💊 **${d['medicineName']}**: ~$forecast units/month (estimated)\n';
      }
    } else {
      for (var entry in medHistory.entries) {
        final avg =
            entry.value.fold(0, (acc, v) => acc + v) / entry.value.length;
        final forecast30 = (avg * 30 * 1.1).round(); // 10% buffer
        final trend = entry.value.length >= 3
            ? (entry.value.last > entry.value.first
                ? '📈 Increasing'
                : '📉 Decreasing')
            : '➡️ Stable';
        response +=
            '💊 **${entry.key}**: ~**$forecast30** units/30 days | $trend\n';
      }
    }

    response +=
        '\n_Forecasts include a 10% safety buffer. Based on ${_usageLogs.length} days of data._';
    return response;
  }

  String _facilityInfo() {
    if (_facilityData != null) {
      final d = _facilityData!;
      return '🏥 **${d['name'] ?? 'Unknown Facility'}**\n\n'
          '• Type: ${d['type'] ?? 'N/A'}\n'
          '• Region: ${d['region'] ?? 'N/A'}\n'
          '• Location: (${d['latitude']}, ${d['longitude']})\n'
          '• Medicines tracked: ${_inventoryData.length}\n'
          '• Recent logs: ${_usageLogs.length} days';
    }

    if (_allFacilities.isNotEmpty) {
      String response = '🏥 **All Facilities** (${_allFacilities.length})\n\n';
      for (var d in _allFacilities) {
        response += '• **${d['name']}** (${d['type']}) — ${d['region']}\n';
      }
      return response;
    }

    return '🏥 No facility information available.';
  }

  String _topMedicines() {
    if (_inventoryData.isEmpty) {
      return '💊 No inventory data available.';
    }

    Map<String, int> medUsage = {};
    for (var d in _usageLogs) {
      final meds = (d['medicines'] as List<dynamic>?) ?? [];
      for (var m in meds) {
        final name = m['medicineName'] as String;
        final units = (m['unitsDistributed'] ?? 0) as int;
        medUsage[name] = (medUsage[name] ?? 0) + units;
      }
    }

    if (medUsage.isEmpty) {
      return '💊 No usage data yet. Log daily consumption to see top medicines.';
    }

    final sorted = medUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String response = '💊 **Most Used Medicines**\n\n';
    for (int i = 0; i < sorted.length && i < 5; i++) {
      final medal = i == 0 ? '🥇' : (i == 1 ? '🥈' : (i == 2 ? '🥉' : '▪️'));
      response +=
          '$medal **${sorted[i].key}**: ${sorted[i].value} units distributed\n';
    }
    return response;
  }

  String _redistributionAdvice() {
    if (_inventoryData.isEmpty) {
      return '🔄 No inventory data available for redistribution analysis.';
    }

    final surplus = <Map<String, dynamic>>[];
    final deficit = <Map<String, dynamic>>[];

    for (var d in _inventoryData) {
      final remaining = (d['remainingQuantity'] ?? 0) as num;
      final initial = (d['initialQuantity'] ?? 1) as num;
      final pct = initial > 0 ? ((remaining / initial) * 100).round() : 0;

      if (pct > 70) surplus.add({...d, 'pct': pct});
      if (pct <= 25) deficit.add({...d, 'pct': pct});
    }

    if (deficit.isEmpty) {
      return '✅ No critical shortages detected. Redistribution is not needed at this time.';
    }

    String response = '🔄 **Redistribution Recommendations**\n\n';
    response += '**Facilities needing supply:**\n';
    for (var d in deficit) {
      final facilityLabel = d['facilityName'] ?? '';
      response +=
          '🔴 ${d['medicineName']} $facilityLabel — ${d['pct']}% remaining\n';
    }

    if (surplus.isNotEmpty) {
      response += '\n**Potential donors:**\n';
      for (var d in surplus) {
        final facilityLabel = d['facilityName'] ?? '';
        response +=
            '🟢 ${d['medicineName']} $facilityLabel — ${d['pct']}% remaining (surplus)\n';
      }
    }

    response +=
        '\n💡 _Use AI Stock Analysis to prepare restock or redistribution requests._';
    return response;
  }

  String _generalResponse(String message) {
    return '🤖 I\'m running in **offline analytics mode** right now.\n\n'
        'I can help you with these topics:\n'
        '• 📦 **"inventory"** — Stock summary\n'
        '• ⚠️ **"alerts"** — Low stock warnings\n'
        '• 📈 **"usage trends"** — Consumption patterns\n'
        '• 📅 **"expiry"** — Expiry report\n'
        '• 🔮 **"forecast"** — Demand predictions\n'
        '• 📋 **"requests"** — Pending supply requests\n'
        '• 🔄 **"redistribute"** — Transfer suggestions\n'
        '• 💊 **"most used"** — Top medicines\n'
        '• 🏥 **"facility"** — Facility info\n\n'
        'Try asking about any of these! 💡';
  }
}
