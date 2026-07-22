import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/inventory_item.dart';
import '../../models/daily_usage_log.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class AIForecastPage extends ConsumerStatefulWidget {
  final String facilityId;
  const AIForecastPage({super.key, required this.facilityId});

  @override
  ConsumerState<AIForecastPage> createState() => _AIForecastPageState();
}

class _AIForecastPageState extends ConsumerState<AIForecastPage> {
  int _forecastDays = 30;
  String? _selectedMed;
  Map<String, dynamic>? _forecastResult;
  bool _isForecasting = false;
  List<double> _historicalData = [];
  bool _isLoadingHistory = false;

  Future<void> _loadHistoricalData(String medicineName) async {
    setState(() {
      _isLoadingHistory = true;
      _historicalData = [];
      _forecastResult = null;
    });
    try {
      final logs = await ref
          .read(firebaseServiceProvider)
          .getRecentLogs(widget.facilityId, days: 30);
      final sorted = [...logs]..sort((a, b) => a.date.compareTo(b.date));
      final data = sorted.map((log) {
        final usage = log.medicines.firstWhere(
          (m) => m.medicineName == medicineName,
          orElse: () =>
              MedicineUsage(medicineName: medicineName, unitsDistributed: 0),
        );
        return usage.unitsDistributed.toDouble();
      }).toList();
      if (mounted) {
        setState(() {
          _historicalData = data;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _generateForecast() async {
    setState(() => _isForecasting = true);
    try {
      final logs = await ref
          .read(firebaseServiceProvider)
          .getRecentLogs(widget.facilityId);
      final result = await ref.read(aiServiceProvider).forecastDemand(
          _selectedMed!, logs, _forecastDays,
          facilityId: widget.facilityId);
      if (mounted) {
        setState(() {
          _forecastResult = result;
          _isForecasting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isForecasting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Forecast failed: ${e.toString()}'),
            backgroundColor: MediColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryStream =
        ref.watch(firebaseServiceProvider).streamInventory(widget.facilityId);

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('AI Demand Forecast')),
      body: StreamBuilder<List<InventoryItem>>(
        stream: inventoryStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final inventory = snapshot.data ?? [];
          final medNames =
              inventory.map((i) => i.medicineName).toSet().toList();

          if (_selectedMed == null && medNames.isNotEmpty) {
            _selectedMed = medNames.first;
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _loadHistoricalData(_selectedMed!));
          }

          return LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 1000;

            final controls = Container(
              width: isWide ? 320 : double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: MediColors.surface,
                border: Border(
                    right: isWide
                        ? BorderSide(color: MediColors.border)
                        : BorderSide.none),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Parameters',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: MediColors.textPrimary)),
                  const SizedBox(height: 8),
                  const Text('Configure your forecast model',
                      style:
                          TextStyle(fontSize: 13, color: MediColors.textMuted)),
                  const SizedBox(height: 28),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Medicine'),
                    dropdownColor: MediColors.surfaceLight,
                    initialValue: _selectedMed,
                    style: const TextStyle(color: MediColors.textPrimary),
                    items: medNames
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedMed = v;
                        _forecastResult = null;
                      });
                      if (v != null) _loadHistoricalData(v);
                    },
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Duration'),
                    dropdownColor: MediColors.surfaceLight,
                    initialValue: _forecastDays,
                    style: const TextStyle(color: MediColors.textPrimary),
                    items: const [
                      DropdownMenuItem(
                          value: 30, child: Text('1 Month (30 Days)')),
                      DropdownMenuItem(
                          value: 90, child: Text('1 Quarter (90 Days)')),
                    ],
                    onChanged: (v) => setState(() {
                      _forecastDays = v!;
                      _forecastResult = null;
                    }),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                          gradient: MediColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12)),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent),
                        icon: _isForecasting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.auto_awesome_rounded),
                        label: const Text('Generate Forecast'),
                        onPressed: _isForecasting ? null : _generateForecast,
                      ),
                    ),
                  ),
                  if (_historicalData.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MediColors.successSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: MediColors.successBorder),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded,
                            color: MediColors.success, size: 16),
                        const SizedBox(width: 8),
                        Text('${_historicalData.length} days loaded',
                            style: const TextStyle(
                                color: MediColors.success, fontSize: 12)),
                      ]),
                    ),
                  ],
                ],
              ),
            );

            final mainContent = SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(children: [
                // Chart
                Container(
                  height: 380,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: MediColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: MediColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('Usage Trend',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: MediColors.textPrimary)),
                        const Spacer(),
                        _buildLegendDot(MediColors.info, 'Historical'),
                        if (_forecastResult != null) ...[
                          const SizedBox(width: 16),
                          _buildLegendDot(MediColors.violet, 'Forecast')
                        ],
                      ]),
                      const SizedBox(height: 20),
                      Expanded(
                          child: _isLoadingHistory
                              ? const Center(child: CircularProgressIndicator())
                              : _buildChart()),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Insight
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: MediColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: MediColors.primary.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                gradient: MediColors.primaryGradient,
                                borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.psychology_rounded,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text('AI Insight',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: MediColors.primary)),
                        ]),
                        const SizedBox(height: 16),
                        if (_forecastResult == null)
                          const Text(
                              'Run the forecaster to see AI-powered demand predictions.',
                              style: TextStyle(color: MediColors.textSecondary))
                        else ...[
                          Text(
                              'Predicted: ${_forecastResult!['prediction']} units over $_forecastDays days',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: MediColors.primary)),
                          const SizedBox(height: 8),
                          Text('${_forecastResult!['reasoning']}',
                              style: const TextStyle(
                                  color: MediColors.textSecondary,
                                  height: 1.6)),
                        ],
                      ]),
                ),
              ]),
            );

            if (isWide) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [controls, Expanded(child: mainContent)]);
            }
            return SingleChildScrollView(
                child: Column(children: [controls, mainContent]));
          });
        },
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(fontSize: 12, color: MediColors.textMuted)),
    ]);
  }

  Widget _buildChart() {
    final historicalSpots = _historicalData.isNotEmpty
        ? _historicalData
            .asMap()
            .entries
            .map((e) => FlSpot(e.key.toDouble(), e.value))
            .toList()
        : <FlSpot>[FlSpot(0, 0)];

    List<FlSpot> forecastSpots = [];
    if (_forecastResult != null && _historicalData.isNotEmpty) {
      final lastX = _historicalData.length - 1.0;
      final lastY = _historicalData.last;
      final predTotal = (_forecastResult!['prediction'] as num).toDouble();
      final projectedEndY = predTotal / _forecastDays;
      forecastSpots = [
        FlSpot(lastX, lastY),
        FlSpot(lastX + (_forecastDays / 3.0), projectedEndY * 0.8),
        FlSpot(lastX + (_forecastDays / 1.5), projectedEndY),
      ];
    }

    final maxY = [
          if (_historicalData.isNotEmpty)
            _historicalData.reduce((a, b) => a > b ? a : b),
          if (forecastSpots.isNotEmpty)
            forecastSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b),
          1.0,
        ].reduce((a, b) => a > b ? a : b) *
        1.2;

    return LineChart(LineChartData(
      minY: 0,
      maxY: maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: MediColors.border, strokeWidth: 0.5),
      ),
      titlesData: FlTitlesData(
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
              style:
                  const TextStyle(fontSize: 10, color: MediColors.textMuted)),
        )),
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (v, _) {
            final idx = v.toInt();
            if (_historicalData.isEmpty) return const Text('');
            if (idx == 0) {
              return const Text('D-30',
                  style: TextStyle(fontSize: 10, color: MediColors.textMuted));
            }
            if (idx == _historicalData.length - 1) {
              return const Text('Today',
                  style: TextStyle(fontSize: 10, color: MediColors.textMuted));
            }
            return const Text('');
          },
        )),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: historicalSpots,
          isCurved: true,
          color: MediColors.info,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: MediColors.info.withValues(alpha: 0.08)),
        ),
        if (forecastSpots.isNotEmpty)
          LineChartBarData(
            spots: forecastSpots,
            isCurved: true,
            color: MediColors.violet,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
      ],
    ));
  }
}
