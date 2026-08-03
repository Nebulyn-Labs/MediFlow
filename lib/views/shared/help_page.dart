import 'package:flutter/material.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class HelpPage extends StatelessWidget {
  final String role;
  const HelpPage({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = role == 'admin';

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: Text(isAdmin ? 'CMS Admin Help' : 'Facility Help')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              isAdmin
                  ? 'Central Management System'
                  : 'MediFlow Facility Portal',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: MediColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? 'Manage logistics and optimize redistribution across all facilities.'
                  : 'Track inventory, predict demand with AI, and request supplies.',
              style: const TextStyle(
                  color: MediColors.textSecondary, fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 40),
            const Text('How It Works',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: MediColors.primary)),
            const SizedBox(height: 24),
            if (isAdmin) ...[
              _buildStep(
                  context,
                  '01',
                  'Facility Overview',
                  'Monitor real-time inventory across all facilities. Spot shortages instantly.',
                  Icons.grid_view_rounded),
              _buildStep(
                  context,
                  '02',
                  'Smart Routing',
                  'AI matches shortages with surpluses and generates optimal logistics paths.',
                  Icons.map_rounded),
              _buildStep(
                  context,
                  '03',
                  'Plan Approval',
                  'Review and approve redistribution plans to initiate transfers.',
                  Icons.check_circle_outline_rounded),
            ] else ...[
              _buildStep(
                  context,
                  '01',
                  'Daily Logging',
                  'Record distributed medicines. Clean data fuels the AI forecasting engine.',
                  Icons.edit_calendar_rounded),
              _buildStep(
                  context,
                  '02',
                  'AI Forecast',
                  'Predict future stock needs. Gemini AI analyzes your usage patterns.',
                  Icons.auto_graph_rounded),
              _buildStep(
                  context,
                  '03',
                  'AI Stock Analysis',
                  'AI analyzes your inventory health — flags low stock, expired & surplus medicines, and prepares restock or redistribution requests.',
                  Icons.receipt_long_rounded),
            ],
            const SizedBox(height: 36),
            // Tip card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: MediColors.warning.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: MediColors.warning.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: MediColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.lightbulb_rounded,
                        color: MediColors.warning, size: 22),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pro Tip',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: MediColors.warning,
                                  fontSize: 14)),
                          SizedBox(height: 4),
                          Text(
                              'Check dashboard daily for alerts. AI works best with consistent logging.',
                              style: TextStyle(
                                  color: MediColors.textSecondary,
                                  fontSize: 13)),
                        ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, String number, String title,
      String desc, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MediColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MediColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  gradient: MediColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14)),
              child: Center(
                  child: Text(number,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 16))),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: MediColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(desc,
                        style: const TextStyle(
                            color: MediColors.textSecondary,
                            fontSize: 13,
                            height: 1.5)),
                  ]),
            ),
            Icon(icon, size: 28, color: MediColors.textMuted),
          ],
        ),
      ),
    );
  }
}
