import 'package:shared_preferences/shared_preferences.dart';

import '../state/diary_store.dart';
import '../state/flicker_store.dart';
import '../widgets/notification_banner.dart';

/* PUSH NOTIFICATION SYSTEM — implement when backend ready
 *
 * This service currently drives in-app banners only.
 * When the backend (FCM / APNs) is ready, each _check* method
 * should also enqueue a push notification via the platform channel.
 *
 * ── 8 trigger types ──────────────────────────────────────────────────────────
 *
 * 1. LISTENER RECEIPT  (SaanjhNotificationType.listenerReceipt)
 *    Title:   "[Name] listened to your voice note 🎧"
 *    Body:    "They heard every word."
 *    Payload: { diaryId, entryId }
 *    Action:  "Open diary"  →  /diary-thread?diaryId=X
 *    Rate:    max 3 per diary per day; suppress if app is foregrounded
 *
 * 2. FLICKER RECEIVED  (SaanjhNotificationType.flickerReceived)
 *    Title:   "[Name] flickered you 💛"
 *    Body:    "They're thinking of you."
 *    Payload: { diaryId }
 *    Action:  "Send one back"  →  /flicker?targetDiaryId=X
 *    Rate:    1 per diary per day; suppress if app foregrounded
 *
 * 3. MUTUAL FLICKER  (SaanjhNotificationType.mutualFlicker)
 *    Title:   "You and [Name] both flickered today ✨"
 *    Body:    "A little moment, shared."
 *    Payload: { diaryId }
 *    Action:  "Open diary"  →  /diary-thread?diaryId=X
 *    Rate:    1 per diary per day
 *
 * 4. STREAK AT RISK  (SaanjhNotificationType.streakAtRisk)
 *    Title:   "Your [N]-day streak with [Name] ends tonight ⏳"
 *    Body:    "Send something before midnight."
 *    Payload: { diaryId, streakDays }
 *    Action:  "Record now"  →  /record?targetDiaryId=X
 *    Rate:    1 per diary per day; only if streak >= 3; deliver 8 PM local
 *
 * 5. STREAK BROKE  (SaanjhNotificationType.streakBroke)
 *    Title:   "Your streak with [Name] paused 🌧"
 *    Body:    "Streaks can be rebuilt. Send something today."
 *    Payload: { diaryId, previousDays }
 *    Action:  "Start again"  →  /diary-thread?diaryId=X
 *    Rate:    1 per diary per break event; deliver next morning 9 AM
 *
 * 6. MILESTONE  (SaanjhNotificationType.milestone)
 *    Title:   "🔥 [N] days with [Name]!"
 *    Body:    "This is something rare. Keep going."
 *    Payload: { diaryId, milestone }
 *    Action:  "Share milestone"  →  /streak-milestone?diaryId=X
 *    Rate:    1 per milestone value (7, 14, 30, 60, 90, 100, 365)
 *
 * 7. ON THIS DAY  (SaanjhNotificationType.onThisDay)
 *    Title:   "📅 A year ago with [Name]"
 *    Body:    "[Transcript excerpt or 'A voice note from this day last year']"
 *    Payload: { diaryId, entryId }
 *    Action:  "Listen again"  →  /on-this-day
 *    Rate:    1 per day maximum; only if matching entry exists; deliver 10 AM
 *
 * 8. OCCASION  (SaanjhNotificationType.occasion)
 *    Title:   "[emoji] [Occasion] is [N] days away"
 *    Body:    "Send [Name] a special voice note."
 *    Payload: { diaryId, occasion, daysUntil }
 *    Action:  "Record now"  →  /record?targetDiaryId=X&occasionTag=Y
 *    Rate:    1 per occasion per year; deliver 3 days before the occasion
 *
 * ── NotificationPreferences (honour in all push sends) ──────────────────────
 *   preferences.quietHours      : suppress 10 PM – 8 AM local
 *   preferences.streakReminders : gate trigger types 4, 5
 *   preferences.milestones      : gate trigger type 6
 *   preferences.onThisDay       : gate trigger type 7
 *   preferences.occasions       : gate trigger type 8
 *
 * ── Global rate limit ────────────────────────────────────────────────────────
 *   Max 3 push notifications per user per calendar day across all types.
 *   Tracked server-side; client only enqueues, server decides to deliver.
 */

