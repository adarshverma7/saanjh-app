// Stub — fully implemented in Prompt 27.
// Stores private voice recordings locally. Never shared. Only accessible from Me screen.

class PersonalReflection {
  final String id;
  final String audioPath;
  final String? transcript;
  final DateTime createdAt;
  final String? prompt;

  const PersonalReflection({
    required this.id,
    required this.audioPath,
    this.transcript,
    required this.createdAt,
    this.prompt,
  });
}

class PersonalReflectionService {
  PersonalReflectionService._();
  static final PersonalReflectionService instance =
      PersonalReflectionService._();

  final List<PersonalReflection> _reflections = [];

  List<PersonalReflection> get all => List.unmodifiable(_reflections);

  void addReflection(PersonalReflection reflection) {
    _reflections.insert(0, reflection);
  }

  // Returns a reflection from the same month+day in a prior year, if any.
  PersonalReflection? todaysMemory() {
    final now = DateTime.now();
    try {
      return _reflections.firstWhere((r) =>
          r.createdAt.month == now.month &&
          r.createdAt.day == now.day &&
          r.createdAt.year != now.year);
    } catch (_) {
      return null;
    }
  }
}
