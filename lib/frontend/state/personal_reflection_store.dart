import 'package:flutter/material.dart';

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

  String get dateLabel {
    final d = createdAt;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }
}

class PersonalReflectionStore extends ChangeNotifier {
  PersonalReflectionStore._();
  static final PersonalReflectionStore instance = PersonalReflectionStore._();

  final List<PersonalReflection> _reflections = [];

  List<PersonalReflection> get all {
    final sorted = [..._reflections]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sorted);
  }

  int get count => _reflections.length;

  void addReflection(PersonalReflection r) {
    _reflections.insert(0, r);
    notifyListeners();
  }

  // Returns a reflection from the same month+day exactly one year ago.
  PersonalReflection? todaysMemory() {
    final now = DateTime.now();
    try {
      return _reflections.firstWhere((r) =>
          r.createdAt.month == now.month &&
          r.createdAt.day == now.day &&
          r.createdAt.year == now.year - 1);
    } catch (_) {
      return null;
    }
  }
}
