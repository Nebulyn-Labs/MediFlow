import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';

void main() {
  group('MediFlowTheme', () {
    test('dark theme preserves the legacy application palette', () {
      const theme = MediFlowTheme.dark;

      expect(theme.background, MediColors.bg);
      expect(theme.surface, MediColors.surface);
      expect(theme.surfaceLight, MediColors.surfaceLight);
      expect(theme.surfaceHover, MediColors.surfaceHover);
      expect(theme.border, MediColors.border);
      expect(theme.borderLight, MediColors.borderLight);
      expect(theme.textPrimary, MediColors.textPrimary);
      expect(theme.textSecondary, MediColors.textSecondary);
      expect(theme.textMuted, MediColors.textMuted);
      expect(theme.primary, MediColors.primary);
      expect(theme.primaryLight, MediColors.primaryLight);
      expect(theme.violet, MediColors.violet);
      expect(theme.cyan, MediColors.cyan);
      expect(theme.teal, MediColors.teal);
      expect(theme.success, MediColors.success);
      expect(theme.warning, MediColors.warning);
      expect(theme.error, MediColors.error);
      expect(theme.info, MediColors.info);
      expect(theme.primaryOverlay, MediColors.primaryOverlay);
      expect(theme.primarySubtle, MediColors.primarySubtle);
      expect(theme.successOverlay, MediColors.successOverlay);
      expect(theme.successSubtle, MediColors.successSubtle);
      expect(theme.successBorder, MediColors.successBorder);
      expect(theme.errorOverlay, MediColors.errorOverlay);
      expect(theme.warningOverlay, MediColors.warningOverlay);
      expect(theme.primaryGradient, MediColors.primaryGradient);
      expect(theme.cyanGradient, MediColors.cyanGradient);
      expect(theme.surfaceGradient, MediColors.surfaceGradient);
    });

    test('light theme provides expected light palette tokens', () {
      const theme = MediFlowTheme.light;

      expect(theme.background, const Color(0xFFF8FAFC));
      expect(theme.surface, const Color(0xFFFFFFFF));
      expect(theme.surfaceLight, const Color(0xFFF1F5F9));
      expect(theme.surfaceHover, const Color(0xFFE2E8F0));
      expect(theme.border, const Color(0xFFE2E8F0));
      expect(theme.borderLight, const Color(0xFFCBD5E1));
      expect(theme.textPrimary, const Color(0xFF0F172A));
      expect(theme.textSecondary, const Color(0xFF475569));
      expect(theme.textMuted, const Color(0xFF94A3B8));
      expect(theme.primary, const Color(0xFF4F46E5));
      expect(theme.primaryLight, const Color(0xFF6366F1));
      expect(theme.violet, const Color(0xFF7C3AED));
      expect(theme.cyan, const Color(0xFF0891B2));
      expect(theme.teal, const Color(0xFF0D9488));
      expect(theme.success, const Color(0xFF059669));
      expect(theme.warning, const Color(0xFFD97706));
      expect(theme.error, const Color(0xFFE11D48));
      expect(theme.info, const Color(0xFF2563EB));
      expect(theme.onAccent, Colors.white);
    });

    testWidgets('context reads the extension from ThemeData', (tester) async {
      const customPrimary = Color(0xFF123456);
      final customTheme = MediFlowTheme.dark.copyWith(primary: customPrimary);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [customTheme]),
          home: Builder(
            builder: (context) {
              expect(context.mediTheme.primary, customPrimary);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('context has a safe dark-theme fallback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(context.mediTheme.primary, MediFlowTheme.dark.primary);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('copyWith changes one role without changing the others', () {
      const replacement = Color(0xFF654321);
      final copied = MediFlowTheme.dark.copyWith(primary: replacement);

      expect(copied.primary, replacement);
      expect(copied.background, MediFlowTheme.dark.background);
      expect(copied.textPrimary, MediFlowTheme.dark.textPrimary);
    });

    test('lerp interpolates semantic roles', () {
      final destination = MediFlowTheme.dark.copyWith(
        primary: Colors.white,
        background: Colors.white,
      );
      final midpoint = MediFlowTheme.dark.lerp(destination, 0.5);

      expect(
        midpoint.primary,
        Color.lerp(MediFlowTheme.dark.primary, Colors.white, 0.5),
      );
      expect(
        midpoint.background,
        Color.lerp(MediFlowTheme.dark.background, Colors.white, 0.5),
      );
    });
  });
}
