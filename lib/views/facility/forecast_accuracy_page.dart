import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/forecast_evaluation.dart';
import '../../services/firebase_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class ForecastAccuracyPage extends ConsumerStatefulWidget {
  final String facilityId;

  const ForecastAccuracyPage({super.key, required this.facilityId});

  @override
  ConsumerState<ForecastAccuracyPage> createState() =>
      _ForecastAccuracyPageState();
}

class _ForecastAccuracyPageState extends ConsumerState<ForecastAccuracyPage> {
  String _selectedMedicine = 'All';

  @override
  Widget build(BuildContext context) {
    final stream = ref
        .watch(firebaseServiceProvider)
        .streamForecastEvaluations(widget.facilityId);

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: const Text('Forecast Accuracy Dashboard'),
      ),
      body: StreamBuilder<List<ForecastEvaluation>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final evals = snapshot.data ?? [];
          if (evals.isEmpty) {
            return const Center(
              child: Text(
                'No forecast evaluations available yet.',
                style: TextStyle(color: MediColors.textMuted, fontSize: 16),
              ),
            );
          }

          // Get unique medicines for the dropdown filter
          final medicines = evals.map((e) => e.medicineName).toSet().toList()
            ..sort();
          final filteredEvals = _selectedMedicine == 'All'
              ? evals
              : evals
                  .where((e) => e.medicineName == _selectedMedicine)
                  .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Predicted vs Actual Consumption',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: MediColors.textPrimary)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: MediColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MediColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedMedicine,
                          dropdownColor: MediColors.surface,
                          items: [
                            const DropdownMenuItem(
                                value: 'All', child: Text('All Medicines')),
                            ...medicines.map((m) =>
                                DropdownMenuItem(value: m, child: Text(m))),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedMedicine = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildScorecards(filteredEvals),
                const SizedBox(height: 32),
                if (_selectedMedicine != 'All')
                  _buildLineChart(filteredEvals)
                else
                  const Center(
                    child: Text(
                        'Select a specific medicine to view the trend chart.',
                        style: TextStyle(color: MediColors.textSecondary)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildScorecards(List<ForecastEvaluation> evals) {
    if (evals.isEmpty) return const SizedBox.shrink();

    double totalMape = 0;
    int totalEvaluations = evals.length;
    double totalBias = 0;

    for (var e in evals) {
      totalMape += e.mape;
      totalBias += e.bias;
    }

    final avgMape = totalMape / totalEvaluations;
    final avgBias = totalBias / totalEvaluations;

    return Row(
      children: [
        Expanded(
            child: _buildCard('Average Error (MAPE)',
                '${avgMape.toStringAsFixed(1)}%', Icons.analytics)),
        const SizedBox(width: 16),
        Expanded(
            child: _buildCard(
                'Avg Bias (Units)',
                avgBias > 0
                    ? '+${avgBias.toStringAsFixed(1)} (Over)'
                    : '${avgBias.toStringAsFixed(1)} (Under)',
                Icons.trending_up)),
        const SizedBox(width: 16),
        Expanded(
            child: _buildCard('Total Evaluated', '$totalEvaluations Forecasts',
                Icons.fact_check)),
      ],
    );
  }

  Widget _buildCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MediColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MediColors.primary, size: 24),
          const SizedBox(height: 16),
          Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: MediColors.textPrimary)),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(
                  fontSize: 14, color: MediColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<ForecastEvaluation> evals) {
    // Sort ascending by date
    final sortedEvals = List<ForecastEvaluation>.from(evals)
      ..sort((a, b) => a.decisionDate.compareTo(b.decisionDate));

    if (sortedEvals.isEmpty) return const SizedBox.shrink();

    final List<FlSpot> predictedSpots = [];
    final List<FlSpot> actualSpots = [];

    for (int i = 0; i < sortedEvals.length; i++) {
      predictedSpots
          .add(FlSpot(i.toDouble(), sortedEvals[i].prediction.toDouble()));
      actualSpots
          .add(FlSpot(i.toDouble(), sortedEvals[i].actualUsage.toDouble()));
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MediColors.border),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          lineBarsData: [
            LineChartBarData(
              spots: predictedSpots,
              isCurved: true,
              color: MediColors.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
            ),
            LineChartBarData(
              spots: actualSpots,
              isCurved: true,
              color: MediColors.success,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < sortedEvals.length) {
                    final date = sortedEvals[index].decisionDate;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('${date.month}/${date.day}',
                          style: const TextStyle(
                              color: MediColors.textSecondary, fontSize: 10)),
                    );
                  }
                  return const Text('');
                },
                interval: 1,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(value.toInt().toString(),
                      style: const TextStyle(
                          color: MediColors.textSecondary, fontSize: 10));
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: MediColors.border.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              // getTooltipColor was changed to getTooltipItems
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((LineBarSpot touchedSpot) {
                  final textStyle = TextStyle(
                    color: touchedSpot.bar.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  );
                  return LineTooltipItem(
                    '${touchedSpot.barIndex == 0 ? "Predicted" : "Actual"}: ${touchedSpot.y.toInt()}',
                    textStyle,
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}
