import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  static TextStyle display({double size = 56, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.02 * size,
        height: 1.1,
        color: AppColors.text,
      );

  static TextStyle title({double size = 28, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.01 * size,
        height: 1.15,
        color: AppColors.text,
      );

  static TextStyle serifItalic({double size = 20, Color? color}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? Colors.white.withValues(alpha:0.62),
      );

  static TextStyle devanagari({double size = 15, Color? color}) =>
      GoogleFonts.tiroDevanagariHindi(
        fontSize: size,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.03 * size,
        color: color ?? const Color(0xFFFFC88C).withValues(alpha:0.42),
      );

  static TextStyle body({double size = 15, FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.01 * size,
        height: 1.4,
        color: color ?? AppColors.text,
      );

  static TextStyle label({double size = 13, FontWeight weight = FontWeight.w500, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: 1.3,
        color: color ?? AppColors.textMuted,
      );

  // Secondary metadata: timestamps, dates, type indicators, duration text.
  // Defaults to textFaint; use color: param to override.
  static TextStyle caption({
    double size = 11,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: 1.3,
        letterSpacing: 0.01 * size,
        color: color ?? AppColors.textFaint,
      );

  // Timecodes and counters — tabular figures prevent width jitter as digits change.
  static TextStyle timestamp({Color? color}) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color ?? AppColors.textMuted,
      );

  static TextStyle button({double size = 15, FontWeight weight = FontWeight.w600, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.01 * size,
        color: color ?? AppColors.text,
      );

  static TextStyle eyebrow({double size = 11, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.18 * size,
        color: color ?? AppColors.textFaint,
      );
}
