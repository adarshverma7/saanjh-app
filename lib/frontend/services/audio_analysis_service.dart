// Audio analysis infrastructure — Phase 1.
//
// STUB: analyse() always returns null.
// TODO: Replace with real amplitude + RMS calculation using audioplayers:
//   1. Load file with AudioPlayer
//   2. Sample amplitude via onPositionChanged
//   3. Compute RMS from samples → averageAmplitude
//   4. Detect pace from silence intervals → syllables/sec estimate
//   5. Derive energy = clamp(averageAmplitude * 1.5 + pace * 0.3, 0, 1)
//   6. Derive warmth from spectral centroid (low freq dominance = warmer)

class AudioAnalysisResult {
  final double averageAmplitude; // 0.0–1.0
  final double peakAmplitude;    // 0.0–1.0
  final double pace;             // syllables/sec estimate (0.0–1.0 normalised)
  final double energy;           // composite 0.0–1.0 — drives bubble tint
  final double warmth;           // spectral warmth 0.0–1.0 — reserved for Phase 2

  const AudioAnalysisResult({
    required this.averageAmplitude,
    required this.peakAmplitude,
    required this.pace,
    required this.energy,
    required this.warmth,
  });
}

class AudioAnalysisService {
  static Future<AudioAnalysisResult?> analyse(String audioPath) async {
    // STUB — real implementation goes here when audioplayers integration lands.
    return null;
  }
}
