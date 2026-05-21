import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Warmth tiers — calculated from time since last voice/video note.
enum FlickerWarmth {
  fullBurn, // 0–48 h  : 60-80 particles, amber-gold fire
  embers,   // 2–7 d   : 15-20 particles, deep red glow
  coldAsh,  // 7+ d    : 3-5  particles, blue-grey drift
}

extension FlickerWarmthX on FlickerWarmth {
  /// Target particle count for this warmth state.
  int get particleCount => switch (this) {
        FlickerWarmth.fullBurn => 68,
        FlickerWarmth.embers   => 18,
        FlickerWarmth.coldAsh  => 4,
      };

  /// Velocity scale (how fast embers rise).
  double get velocityScale => switch (this) {
        FlickerWarmth.fullBurn => 1.0,
        FlickerWarmth.embers   => 0.55,
        FlickerWarmth.coldAsh  => 0.28,
      };

  /// Base flame height as fraction of canvas height.
  double get flameHeight => switch (this) {
        FlickerWarmth.fullBurn => 0.42,
        FlickerWarmth.embers   => 0.22,
        FlickerWarmth.coldAsh  => 0.10,
      };

  /// Primary ember colour palette for particles.
  List<Color> get particleColors => switch (this) {
        FlickerWarmth.fullBurn => const [
            Color(0xFFFFED80), // bright yellow-white
            Color(0xFFFFB840), // gold
            Color(0xFFFF8020), // orange
            Color(0xFFCC4400), // deep orange
          ],
        FlickerWarmth.embers => const [
            Color(0xFFFF7020),
            Color(0xFFCC3300),
            Color(0xFF8B1800),
          ],
        FlickerWarmth.coldAsh => const [
            Color(0xFF6080AA),
            Color(0xFF3A5080),
            Color(0xFF1E2E50),
          ],
      };

  /// Flame body gradient colours (bottom → top).
  List<Color> get flameGradient => switch (this) {
        FlickerWarmth.fullBurn => const [
            Color(0xFFFF4400),
            Color(0xFFFF8800),
            Color(0xFFFFCC00),
            Color(0x00FFEE80),
          ],
        FlickerWarmth.embers => const [
            Color(0xFF8B1000),
            Color(0xFFCC3300),
            Color(0xFFFF6600),
            Color(0x00FF8800),
          ],
        FlickerWarmth.coldAsh => const [
            Color(0xFF0A1428),
            Color(0xFF1A2A50),
            Color(0xFF2A3C6A),
            Color(0x00344880),
          ],
      };

  /// Ground-glow colour at the base of the fire.
  Color get groundGlow => switch (this) {
        FlickerWarmth.fullBurn => const Color(0x55FF6600),
        FlickerWarmth.embers   => const Color(0x33CC2200),
        FlickerWarmth.coldAsh  => const Color(0x11334488),
      };

  /// Background radial tint behind the whole scene.
  Color get sceneTint => switch (this) {
        FlickerWarmth.fullBurn => const Color(0x22FF4400),
        FlickerWarmth.embers   => const Color(0x15880000),
        FlickerWarmth.coldAsh  => const Color(0x0A001844),
      };
}

/// Derive warmth from how long ago the last note was sent/received.
FlickerWarmth warmthFromDuration(Duration? since) {
  if (since == null || since.inHours < 48) return FlickerWarmth.fullBurn;
  if (since.inDays < 7)                    return FlickerWarmth.embers;
  return FlickerWarmth.coldAsh;
}

/// Time-of-day colour temperature overlay applied to the fire.
/// Keeps the simulation anchored to real circadian rhythms.
Color timeOfDayTint() {
  final h = DateTime.now().hour;
  if (h >= 5  && h < 9)  return const Color(0x18FFD060); // golden dawn
  if (h >= 9  && h < 17) return const Color(0x00FFFFFF); // neutral day
  if (h >= 17 && h < 21) return const Color(0x14FF8820); // warm dusk
  return const Color(0x12304880);                          // cool night
}

/// Controller that lets callers trigger one-shot fire events.
class FlickerController extends ChangeNotifier {
  int _burstCount = 0;
  double _brightnessBoost = 0; // 0–1

  int get burstCount => _burstCount;
  double get brightnessBoost => _brightnessBoost;

  /// Called when a voice/video note is sent — spawns a particle burst.
  void onNoteSent() {
    _burstCount++;
    notifyListeners();
    HapticFeedback.mediumImpact();
  }

  /// Called when a received note starts playing — brightens fire for 3 s.
  Future<void> onNotePlay() async {
    _brightnessBoost = 1.0;
    notifyListeners();
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      _brightnessBoost = 1.0 - (i / 30);
      notifyListeners();
    }
    _brightnessBoost = 0;
    notifyListeners();
  }

  /// Resets burst counter after the painter has consumed it.
  void consumeBurst() {
    _burstCount = 0;
  }
}

