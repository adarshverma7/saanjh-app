import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppShadows {
  AppShadows._();

  // ── Ember glow — under gradient buttons, FABs, active chips ──────────────
  // All params are optional so call sites only override what differs from
  // the standard CTA-button config (blur 28, offset 0 8, intensity 0.40).
  static List<BoxShadow> emberGlow({
    double intensity = 0.40,
    double blur = 28.0,
    Offset offset = const Offset(0, 8),
  }) =>
      [
        BoxShadow(
          color: AppColors.ember.withValues(alpha: intensity),
          blurRadius: blur,
          offset: offset,
        ),
      ];

  // ── Dot glow — status dots, badges, active ring indicators ───────────────
  static List<BoxShadow> dotGlow({
    Color? color,
    double intensity = 0.55,
    double blur = 6.0,
  }) =>
      [
        BoxShadow(
          color: (color ?? AppColors.emberWarm).withValues(alpha: intensity),
          blurRadius: blur,
        ),
      ];

  // ── Float — deep shadow for elevated / print-like surfaces ───────────────
  // Color(0x73000000) = black @ ~45 % opacity.
  static const List<BoxShadow> float = [
    BoxShadow(
      color: Color(0x73000000),
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];

  // ── Card — subtle lift for list cards ────────────────────────────────────
  // Color(0x38000000) = black @ ~22 % opacity.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x38000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}
