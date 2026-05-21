import 'package:shared_preferences/shared_preferences.dart';

class MorningService {
  MorningService._();
  static final MorningService instance = MorningService._();

  static const _kLastOpenedKey = 'morning_last_opened';

  bool get isMorning {
    final h = DateTime.now().hour;
    return h >= 5 && h < 9;
  }

  Future<bool> get isFirstOpenToday async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kLastOpenedKey);
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    return stored != todayKey;
  }

  Future<void> markOpened() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(
        _kLastOpenedKey, '${now.year}-${now.month}-${now.day}');
  }

  String get morningGreeting {
    final h = DateTime.now().hour;
    if (h < 6) return 'Up early. Someone will love hearing that. 🌙';
    if (h < 7) return 'Good morning. The day is just beginning. 🌅';
    if (h < 8) return 'Morning light. A good time to say something. ☀️';
    return 'Good morning. Before the day gets busy.';
  }

  String get currentTimeLabel {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $period';
  }
}
