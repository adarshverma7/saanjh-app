import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Semantic surface / state tokens ──────────────────────────────────────
  // Single source of truth for these raw hex values across the whole codebase.
  static const modalSurface  = Color(0xFF130A10); // bottom sheets, dialogs
  static const destructive   = Color(0xFFFF453A); // delete, block, error
  static const successGreen  = Color(0xFF30D158); // streaks complete, sent, confirmed
  static const violet        = Color(0xFFBF5AF2); // video type, onboarding slide 2
  static const azure         = Color(0xFF0A84FF); // photo type, privacy icons

  static const ember = Color(0xFFE8720C);
  static const emberWarm = Color(0xFFFF9A40);
  static const emberBright = Color(0xFFFFB870);
  // WCAG AA–safe amber for small text on dark backgrounds (≥4.5:1 on inkDeep).
  static const emberAccessible = Color(0xFFFFA040);

  static const ink = Color(0xFF0A0608);
  static const inkDeep = Color(0xFF050405);
  static const inkRaised = Color(0xFF0F0606);

  static const text = Color(0xFFF5EFE8);
  static Color textMuted = const Color(0xFFF5EFE8).withValues(alpha:0.62);
  static Color textFaint = const Color(0xFFF5EFE8).withValues(alpha:0.32);

  static Color borderSoft = Colors.white.withValues(alpha:0.14);
  static Color borderStrong = Colors.white.withValues(alpha:0.22);
  static Color surfaceTint = Colors.white.withValues(alpha:0.04);

  static const emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [emberWarm, ember],
  );

  static const logoGradient = LinearGradient(
    begin: Alignment(-0.5, -0.7),
    end: Alignment(0.6, 0.8),
    colors: [emberWarm, ember],
  );
}
