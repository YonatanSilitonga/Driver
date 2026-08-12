import 'package:flutter/material.dart';

/// Centralized color palette — matches splash screen theme.
class AppColors {
  AppColors._();

  // ── Navy (primary) ──
  static const navyDeep = Color(0xFF0F172A); // splash top
  static const navyMid = Color(0xFF1E293B); // splash mid
  static const navy = Color(0xFF0D47A1); // splash bottom / primary

  // ── Orange (accent) ──
  static const orange = Color(0xFFF27D26); // button / CTA
  static const orangeLight = Color(0xFFFF8F00); // badges / highlights
  static const amber = Color(0xFFFFC107);

  // ── Neutrals ──
  static const scaffoldBg = Color(0xFFF8F9FA);
  static const cardWhite = Colors.white;
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textMuted = Color(0xFF94A3B8);
  static const borderLight = Color(0xFFE2E8F0);

  // ── Semantic ──
  static const success = Color(0xFF16A34A);
  static const successBg = Color(0xFFDCFCE7);
  static const warning = Color(0xFFD97706);
  static const warningBg = Color(0xFFFEF3C7);
  static const error = Color(0xFFDC2626);
  static const errorBg = Color(0xFFFEE2E2);

  // ── Gradients ──
  static const navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [navyDeep, navyMid, navy],
  );
}
