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
