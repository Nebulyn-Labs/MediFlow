import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../services/csv_export_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import '../shared/kpi_card.dart';
import '../shared/skeleton_loaders.dart';
import '../../models/inventory_item.dart';

class WastageReportPage extends ConsumerStatefulWidget {
  final String facilityId;
  const WastageReportPage({super.key, required this.facilityId});

  @override
  ConsumerState<WastageReportPage> createState() => _WastageReportPageState();
}

class _WastageReportPageState extends ConsumerState<WastageReportPage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _wastageData = [];
  int _totalExpired = 0;
  int _totalNearExpiry = 0;
  double _totalLostCost = 0.0;
  double _totalAtRiskCost = 0.0;
  bool _isLoadingAi = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final inventory = await ref
          .read(firebaseServiceProvider)
          .streamInventory(widget.facilityId)
          .first;

      final result = aggregateWastage(inventory, DateTime.now());

      if (mounted) {
        setState(() {
          _wastageData = result.data;
          _totalExpired = result.totalExpired;
          _totalNearExpiry = result.totalNearExpiry;
          _totalLostCost = result.totalLostCost;
          _totalAtRiskCost = result.totalAtRiskCost;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _fetchAiRecommendations() async {
    if (_wastageData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No wastage data to analyze.')));
      return;
    }

    setState(() => _isLoadingAi = true);
    try {
      final aiService = ref.read(aiServiceProvider);
      final response = await aiService.getWastageRecommendations(_wastageData);

      if (mounted) {
        setState(() {
          _isLoadingAi = false;
        });

        _showAiRecommendationsDialog(response);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAi = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to fetch recommendations: $e')));
      }
    }
  }

  void _showAiRecommendationsDialog(String recommendations) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: MediColors.primary),
              SizedBox(width: 8),
              Text('AI Recommendations'),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(recommendations, style: const TextStyle(height: 1.5)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportCsv() async {
    if (_wastageData.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }

    try {
      final path = await CsvExportService.exportWastageReport(
        _wastageData,
        facilityName: widget.facilityId,
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export saved to $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: const Text('Wastage Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const AlertsSkeleton()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: KpiCard.summary(
                          title: 'Expired Units',
                          value: _totalExpired.toString(),
                          icon: Icons.error_outline,
                          accent: MediColors.error,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: KpiCard.summary(
                          title: 'Est. Lost',
                          value: '\$${_totalLostCost.toStringAsFixed(2)}',
                          icon: Icons.money_off,
                          accent: MediColors.error,
                          subtitle: 'assumes \$1.50/unit',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: KpiCard.summary(
                          title: 'Near Expiry (≤30 Days)',
                          value: _totalNearExpiry.toString(),
                          icon: Icons.warning_amber_rounded,
                          accent: MediColors.warning,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: KpiCard.summary(
                          title: 'Est. At Risk',
                          value: '\$${_totalAtRiskCost.toStringAsFixed(2)}',
                          icon: Icons.attach_money,
                          accent: MediColors.warning,
                          subtitle: 'assumes \$1.50/unit',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Wastage Breakdown',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: MediColors.textPrimary),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _exportCsv,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Export CSV'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed:
                                _isLoadingAi ? null : _fetchAiRecommendations,
                            icon: _isLoadingAi
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('AI Recommendations'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 64, color: MediColors.error),
                          const SizedBox(height: 16),
                          Text('Failed to load wastage data: $_error',
                              style: const TextStyle(
                                  color: MediColors.error, fontSize: 16)),
                        ],
                      ),
                    )
                  else if (_wastageData.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.center,
                      child: const Column(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 64, color: MediColors.success),
                          SizedBox(height: 16),
                          Text(
                              'No wastage data found. Excellent inventory management!',
                              style: TextStyle(
                                  color: MediColors.textSecondary,
                                  fontSize: 16)),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: MediColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: MediColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Medicine Name')),
                            DataColumn(label: Text('Unit')),
                            DataColumn(
                                label: Text('Expired Units'), numeric: true),
                            DataColumn(
                                label: Text('Near Expiry'), numeric: true),
                            DataColumn(label: Text('Est. Lost'), numeric: true),
                            DataColumn(
                                label: Text('Est. At Risk'), numeric: true),
                          ],
                          rows: _wastageData.map((data) {
                            final expiredUnits =
                                (data['expiredUnits'] as num?)?.toInt() ?? 0;
                            final nearExpiryUnits =
                                (data['nearExpiryUnits'] as num?)?.toInt() ?? 0;
                            final lostCost =
                                (data['lostCost'] as num?)?.toDouble() ?? 0.0;
                            final atRiskCost =
                                (data['atRiskCost'] as num?)?.toDouble() ?? 0.0;

                            return DataRow(
                              cells: [
                                DataCell(Text(
                                    data['medicineName']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(data['unit']?.toString() ?? '')),
                                DataCell(Text(expiredUnits.toString(),
                                    style: TextStyle(
                                        color: expiredUnits > 0
                                            ? MediColors.error
                                            : null))),
                                DataCell(Text(nearExpiryUnits.toString(),
                                    style: TextStyle(
                                        color: nearExpiryUnits > 0
                                            ? MediColors.warning
                                            : null))),
                                DataCell(Text(
                                    '\$${lostCost.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: lostCost > 0
                                            ? MediColors.error
                                            : null))),
                                DataCell(Text(
                                    '\$${atRiskCost.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: atRiskCost > 0
                                            ? MediColors.warning
                                            : null))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class WastageAggregationResult {
  final List<Map<String, dynamic>> data;
  final int totalExpired;
  final int totalNearExpiry;
  final double totalLostCost;
  final double totalAtRiskCost;

  WastageAggregationResult(this.data, this.totalExpired, this.totalNearExpiry,
      this.totalLostCost, this.totalAtRiskCost);
}

WastageAggregationResult aggregateWastage(
    List<InventoryItem> items, DateTime now) {
  int totalExp = 0;
  int totalNearExp = 0;
  double totalLostCost = 0.0;
  double totalAtRiskCost = 0.0;

  Map<String, Map<String, dynamic>> grouped = {};

  for (var item in items) {
    final daysToExpiry = item.expiryDate.difference(now).inDays;
    int exp = 0;
    int nearExp = 0;

    if (daysToExpiry < 0) {
      exp = item.remainingQuantity;
    } else if (daysToExpiry <= 30) {
      nearExp = item.remainingQuantity;
    }

    if (exp > 0 || nearExp > 0) {
      totalExp += exp;
      totalNearExp += nearExp;

      final key = '${item.medicineName}_${item.unit}';
      if (!grouped.containsKey(key)) {
        grouped[key] = {
          'medicineName': item.medicineName,
          'unit': item.unit,
          'expiredUnits': 0,
          'nearExpiryUnits': 0,
          'estimatedCost': 0.0,
          'lostCost': 0.0,
          'atRiskCost': 0.0,
        };
      }
      grouped[key]!['expiredUnits'] =
          (grouped[key]!['expiredUnits'] as int) + exp;
      grouped[key]!['nearExpiryUnits'] =
          (grouped[key]!['nearExpiryUnits'] as int) + nearExp;

      double itemLostCost = exp * 1.50;
      double itemAtRiskCost = nearExp * 1.50;

      grouped[key]!['lostCost'] =
          (grouped[key]!['lostCost'] as double) + itemLostCost;
      grouped[key]!['atRiskCost'] =
          (grouped[key]!['atRiskCost'] as double) + itemAtRiskCost;
      grouped[key]!['estimatedCost'] =
          (grouped[key]!['estimatedCost'] as double) +
              itemLostCost +
              itemAtRiskCost;

      totalLostCost += itemLostCost;
      totalAtRiskCost += itemAtRiskCost;
    }
  }

  return WastageAggregationResult(grouped.values.toList(), totalExp,
      totalNearExp, totalLostCost, totalAtRiskCost);
}
