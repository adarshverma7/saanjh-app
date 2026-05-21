import 'package:flutter/material.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class Occasion {
  final String name;
  final String emoji;
  final int month;
  // Approximate calendar day. Lunar-calendar festivals vary yearly — update annually.
  final int approximateDay;
  final int daysBeforeToShow;
  final Color tintColor;

  const Occasion({
    required this.name,
    required this.emoji,
    required this.month,
    required this.approximateDay,
    this.daysBeforeToShow = 2,
    required this.tintColor,
  });

  String get tag => '$emoji $name';
}

// ─── Service ──────────────────────────────────────────────────────────────────

class OccasionService {
  OccasionService._();
  static final OccasionService instance = OccasionService._();

  static const List<Occasion> calendar = [
    Occasion(name: 'New Year',        emoji: '🎆', month: 1,  approximateDay: 1,  tintColor: Color(0xFF00001A)),
    Occasion(name: 'Pongal',          emoji: '🌾', month: 1,  approximateDay: 14, tintColor: Color(0xFF1A1200)),
    Occasion(name: 'Republic Day',    emoji: '🇮🇳', month: 1,  approximateDay: 26, tintColor: Color(0xFF00081A)),
    Occasion(name: "Valentine's Day", emoji: '💝', month: 2,  approximateDay: 14, tintColor: Color(0xFF1A0010)),
    Occasion(name: 'Holi',            emoji: '🎨', month: 3,  approximateDay: 25, tintColor: Color(0xFF1A000A)),
    Occasion(name: 'Eid',             emoji: '🌙', month: 4,  approximateDay: 10, tintColor: Color(0xFF002A1A)),
    Occasion(name: 'Baisakhi',        emoji: '🌻', month: 4,  approximateDay: 13, tintColor: Color(0xFF0A1A00)),
    Occasion(name: "Mother's Day",    emoji: '💐', month: 5,  approximateDay: 12, tintColor: Color(0xFF1A0016)),
    Occasion(name: "Father's Day",    emoji: '🌿', month: 6,  approximateDay: 16, tintColor: Color(0xFF001018)),
    Occasion(name: 'Friendship Day',  emoji: '🤝', month: 8,  approximateDay: 4,  tintColor: Color(0xFF101A00)),
    Occasion(name: 'Independence Day',emoji: '🇮🇳', month: 8,  approximateDay: 15, tintColor: Color(0xFF001A00)),
    Occasion(name: 'Raksha Bandhan',  emoji: '🪢', month: 8,  approximateDay: 19, tintColor: Color(0xFF1A1000)),
    Occasion(name: "Teacher's Day",   emoji: '📚', month: 9,  approximateDay: 5,  tintColor: Color(0xFF001818)),
    Occasion(name: 'Grandparents Day',emoji: '💛', month: 9,  approximateDay: 8,  tintColor: Color(0xFF1A0E00)),
    Occasion(name: 'Onam',            emoji: '🌺', month: 9,  approximateDay: 15, tintColor: Color(0xFF001A08)),
    Occasion(name: 'Navratri',        emoji: '🪔', month: 10, approximateDay: 3,  tintColor: Color(0xFF1A0A00)),
    Occasion(name: 'Dussehra',        emoji: '🏹', month: 10, approximateDay: 12, tintColor: Color(0xFF1A0800)),
    Occasion(name: 'Diwali',          emoji: '🪔', month: 10, approximateDay: 20, tintColor: Color(0xFF2A1A00)),
    Occasion(name: 'Christmas',       emoji: '🎄', month: 12, approximateDay: 25, tintColor: Color(0xFF1A0006)),
    Occasion(name: "New Year's Eve",  emoji: '🥂', month: 12, approximateDay: 31, tintColor: Color(0xFF0A001A)),
  ];

  // Returns the nearest upcoming occasion within its daysBeforeToShow window.
  Occasion? upcomingOccasion() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final occasion in calendar) {
      final occasionDate =
          DateTime(now.year, occasion.month, occasion.approximateDay);
      final diff = occasionDate.difference(today).inDays;
      if (diff >= 0 && diff <= occasion.daysBeforeToShow) return occasion;
    }
    return null;
  }

  int _daysUntil(Occasion occasion) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(now.year, occasion.month, occasion.approximateDay);
    return date.difference(today).inDays;
  }

  String occasionPrompt(Occasion occasion, String contactName) {
    final days = _daysUntil(occasion);
    final when = days == 0
        ? 'today'
        : days == 1
            ? 'tomorrow'
            : 'in $days days';

    return switch (occasion.name) {
      'Diwali' =>
        'Diwali is $when. Send $contactName a greeting before the forwards start. 20 seconds. It\'ll mean more. ${occasion.emoji}',
      'Eid' =>
        'Eid is $when. A voice note before the day begins. Worth more than any text. ${occasion.emoji}',
      'Christmas' =>
        'Christmas is $when. A voice note from you will mean more than any card. 20 seconds. ${occasion.emoji}',
      'New Year' =>
        'The new year arrives $when. Send $contactName the first voice of the year. ${occasion.emoji}',
      "New Year's Eve" =>
        'The year ends $when. Send $contactName one last voice before it\'s over. ${occasion.emoji}',
      'Republic Day' =>
        'Republic Day is $when. A good day to say something real to $contactName. ${occasion.emoji}',
      'Independence Day' =>
        'Independence Day is $when. Celebrate by saying something that matters. ${occasion.emoji}',
      "Mother's Day" =>
        'Mother\'s Day is $when. She doesn\'t need a gift. She needs to hear your voice. ${occasion.emoji}',
      "Father's Day" =>
        'Father\'s Day is $when. He\'ll say it\'s fine. But hearing you will make his day. ${occasion.emoji}',
      'Holi' =>
        'Holi is $when. Send $contactName some colour before the celebrations. 20 seconds. ${occasion.emoji}',
      'Raksha Bandhan' =>
        'Raksha Bandhan is $when. A voice note for $contactName — this time it\'s yours to send. ${occasion.emoji}',
      'Navratri' =>
        'Navratri begins $when. Reach $contactName before the celebrations begin. ${occasion.emoji}',
      'Baisakhi' =>
        'Baisakhi is $when. Harvest season — a good time to send warmth to $contactName. ${occasion.emoji}',
      'Onam' =>
        'Onam is $when. Send $contactName a voice greeting from wherever you are. ${occasion.emoji}',
      'Pongal' =>
        'Pongal is $when. A moment of thanks — share it with $contactName. ${occasion.emoji}',
      "Valentine's Day" =>
        'Valentine\'s Day is $when. Skip the card. Just say something real. 20 seconds. ${occasion.emoji}',
      'Friendship Day' =>
        'Friendship Day is $when. Tell $contactName what they mean to you. 20 seconds. ${occasion.emoji}',
      "Teacher's Day" =>
        'Teacher\'s Day is $when. If $contactName shaped who you are — tell them. ${occasion.emoji}',
      'Grandparents Day' =>
        'Grandparents Day is $when. $contactName will light up hearing your voice today. ${occasion.emoji}',
      'Dussehra' =>
        'Dussehra is $when. A moment of warmth for $contactName before the celebrations. ${occasion.emoji}',
      _ =>
        '${occasion.name} is $when. Send $contactName a voice greeting. 20 seconds of warmth. ${occasion.emoji}',
    };
  }
}
