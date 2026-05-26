/*
 * HOME SCREEN WIDGET SERVICE
 *
 * SETUP REQUIRED before widgets appear on device:
 *
 * Android:
 *   1. Confirm SaanjhWidgetProvider is registered in AndroidManifest.xml
 *      (already done — see <receiver> block added to AndroidManifest.xml).
 *   2. Run `flutter build apk` or `flutter run` — widgets appear in
 *      the system launcher's "Add Widget" sheet.
 *   3. No Developer Portal needed.
 *
 * iOS:
 *   1. In Xcode → Signing & Capabilities → add "App Groups" to BOTH
 *      the Runner target and the SaanjhWidget extension target.
 *      Use group ID: group.com.saanjh.saanjh
 *   2. In Apple Developer Portal → Identifiers → add the App Group.
 *   3. Build from Xcode (not `flutter run`) to include the extension.
 *   4. The widget reads from UserDefaults(suiteName: "group.com.saanjh.saanjh").
 */

import 'package:home_widget/home_widget.dart';

import '../state/diary_store.dart';
import '../state/flicker_store.dart';

class HomeWidgetService {
  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  static const _appGroupId = 'group.com.saanjh.saanjh';
  static const _androidWidgetName = 'SaanjhWidgetProvider';
  static const _iosWidgetName = 'SaanjhWidget';

  // ── Call once at app start to register the App Group ─────────────────────
  static Future<void> init() async {
    await HomeWidget.setAppGroupId(_appGroupId);
  }

  // ── Push fresh data to the home screen widget ─────────────────────────────
  Future<void> update() async {
    final diaryStore = DiaryStore.instance;
    final flickerStore = FlickerStore.instance;

    // Pick the most recent (top-of-list) diary.
    final diaries = diaryStore.diaries;
    if (diaries.isEmpty) return;

    final top = diaries.first;
    final diaryId = top.id;
    final contactName = top.displayName;
    final streakDays = diaryStore.streakDays(diaryId);

    // Flicker data for this diary.
    final received = flickerStore.receivedToday(diaryId);
    final wasHere = received != null;
    final pulseTime = received?.timeLabel ?? '';

    final now = DateTime.now();
    final lastUpdated =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // Save data — both Android (SharedPreferences) and iOS (UserDefaults) read these.
    await Future.wait([
      HomeWidget.saveWidgetData<String>('contact_name', contactName),
      HomeWidget.saveWidgetData<int>('streak_days', streakDays),
      HomeWidget.saveWidgetData<String>('pulse_time', pulseTime),
      HomeWidget.saveWidgetData<bool>('was_here', wasHere),
      HomeWidget.saveWidgetData<String>('last_updated', lastUpdated),
    ]);

    // Tell the OS to refresh the widget.
    // qualifiedAndroidName = full package path to the AppWidgetProvider class.
    await HomeWidget.updateWidget(
      androidName: _androidWidgetName,
      qualifiedAndroidName:
          'com.saanjh.saanjh.$_androidWidgetName',
      iOSName: _iosWidgetName,
    );
  }
}

