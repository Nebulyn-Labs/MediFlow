import 'package:flutter/material.dart';
import 'package:med_supply_prototype/constants/colors.dart';

/// Semantic MediFlow color roles supplied through Flutter's theme system.
///
/// Widgets should read these values with `context.mediTheme` instead of using
/// palette constants directly. A future light or high-contrast theme can then
/// replace the extension without requiring changes throughout the UI.
@immutable
class MediFlowTheme extends ThemeExtension<MediFlowTheme> {
  const MediFlowTheme({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceHover,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.primaryLight,
    required this.violet,
    required this.cyan,
    required this.teal,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.onAccent,
    required this.shadow,
    required this.donor,
    required this.recipient,
    required this.priorityRoute,
    required this.heroStart,
    required this.heroEnd,
    required this.heroTextEnd,
    required this.facilityGradientStart,
    required this.smartAnalysisSurface,
    required this.kpiSurfaceEnd,
    required this.healthyKpiSurface,
    required this.warningKpiSurface,
    required this.infoKpiSurface,
    required this.errorKpiSurface,
  });

  /// Current application palette. Values intentionally match the pre-refactor
  /// `MediColors` values so this migration causes no visual change.
  static const dark = MediFlowTheme(
    background: MediColors.bg,
    surface: MediColors.surface,
    surfaceLight: MediColors.surfaceLight,
    surfaceHover: MediColors.surfaceHover,
    border: MediColors.border,
    borderLight: MediColors.borderLight,
    textPrimary: MediColors.textPrimary,
    textSecondary: MediColors.textSecondary,
    textMuted: MediColors.textMuted,
    primary: MediColors.primary,
    primaryLight: MediColors.primaryLight,
    violet: MediColors.violet,
    cyan: MediColors.cyan,
    teal: MediColors.teal,
    success: MediColors.success,
    warning: MediColors.warning,
    error: MediColors.error,
    info: MediColors.info,
    onAccent: Colors.white,
    shadow: Colors.black,
    donor: Colors.green,
    recipient: Colors.orange,
    priorityRoute: Colors.blueAccent,
    heroStart: Color(0xFF0F172A),
    heroEnd: Color(0xFF1E1B4B),
    heroTextEnd: Color(0xFFA5B4FC),
    facilityGradientStart: Color(0xFF059669),
    smartAnalysisSurface: Color(0xFF1E3A8A),
    kpiSurfaceEnd: Color(0xFF1E293B),
    healthyKpiSurface: Color(0xFF0A3D2E),
    warningKpiSurface: Color(0xFF3D2E0A),
    infoKpiSurface: Color(0xFF1E3A5F),
    errorKpiSurface: Color(0xFF3D1519),
  );

  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceHover;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primary;
  final Color primaryLight;
  final Color violet;
  final Color cyan;
  final Color teal;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color onAccent;
  final Color shadow;
  final Color donor;
  final Color recipient;
  final Color priorityRoute;
  final Color heroStart;
  final Color heroEnd;
  final Color heroTextEnd;
  final Color facilityGradientStart;
  final Color smartAnalysisSurface;
  final Color kpiSurfaceEnd;
  final Color healthyKpiSurface;
  final Color warningKpiSurface;
  final Color infoKpiSurface;
  final Color errorKpiSurface;

  Color get primaryOverlay => primary.withValues(alpha: 0.1);
  Color get primarySubtle => primary.withValues(alpha: 0.08);
  Color get successOverlay => success.withValues(alpha: 0.1);
  Color get successSubtle => success.withValues(alpha: 0.08);
  Color get successBorder => success.withValues(alpha: 0.2);
  Color get errorOverlay => error.withValues(alpha: 0.1);
  Color get warningOverlay => warning.withValues(alpha: 0.1);

