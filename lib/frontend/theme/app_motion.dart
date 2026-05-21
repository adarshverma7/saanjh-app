import 'package:flutter/animation.dart';

class AppMotion {
  AppMotion._();

  static const easeOut    = Cubic(0.16, 1.0, 0.3, 1.0);
  static const easeSpring = Cubic(0.34, 1.56, 0.64, 1.0);

  static const fast   = Duration(milliseconds: 200);
  static const page   = Duration(milliseconds: 350); // page-level entry / tab switch
  static const medium = Duration(milliseconds: 480);
  static const slow   = Duration(milliseconds: 900);
  static const hero   = Duration(milliseconds: 1100);
  static const xSlow  = Duration(milliseconds: 1000); // full-screen reveals
  static const xxSlow = Duration(milliseconds: 1600); // cinematic entrances

  static const breatheSlow = Duration(seconds: 8);
  static const breatheLogo = Duration(seconds: 5);

  /// Staggered delay for a list item at [index].
  /// Items beyond [maxIndex] are shown immediately (zero delay) so long
  /// lists don't accumulate excessive wait times on scroll.
  static Duration stagger(int index, {int baseMs = 60, int maxIndex = 6}) =>
      Duration(milliseconds: baseMs * index.clamp(0, maxIndex));
}
