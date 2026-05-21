// Replace stub with POST to /api/transcribe when backend ready.
// Real implementation uses Whisper API: POST audioPath → String transcript.

class TranscriptionService {
  TranscriptionService._();
  static final TranscriptionService instance = TranscriptionService._();

  // STUB: Returns null until backend transcription endpoint is wired.
  Future<String?> transcribeFile(String audioPath) async => null;
}