  LinearGradient get primaryGradient => LinearGradient(
        colors: [primary, violet],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get cyanGradient => LinearGradient(
        colors: [cyan, teal],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get surfaceGradient => LinearGradient(
        colors: [surface, surfaceLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get heroGradient => LinearGradient(
        colors: [heroStart, heroEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get heroTitleGradient =>
      LinearGradient(colors: [onAccent, heroTextEnd]);

  LinearGradient get facilityGradient =>
      LinearGradient(colors: [facilityGradientStart, teal]);

  LinearGradient get healthyKpiGradient =>
      LinearGradient(colors: [healthyKpiSurface, kpiSurfaceEnd]);

  LinearGradient get warningKpiGradient =>
      LinearGradient(colors: [warningKpiSurface, kpiSurfaceEnd]);

  LinearGradient get infoKpiGradient =>
      LinearGradient(colors: [infoKpiSurface, kpiSurfaceEnd]);

  LinearGradient get errorKpiGradient =>
      LinearGradient(colors: [errorKpiSurface, kpiSurfaceEnd]);

  @override
  MediFlowTheme copyWith({
    Color? background,
    Color? surface,
    Color? surfaceLight,
    Color? surfaceHover,
    Color? border,
    Color? borderLight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? primary,
    Color? primaryLight,
    Color? violet,
    Color? cyan,
    Color? teal,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? onAccent,
    Color? shadow,
    Color? donor,
    Color? recipient,
    Color? priorityRoute,
    Color? heroStart,
    Color? heroEnd,
    Color? heroTextEnd,
    Color? facilityGradientStart,
    Color? smartAnalysisSurface,
    Color? kpiSurfaceEnd,
    Color? healthyKpiSurface,
    Color? warningKpiSurface,
    Color? infoKpiSurface,
    Color? errorKpiSurface,
  }) {
    return MediFlowTheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceLight: surfaceLight ?? this.surfaceLight,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      border: border ?? this.border,
      borderLight: borderLight ?? this.borderLight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      violet: violet ?? this.violet,
      cyan: cyan ?? this.cyan,
      teal: teal ?? this.teal,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      onAccent: onAccent ?? this.onAccent,
      shadow: shadow ?? this.shadow,
      donor: donor ?? this.donor,
      recipient: recipient ?? this.recipient,
      priorityRoute: priorityRoute ?? this.priorityRoute,
      heroStart: heroStart ?? this.heroStart,
      heroEnd: heroEnd ?? this.heroEnd,
      heroTextEnd: heroTextEnd ?? this.heroTextEnd,
      facilityGradientStart:
          facilityGradientStart ?? this.facilityGradientStart,
      smartAnalysisSurface: smartAnalysisSurface ?? this.smartAnalysisSurface,
      kpiSurfaceEnd: kpiSurfaceEnd ?? this.kpiSurfaceEnd,
      healthyKpiSurface: healthyKpiSurface ?? this.healthyKpiSurface,
      warningKpiSurface: warningKpiSurface ?? this.warningKpiSurface,
      infoKpiSurface: infoKpiSurface ?? this.infoKpiSurface,
      errorKpiSurface: errorKpiSurface ?? this.errorKpiSurface,
    );
  }

  @override
  MediFlowTheme lerp(covariant MediFlowTheme? other, double t) {
    if (other == null) return this;
    return MediFlowTheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderLight: Color.lerp(borderLight, other.borderLight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      donor: Color.lerp(donor, other.donor, t)!,
      recipient: Color.lerp(recipient, other.recipient, t)!,
      priorityRoute: Color.lerp(priorityRoute, other.priorityRoute, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
      heroTextEnd: Color.lerp(heroTextEnd, other.heroTextEnd, t)!,
      facilityGradientStart: Color.lerp(
        facilityGradientStart,
        other.facilityGradientStart,
        t,
      )!,
      smartAnalysisSurface: Color.lerp(
        smartAnalysisSurface,
        other.smartAnalysisSurface,
        t,
      )!,
      kpiSurfaceEnd: Color.lerp(kpiSurfaceEnd, other.kpiSurfaceEnd, t)!,
      healthyKpiSurface: Color.lerp(
        healthyKpiSurface,
        other.healthyKpiSurface,
        t,
      )!,
      warningKpiSurface: Color.lerp(
        warningKpiSurface,
        other.warningKpiSurface,
        t,
      )!,
      infoKpiSurface: Color.lerp(infoKpiSurface, other.infoKpiSurface, t)!,
      errorKpiSurface: Color.lerp(errorKpiSurface, other.errorKpiSurface, t)!,
    );
  }
}

extension MediFlowThemeContext on BuildContext {
  /// Semantic color roles for the active MediFlow theme.
  MediFlowTheme get mediTheme =>
      Theme.of(this).extension<MediFlowTheme>() ?? MediFlowTheme.dark;
}
