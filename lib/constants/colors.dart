import 'package:flutter/material.dart';

/// A complete set of colors used by the app for a single theme mode.
class MediPalette {
  const MediPalette({
    required this.bg,
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
  });

  final Color bg;
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

  // Semantic translucent overlays
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
}

class MediColors {
  MediColors._();

  /// Dark theme palette (default).
  static const MediPalette dark = MediPalette(
    bg: Color(0xFF0B1120),
    surface: Color(0xFF141B2D),
    surfaceLight: Color(0xFF1C2538),
    surfaceHover: Color(0xFF243049),
    border: Color(0xFF2A3550),
    borderLight: Color(0xFF354363),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF8896B3),
    textMuted: Color(0xFF5A6B8A),
    primary: Color(0xFF6366F1),
    primaryLight: Color(0xFF818CF8),
    violet: Color(0xFF8B5CF6),
    cyan: Color(0xFF06B6D4),
    teal: Color(0xFF14B8A6),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFF43F5E),
    info: Color(0xFF3B82F6),
  );

  /// Light theme palette.
  static const MediPalette light = MediPalette(
    bg: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFEFF2F8),
    surfaceHover: Color(0xFFE4E8F0),
    border: Color(0xFFE2E8F0),
    borderLight: Color(0xFFCBD5E1),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    primary: Color(0xFF6366F1),
    primaryLight: Color(0xFF818CF8),
    violet: Color(0xFF8B5CF6),
    cyan: Color(0xFF06B6D4),
    teal: Color(0xFF14B8A6),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFF43F5E),
    info: Color(0xFF3B82F6),
  );

  static MediPalette _active = dark;

  /// Palette backing the currently active theme mode.
  static MediPalette get active => _active;

  /// Switches the active palette (called when the theme mode changes).
  static void setActivePalette(MediPalette palette) {
    _active = palette;
  }

  // ──────────────────────────────────────────────────────────────
  // Current palette colors (kept as the `MediColors.*` API)
  // ──────────────────────────────────────────────────────────────
  static Color get bg => _active.bg;
  static Color get surface => _active.surface;
  static Color get surfaceLight => _active.surfaceLight;
  static Color get surfaceHover => _active.surfaceHover;
  static Color get border => _active.border;
  static Color get borderLight => _active.borderLight;
  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  static Color get textMuted => _active.textMuted;
  static Color get primary => _active.primary;
  static Color get primaryLight => _active.primaryLight;
  static Color get violet => _active.violet;
  static Color get cyan => _active.cyan;
  static Color get teal => _active.teal;
  static Color get success => _active.success;
  static Color get warning => _active.warning;
  static Color get error => _active.error;
  static Color get info => _active.info;

  // Semantic translucent overlays
  static Color get primaryOverlay => _active.primaryOverlay;
  static Color get primarySubtle => _active.primarySubtle;

  static Color get successOverlay => _active.successOverlay;
  static Color get successSubtle => _active.successSubtle;
  static Color get successBorder => _active.successBorder;

  static Color get errorOverlay => _active.errorOverlay;
  static Color get warningOverlay => _active.warningOverlay;

  static LinearGradient get primaryGradient => _active.primaryGradient;

  static LinearGradient get cyanGradient => _active.cyanGradient;

  static LinearGradient get surfaceGradient => _active.surfaceGradient;
}
