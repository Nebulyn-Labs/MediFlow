import 'package:flutter/material.dart';

class MediColors {
  static const Color bg = Color(0xFF0B1120);
  static const Color surface = Color(0xFF141B2D);
  static const Color surfaceLight = Color(0xFF1C2538);
  static const Color surfaceHover = Color(0xFF243049);
  static const Color border = Color(0xFF2A3550);
  static const Color borderLight = Color(0xFF354363);
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF8896B3);
  static const Color textMuted = Color(0xFF5A6B8A);
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color teal = Color(0xFF14B8A6);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFF43F5E);
  static const Color info = Color(0xFF3B82F6);

  // Semantic translucent overlays
  static Color get primaryOverlay => primary.withValues(alpha: 0.1);
  static Color get primarySubtle => primary.withValues(alpha: 0.08);

  static Color get successOverlay => success.withValues(alpha: 0.1);
  static Color get successSubtle => success.withValues(alpha: 0.08);
  static Color get successBorder => success.withValues(alpha: 0.2);

  static Color get errorOverlay => error.withValues(alpha: 0.1);
  static Color get warningOverlay => warning.withValues(alpha: 0.1);
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [cyan, teal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

static const LinearGradient surfaceGradient = LinearGradient(
    colors: [surface, surfaceLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class MediColorsLight {
  static const Color bg = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF1F5F9);
  static const Color surfaceHover = Color(0xFFE2E8F0);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFCBD5E1);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color teal = Color(0xFF14B8A6);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFF43F5E);
  static const Color info = Color(0xFF3B82F6);
}