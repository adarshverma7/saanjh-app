import '../state/diary_store.dart';

// ─── Page ─────────────────────────────────────────────────────────────────────

class MemoryBookPage {
  final String contactName;
  final DateTime date;
  final String? transcript;
  final String? occasionTag;
  final bool isMine;
  final int durationSeconds;

  const MemoryBookPage({
    required this.contactName,
    required this.date,
    this.transcript,
    this.occasionTag,
    required this.isMine,
    required this.durationSeconds,
  });

  String get dateLabel {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  String get durationLabel {
    if (durationSeconds == 0) return '';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return m > 0
        ? '$m:${s.toString().padLeft(2, '0')}'
        : '0:${s.toString().padLeft(2, '0')}';
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class MemoryBookData {
  final String contactName;
  final int totalEntries;
  final int totalDurationSeconds;
  final int peakStreak;
  final int totalPulses;
  final List<MemoryBookPage> pages;
  final DateTime firstEntryDate;
  final DateTime lastEntryDate;

  const MemoryBookData({
    required this.contactName,
    required this.totalEntries,
    required this.totalDurationSeconds,
    required this.peakStreak,
    required this.totalPulses,
    required this.pages,
    required this.firstEntryDate,
    required this.lastEntryDate,
  });

  String get totalHoursFormatted {
    final hours = totalDurationSeconds ~/ 3600;
    final mins = (totalDurationSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${mins}m';
    if (mins > 0) return '${mins}m';
    return 'a few seconds';
  }

  String get durationLabel {
    if (totalDurationSeconds == 0) return '$totalEntries notes';
    return '$totalEntries notes · $totalHoursFormatted';
  }

  int get bookYear => firstEntryDate.year;
}

// ─── Generator ────────────────────────────────────────────────────────────────

class MemoryBookGenerator {
  static MemoryBookData? generateForDiary(String diaryId) {
    final store = DiaryStore.instance;
    final entries = store.entriesFor(diaryId);
    if (entries.isEmpty) return null;

    final diary = store.diaries
        .cast<DiaryContact?>()
        .firstWhere((d) => d?.id == diaryId, orElse: () => null);
    if (diary == null) return null;

    final sorted = [...entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final pages = sorted.take(20).map((e) => MemoryBookPage(
      contactName: diary.displayName,
      date: e.createdAt,
      transcript: e.transcript,
      occasionTag: e.occasionTag,
      isMine: e.isMine,
      durationSeconds: 0, // populated from audio metadata when backend ready
    )).toList();

    return MemoryBookData(
      contactName: diary.displayName,
      totalEntries: entries.length,
      totalDurationSeconds: 0, // populated from audio metadata when backend ready
      peakStreak: store.streakDays(diaryId),
      totalPulses: 0,
      pages: pages,
      firstEntryDate: sorted.first.createdAt,
      lastEntryDate: sorted.last.createdAt,
    );
  }

  static MemoryBookData? generateAnnual() {
    final store = DiaryStore.instance;
    if (store.diaries.isEmpty) return null;

    int totalEntries = 0;
    int bestStreak = 0;
    DateTime? firstEntry;
    DateTime? lastEntry;
    final pages = <MemoryBookPage>[];

    for (final diary in store.diaries) {
      final entries = store.entriesFor(diary.id);
      totalEntries += entries.length;

      final streak = store.streakDays(diary.id);
      if (streak > bestStreak) bestStreak = streak;

      for (final e in entries) {
        if (firstEntry == null || e.createdAt.isBefore(firstEntry)) {
          firstEntry = e.createdAt;
        }
        if (lastEntry == null || e.createdAt.isAfter(lastEntry)) {
          lastEntry = e.createdAt;
        }
        pages.add(MemoryBookPage(
          contactName: diary.displayName,
          date: e.createdAt,
          transcript: e.transcript,
          occasionTag: e.occasionTag,
          isMine: e.isMine,
          durationSeconds: 0,
        ));
      }
    }

    if (totalEntries == 0) return null;

    pages.sort((a, b) => a.date.compareTo(b.date));

    return MemoryBookData(
      contactName: store.diaries.length == 1
          ? store.diaries.first.displayName
          : 'Your Saanjh',
      totalEntries: totalEntries,
      totalDurationSeconds: 0,
      peakStreak: bestStreak,
      totalPulses: 0,
      pages: pages.take(20).toList(),
      firstEntryDate: firstEntry ?? DateTime.now(),
      lastEntryDate: lastEntry ?? DateTime.now(),
    );
  }
}
