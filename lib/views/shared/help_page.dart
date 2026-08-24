import 'package:flutter/material.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';

class HelpPage extends StatelessWidget {
  final String role;
  const HelpPage({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = role == 'admin';
    final colors = context.mediTheme;

    return Scaffold(
      backgroundColor: colors.background,
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
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? 'Manage logistics and optimize redistribution across all facilities.'
                  : 'Track inventory, predict demand with AI, and request supplies.',
              style: TextStyle(
                  color: colors.textSecondary, fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 40),
            Text('How It Works',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.primary)),
            const SizedBox(height: 24),
            if (isAdmin) ...[
              _buildStep(
                  context,
                  '01',
                  'Facility Overview',
                  'Monitor real-time inventory across all facilities. Spot shortages instantly.',
                  Icons.grid_view_rounded,
                  colors),
              _buildStep(
                  context,
                  '02',
                  'Smart Routing',
                  'AI matches shortages with surpluses and generates optimal logistics paths.',
                  Icons.map_rounded,
                  colors),
              _buildStep(
                  context,
                  '03',
                  'Plan Approval',
                  'Review and approve redistribution plans to initiate transfers.',
                  Icons.check_circle_outline_rounded,
                  colors),
            ] else ...[
              _buildStep(
                  context,
                  '01',
                  'Daily Logging',
                  'Record distributed medicines. Clean data fuels the AI forecasting engine.',
                  Icons.edit_calendar_rounded,
                  colors),
              _buildStep(
                  context,
                  '02',
                  'AI Forecast',
                  'Predict future stock needs. Gemini AI analyzes your usage patterns.',
                  Icons.auto_graph_rounded,
                  colors),
              _buildStep(
                  context,
                  '03',
                  'AI Stock Analysis',
                  'AI analyzes your inventory health — flags low stock, expired & surplus medicines, and prepares restock or redistribution requests.',
                  Icons.receipt_long_rounded,
                  colors),
            ],
            const SizedBox(height: 36),
            // Tip card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: colors.warning.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.lightbulb_rounded,
                        color: colors.warning, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pro Tip',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colors.warning,
                                  fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(
                              'Check dashboard daily for alerts. AI works best with consistent logging.',
                              style: TextStyle(
                                  color: colors.textSecondary,
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
      String desc, IconData icon, MediFlowTheme colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  gradient: colors.primaryGradient,
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
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(desc,
                        style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            height: 1.5)),
                  ]),
            ),
            Icon(icon, size: 28, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
