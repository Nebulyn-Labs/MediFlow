import 'package:flutter/material.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';

/// Visual treatment applied by [KpiCard].
enum KpiCardVariant {
  /// Flat surface tile: title beside the icon, large value underneath.
  compact,

  /// Gradient tile with an icon badge above an accent-colored value.
  gradient,

  /// Elevated tile with a circular icon badge and an optional caption.
  summary,
}

/// Reusable dashboard KPI card. Pick the layout with the matching named
/// constructor; structural colors come from `context.mediTheme` while the
/// accent is supplied by the caller to signal healthy/warning/error states.
class KpiCard extends StatelessWidget {
  /// Card sized to fit a [Wrap] of sibling KPIs. [accent] tints the icon and
  /// defaults to the theme's info color.
  const KpiCard.compact({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.accent,
    this.onTap,
  })  : variant = KpiCardVariant.compact,
        gradient = null,
        subtitle = null;

  /// Fixed-width card whose value is rendered in [accent].
  const KpiCard.gradient({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required Color this.accent,
    required LinearGradient this.gradient,
    this.onTap,
  })  : variant = KpiCardVariant.gradient,
        subtitle = null;

  /// Expandable card for report summaries, with an optional caption.
  const KpiCard.summary({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required Color this.accent,
    this.subtitle,
  })  : variant = KpiCardVariant.summary,
        gradient = null,
        onTap = null;

  final String title;
  final String value;
  final IconData icon;

  /// Tints the icon, and the value on the gradient and summary variants.
  /// Falls back to the theme's info color.
  final Color? accent;

  /// Background of the gradient variant.
  final LinearGradient? gradient;

  /// Caption under the value on the summary variant.
  final String? subtitle;

  /// Card is non-interactive when null.
  final VoidCallback? onTap;

  final KpiCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.mediTheme;
    final accentColor = accent ?? colors.info;

    switch (variant) {
      case KpiCardVariant.compact:
        return _buildCompact(colors, accentColor);
      case KpiCardVariant.gradient:
        return _buildGradient(colors, accentColor);
      case KpiCardVariant.summary:
        return _buildSummary(colors, accentColor);
    }
  }

  Widget _buildCompact(MediFlowTheme colors, Color accentColor) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 250),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.textSecondary,
                            letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Icon(icon, color: accentColor, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Text(value,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildGradient(MediFlowTheme colors, Color accentColor) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(height: 18),
            Text(value,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: accentColor)),
            const SizedBox(height: 4),
            Text(title,
                style: TextStyle(fontSize: 13, color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(MediFlowTheme colors, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
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
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(value,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: accentColor)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: TextStyle(fontSize: 11, color: colors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