/// Centralised in-app notification trigger.
///
/// Attach once from HomeScreen after the banner key is available.
/// The service listens to DiaryStore + FlickerStore and drives the banner.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  NotificationBannerState? _banner;

  // ── Enabled flag — persisted in SharedPreferences ─────────────────────────
  static const _kNotifPref = 'pref_notif_on';
  bool _enabled = true;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifPref, value);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kNotifPref) ?? true;
  }

  // ── Already-notified trackers (in-memory; reset on app restart) ───────────

  final Set<String> _seenEntryReceipts = {}; // entryId
  final Set<String> _seenFlickerKeys = {};     // "diaryId:YYYY-MM-DD"
  final Set<String> _seenMilestoneKeys = {};  // "diaryId:N"
  final Set<String> _seenBreakIds = {};       // diaryId
  final Set<String> _seenReactionIds = {};    // reactionEntryId

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void attach({
    required DiaryStore diaryStore,
    required FlickerStore flickerStore,
    required NotificationBannerState banner,
  }) {
    _banner = banner;
    _loadPrefs(); // restore persisted enabled state

    // Listener's receipt — set callback on DiaryStore.
    diaryStore.onListenedReceipt = _onListenedReceipt;

    // Store change listeners.
    diaryStore.addListener(() => handleStoreChange(diaryStore));
    flickerStore.addListener(() => _checkFlickerReceived(flickerStore, diaryStore));
  }

  void detach(DiaryStore diaryStore) {
    if (diaryStore.onListenedReceipt == _onListenedReceipt) {
      diaryStore.onListenedReceipt = null;
    }
    _banner = null;
  }

  // ── Entry point for DiaryStore listener ───────────────────────────────────

  void handleStoreChange(DiaryStore store) {
    if (!_enabled) return;
    _checkListenerReceipts(store);
    _checkStreakMilestones(store);
    _checkStreakBreaks(store);
    _checkNewReactions(store);
  }

  // ── 9. New voice reaction received ───────────────────────────────────────

  void _checkNewReactions(DiaryStore store) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    for (final diary in store.diaries) {
      for (final entry in store.entriesFor(diary.id)) {
        // Only scan our own sent entries for incoming reactions.
        if (!entry.isMine) continue;
        for (final reaction in entry.reactions) {
          if (reaction.isMine) continue; // their reaction only
          if (_seenReactionIds.contains(reaction.id)) continue;
          _seenReactionIds.add(reaction.id);

          final d = entry.createdAt;
          final monthLabel = months[d.month];

          _banner?.show(
            '💛 ${diary.displayName} reacted to your $monthLabel memory',
            diary.id,
            SaanjhNotificationType.milestone,
          );
          return; // one banner at a time
        }
      }
    }
  }

  // ── 1. Listener receipt ───────────────────────────────────────────────────

  void _onListenedReceipt(String entryId, String diaryId) {
    if (_seenEntryReceipts.contains(entryId)) return;
    _seenEntryReceipts.add(entryId);

    final contact = DiaryStore.instance.diaries
        .cast<DiaryContact?>()
        .firstWhere((d) => d?.id == diaryId, orElse: () => null);
    final name = contact?.displayName ?? 'Someone';

    _banner?.show(
      '$name listened to your voice note 💛',
      diaryId,
      SaanjhNotificationType.listenerReceipt,
    );
  }

  // Called when DiaryStore notifies — scans for any newly-listened entries.
  void _checkListenerReceipts(DiaryStore store) {
    // The onListenedReceipt callback already handles individual receipts.
    // This method is a hook for future batch-check logic.
  }

  // ── 2 & 3. Flicker received / mutual flicker ──────────────────────────────

  void _checkFlickerReceived(FlickerStore flicker, DiaryStore store) {
    if (!_enabled) return;
    final now = DateTime.now();
    final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';

    for (final diary in store.diaries) {
      final received = flicker.receivedToday(diary.id);
      if (received == null) continue;

      final flickerKey = '${diary.id}:$dateKey';
      if (_seenFlickerKeys.contains(flickerKey)) continue;
      _seenFlickerKeys.add(flickerKey);

      final isMutual = flicker.hasMeFlickeredToday(diary.id);
      if (isMutual) {
        _banner?.show(
          'You and ${diary.displayName} both flickered today ✨',
          diary.id,
          SaanjhNotificationType.mutualFlicker,
        );
      } else {
        _banner?.show(
          '${diary.displayName} flickered you 💛',
          diary.id,
          SaanjhNotificationType.flickerReceived,
        );
      }
    }
  }

  // ── 6. Streak milestones ──────────────────────────────────────────────────

  void _checkStreakMilestones(DiaryStore store) {
    for (final diary in store.diaries) {
      final milestone = store.milestoneReached(diary.id);
      if (milestone == null) continue;

      final key = '${diary.id}:$milestone';
      if (_seenMilestoneKeys.contains(key)) continue;
      _seenMilestoneKeys.add(key);

      _banner?.show(
        '🔥 $milestone days with ${diary.displayName}! Keep going.',
        diary.id,
        SaanjhNotificationType.milestone,
      );
    }
  }

  // ── 4 & 5. Streak at risk / streak broke ─────────────────────────────────

  void _checkStreakBreaks(DiaryStore store) {
    for (final diary in store.diaries) {
      // Streak broke (read-once flag).
      if (store.hasBrokeStreak(diary.id) &&
          !_seenBreakIds.contains(diary.id)) {
        _seenBreakIds.add(diary.id);
        final prev = store.brokeStreakPreviousDays(diary.id);
        final label = prev > 0 ? '$prev-day ' : '';
        _banner?.show(
          'Your ${label}streak with ${diary.displayName} paused 🌧',
          diary.id,
          SaanjhNotificationType.streakBroke,
        );
        continue;
      }

      // Streak at risk (non-destructive check).
      if (store.streakAtRisk(diary.id)) {
        final riskKey = '${diary.id}:risk';
        if (_seenBreakIds.contains(riskKey)) continue;
        _seenBreakIds.add(riskKey);
        final days = store.streakDays(diary.id);
        _banner?.show(
          'Your $days-day streak with ${diary.displayName} ends tonight ⏳',
          diary.id,
          SaanjhNotificationType.streakAtRisk,
        );
      }
    }
  }
}


