import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../services/csv_export_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import '../shared/skeleton_loaders.dart';

class WastageReportPage extends ConsumerStatefulWidget {
  final String facilityId;
  const WastageReportPage({super.key, required this.facilityId});

  @override
  ConsumerState<WastageReportPage> createState() => _WastageReportPageState();
}

class _WastageReportPageState extends ConsumerState<WastageReportPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _wastageData = [];
  int _totalExpired = 0;
  int _totalNearExpiry = 0;
  double _totalEstCost = 0.0;
  bool _isLoadingAi = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final inventory = await ref.read(firebaseServiceProvider).streamInventory(widget.facilityId).first;
      
      int totalExp = 0;
      int totalNearExp = 0;
      double totalCost = 0.0;
      
      final now = DateTime.now();
      Map<String, Map<String, dynamic>> grouped = {};

      for (var item in inventory) {
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
          
          if (!grouped.containsKey(item.medicineName)) {
            grouped[item.medicineName] = {
              'medicineName': item.medicineName,
              'expiredUnits': 0,
              'nearExpiryUnits': 0,
              'estimatedCost': 0.0,
            };
          }
          grouped[item.medicineName]!['expiredUnits'] += exp;
          grouped[item.medicineName]!['nearExpiryUnits'] += nearExp;
          // Assumed cost: $1.50 per unit
          double cost = (exp + nearExp) * 1.50;
          grouped[item.medicineName]!['estimatedCost'] += cost;
          totalCost += cost;
        }
      }

      if (mounted) {
        setState(() {
          _wastageData = grouped.values.toList();
          _totalExpired = totalExp;
          _totalNearExpiry = totalNearExp;
          _totalEstCost = totalCost;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading wastage report: $e'))
        );
      }
    }
  }

  Future<void> _fetchAiRecommendations() async {
    if (_wastageData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No wastage data to analyze.'))
      );
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
          SnackBar(content: Text('Failed to fetch recommendations: $e'))
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export.'))
      );
      return;
    }
    
    try {
      final path = await CsvExportService.exportWastageReport(
        _wastageData,
        facilityName: widget.facilityId,
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export saved to $path'))
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'))
        );
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
                        child: _buildSummaryCard(
                          title: 'Total Expired Units',
                          value: _totalExpired.toString(),
                          icon: Icons.error_outline,
                          color: MediColors.error,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Near Expiry (≤30 Days)',
                          value: _totalNearExpiry.toString(),
                          icon: Icons.warning_amber_rounded,
                          color: MediColors.warning,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Estimated Cost',
                          value: '\$${_totalEstCost.toStringAsFixed(2)}',
                          icon: Icons.attach_money,
                          color: MediColors.primary,
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
                            onPressed: _isLoadingAi ? null : _fetchAiRecommendations,
                            icon: _isLoadingAi 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('AI Recommendations'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (_wastageData.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.center,
                      child: const Column(
                        children: [
                          Icon(Icons.check_circle_outline, size: 64, color: MediColors.success),
                          SizedBox(height: 16),
                          Text('No wastage data found. Excellent inventory management!',
                              style: TextStyle(color: MediColors.textSecondary, fontSize: 16)),
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
                            DataColumn(label: Text('Expired Units'), numeric: true),
                            DataColumn(label: Text('Near Expiry'), numeric: true),
                            DataColumn(label: Text('Est. Cost'), numeric: true),
                          ],
                          rows: _wastageData.map((data) {
                            return DataRow(
                              cells: [
                                DataCell(Text(data['medicineName'].toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text(data['expiredUnits'].toString(), style: TextStyle(color: data['expiredUnits'] > 0 ? MediColors.error : null))),
                                DataCell(Text(data['nearExpiryUnits'].toString(), style: TextStyle(color: data['nearExpiryUnits'] > 0 ? MediColors.warning : null))),
                                DataCell(Text('\$${(data['estimatedCost'] as double).toStringAsFixed(2)}')),
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

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MediColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 1,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MediColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(value,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}
