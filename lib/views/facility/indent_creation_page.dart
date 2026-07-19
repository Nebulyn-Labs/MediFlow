import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../models/request.dart';
import '../../models/inventory_item.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class IndentCreationPage extends ConsumerStatefulWidget {
  final String facilityId;
  const IndentCreationPage({super.key, required this.facilityId});

  @override
  ConsumerState<IndentCreationPage> createState() => _IndentCreationPageState();
}

class _IndentCreationPageState extends ConsumerState<IndentCreationPage> {
  List<InventoryItem> _inventory = [];
  final Map<String, int?> _forecasts = {};
  final Map<String, String?> _reasoning = {};
  final Map<String, bool> _forecastLoading = {};
  final Map<String, TextEditingController> _controllers = {};

  bool _isLoading = true;
  bool _isSubmitting = false;
  int _selectedPeriod = 30;

  @override
  void initState() {
    super.initState();
    _fetchInventory();
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchInventory() async {
    setState(() => _isLoading = true);
    try {
      final inv = await ref
          .read(firebaseServiceProvider)
          .getInventoryOnce(widget.facilityId);
      setState(() {
        _inventory = inv;
        for (var item in _inventory) {
          _controllers[item.id] = TextEditingController(text: '0');
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching inventory: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _getAIForecast() async {
    final aiService = ref.read(aiServiceProvider);
    final firebaseService = ref.read(firebaseServiceProvider);

    // Fetch logs for forecasting
    final logs =
        await firebaseService.getRecentLogs(widget.facilityId, days: 90);

    for (var item in _inventory) {
      setState(() => _forecastLoading[item.id] = true);
      try {
        final dynamic result = await aiService.forecastDemand(
            item.medicineName, logs, _selectedPeriod,
            facilityId: widget.facilityId);
        setState(() {
          dynamic predRaw;
          dynamic reasonRaw;
          if (result != null && result is Map) {
            predRaw = result['prediction'];
            reasonRaw = result['reasoning'];
          }

          int predicted = 0;
          if (predRaw is num) {
            predicted = predRaw.toInt();
          } else if (predRaw is String) {
            predicted = double.tryParse(predRaw)?.toInt() ?? 0;
          }

          _forecasts[item.id] = predicted;
          _reasoning[item.id] =
              reasonRaw?.toString() ?? "Calculated based on demand.";

          int available = item.remainingQuantity;
          bool isExpired =
              item.expiryDate.difference(DateTime.now()).inDays < 0;
          bool expiringSoon =
              item.expiryDate.difference(DateTime.now()).inDays <= 30;
          int suggestedQty = 0;

          if (isExpired) {
            suggestedQty = (predicted * 1.2).round();
          } else if (predicted > available) {
            suggestedQty = ((predicted - available) * 1.2).round();
          } else if (predicted > 0 &&
              ((available - predicted) > (predicted * 1.5) ||
                  (available > predicted && expiringSoon))) {
            suggestedQty = available - (predicted * 1.2).round();
            if (suggestedQty < 0) suggestedQty = 0;
          } else {
            suggestedQty = 0;
          }

          _controllers[item.id]?.text = suggestedQty.toString();
        });
      } catch (e) {
        debugPrint('Forecast error for ${item.medicineName}: $e');
      } finally {
        setState(() => _forecastLoading[item.id] = false);
      }
    }
  }

  RequestType _determineRequestType(InventoryItem item, int? forecast,
      int available, bool isExpired, bool expiringSoon) {
    if (forecast == null) return RequestType.regularIndent;
    if (forecast <= 0) return RequestType.regularIndent;
    final hasSurplus = !isExpired &&
        ((available - forecast) > (forecast * 1.5) ||
            (available > forecast && expiringSoon));
    return hasSurplus ? RequestType.surplus : RequestType.regularIndent;
  }

  Future<void> _submitIndent() async {
    final itemsToSubmit = _inventory.where((item) {
      final qty = int.tryParse(_controllers[item.id]?.text ?? '0') ?? 0;
      return qty > 0;
    }).toList();

    if (itemsToSubmit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter quantities for at least one medicine.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      for (var item in itemsToSubmit) {
        final qty = int.tryParse(_controllers[item.id]?.text ?? '0') ?? 0;

        final forecast = _forecasts[item.id];
        int available = item.remainingQuantity;
        bool isExpired = item.expiryDate.difference(DateTime.now()).inDays < 0;
        bool expiringSoon =
            item.expiryDate.difference(DateTime.now()).inDays <= 30;

        final RequestType reqType = _determineRequestType(
            item, forecast, available, isExpired, expiringSoon);

        final req = MedRequest(
          id: '',
          facilityId: widget.facilityId,
          medicineName: item.medicineName,
          type: reqType,
          quantity: qty,
          requestDate: DateTime.now(),
          status: RequestStatus.draft,
          notes:
              'AI predicted usage: ${_forecasts[item.id] ?? "N/A"} for $_selectedPeriod days.',
        );
        await ref.read(firebaseServiceProvider).addRequest(req);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Requests saved as drafts! ✓')));
        context.go('/facility/${widget.facilityId}/active-indents');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Submission failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AI Stock Analysis & Requests'),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: MediColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.facilityId.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    color: MediColors.primary,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- STEP 1 ---
                  _buildSectionHeader('Step 1: Select Period'),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: MediColors.border),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _selectedPeriod,
                                dropdownColor: MediColors.surface,
                                items: [30, 60, 90].map((int value) {
                                  return DropdownMenuItem<int>(
                                    value: value,
                                    child: Text('$value days',
                                        style: const TextStyle(
                                            color: MediColors.textPrimary)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedPeriod = val);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Text(
                            '${_inventory.length} medicines in inventory',
                            style: const TextStyle(
                                color: MediColors.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // --- STEP 2 ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('Step 2: Medicine Quantities'),
                      Container(
                        decoration: BoxDecoration(
                          gradient: MediColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: FilledButton.icon(
                          onPressed: _getAIForecast,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Get AI Forecast'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        _buildTableHeader(),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _inventory.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _inventory[index];
                            return _buildTableRow(item);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- SUBMIT ---
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submitIndent,
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save as Draft',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: MediColors.textPrimary),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: MediColors.surfaceLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: const Row(
        children: [
          SizedBox(
              width: 40,
              child: Icon(Icons.check_box_outline_blank,
                  color: MediColors.textMuted, size: 20)),
          Expanded(
              flex: 3,
              child: Text('Medicine',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Available',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('AI Predicted Usage',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Status',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Request Qty',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildTableRow(InventoryItem item) {
    final isLoading = _forecastLoading[item.id] ?? false;
    final forecast = _forecasts[item.id];
    final reasoning = _reasoning[item.id];

    int available = item.remainingQuantity;
    bool isExpired = item.expiryDate.difference(DateTime.now()).inDays < 0;
    bool expiringSoon = item.expiryDate.difference(DateTime.now()).inDays <= 30;

    String status = "—";
    Color statusColor = MediColors.textMuted;
    Color statusBg = Colors.transparent;
    IconData statusIcon = Icons.help_outline;

    if (forecast != null) {
      if (isExpired) {
        status = "EXPIRED";
        statusColor = MediColors.error;
        statusBg = MediColors.error.withValues(alpha: 0.1);
        statusIcon = Icons.warning_rounded;
      } else if (forecast > available) {
        status = "LOW STOCK";
        statusColor = MediColors.error;
        statusBg = MediColors.error.withValues(alpha: 0.1);
        statusIcon = Icons.trending_down_rounded;
      } else if (forecast > 0 &&
          ((available - forecast) > (forecast * 1.5) ||
              (available > forecast && expiringSoon))) {
        status = "SURPLUS";
        statusColor = MediColors.success;
        statusBg = MediColors.success.withValues(alpha: 0.1);
        statusIcon = Icons.arrow_upward_rounded;
      } else {
        status = "OK";
        statusColor = MediColors.primary;
        statusBg = MediColors.primary.withValues(alpha: 0.1);
        statusIcon = Icons.check;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Checkbox(
                  value: true,
                  onChanged: (v) {},
                  activeColor: MediColors.surfaceLight,
                  checkColor: MediColors.textPrimary,
                  side: const BorderSide(color: MediColors.textMuted))),
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.medicineName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: MediColors.textPrimary)),
              Text(item.batchId,
                  style: const TextStyle(
                      color: MediColors.textSecondary, fontSize: 12)),
            ]),
          ),
          Expanded(
            flex: 2,
            child: Text(available.toString(),
                style: const TextStyle(
                    color: MediColors.textPrimary,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Tooltip(
                    message: reasoning ?? "AI reasoning will appear here.",
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          forecast != null ? forecast.toString() : '—',
                          style: TextStyle(
                            color: forecast != null
                                ? MediColors.primaryLight
                                : MediColors.textMuted,
                            fontWeight: forecast != null
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (forecast != null) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.info_outline,
                              color: MediColors.primaryLight, size: 14),
                        ]
                      ],
                    ),
                  ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusBg, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon, color: statusColor, size: 14),
                    const SizedBox(width: 6),
                    Text(status,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ])),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
                height: 40,
                decoration: BoxDecoration(
                    color: MediColors.surfaceLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: MediColors.border)),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _controllers[item.id],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, color: MediColors.textPrimary),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Text(item.unit,
                        style: const TextStyle(
                            color: MediColors.textMuted, fontSize: 11)),
                  ),
                ])),
          ),
        ],
      ),
    );
  }
}
