import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../backend/entries_api.dart';
import '../../../backend/flicker_api.dart';
import '../../../backend/notifications_api.dart';
import '../../router/app_routes.dart';
import '../../state/diary_store.dart';
import '../../state/flicker_store.dart';
import '../../state/send_queue_store.dart';
import '../../widgets/flicker_received_overlay.dart';
import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/home_widget_service.dart';
import '../../services/morning_service.dart';
import '../../services/notification_service.dart';
import '../../services/occasion_service.dart';
import '../../services/on_this_day_service.dart';
import '../../services/weekly_digest_service.dart';
import '../../widgets/morning_overlay.dart';
import '../../widgets/on_this_day_overlay.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/on_this_day_banner.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/saanjh_avatar.dart';
import '../../widgets/saanjh_shimmer.dart';
import '../../widgets/saanjh_badge.dart';
import '../../widgets/saanjh_dialog.dart';
import '../../widgets/saanjh_empty_state.dart';
import '../../widgets/saanjh_logo.dart';
import '../../widgets/saanjh_stagger.dart';
import '../me/me_screen.dart';
import '../memory_tree/memory_tree_screen.dart';
import '../flicker/flicker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _navIndex = 0;
  double _pagePos = 0.0;
  late final AnimationController _fabCtrl;
  late final PageController _pageCtrl;
  final _store = DiaryStore.instance;
  final _bannerKey = GlobalKey<NotificationBannerState>();

  // Flicker polling — fetches status every 30 s while foregrounded.
  Timer? _flickerPollTimer;
  // SSE subscriptions — one per connection for instant in-app delivery.
  final List<StreamSubscription<String>> _sseSubscriptions = [];
  // Local notification plugin — for background Flicker alerts.
  final _localNotif = FlutterLocalNotificationsPlugin();
  bool _localNotifReady = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    _fabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _pageCtrl = PageController();
    _pageCtrl.addListener(_onPageScroll);
    // NotificationService.attach() is called after first frame so the
    // banner GlobalKey is resolved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bannerState = _bannerKey.currentState;
      if (bannerState != null) {
        NotificationService.instance.attach(
          diaryStore: DiaryStore.instance,
          flickerStore: FlickerStore.instance,
          banner: bannerState,
        );
      }
    });
    // Home screen widget — initial push + re-push on any store change.
    HomeWidgetService.init().then((_) => HomeWidgetService.instance.update());
    DiaryStore.instance.addListener(_onStoreChangeForWidget);
    FlickerStore.instance.addListener(_onStoreChangeForWidget);
    UserStore.instance.addListener(_onUserStoreChange);
    WidgetsBinding.instance.addObserver(this);
    UserStore.instance.loadPrefs();
    // Load and retry anything that was queued while offline.
    SendQueueStore.instance.load().then((_) => SendQueueStore.instance.processQueue());
    // Register push-notification device token; queues automatically if offline.
    _registerDeviceToken();
    // Wire flicker callback before connections load so it's ready the moment
    // the overlay fires.
    FlickerStore.instance.onFlickerReceived = _onFlickerReceived;
    _initLocalNotif();
    // Chain flicker status load AFTER connections load so diaries are populated.
    // This ensures the overlay fires instantly on fresh launch instead of waiting
    // for the first 30-second poll tick.
    DiaryStore.instance.loadConnections().then((_) {
      if (!mounted) return;
      FlickerStore.instance
          .loadFlickerStatus(DiaryStore.instance.diaries)
          .then((_) { if (mounted) _startFlickerPollTimer(); });
      _startSseStreams();
    });
    OnThisDayService.instance.load();
    _maybeShowOnThisDayOrMorning();
    // Schedule weekly digest notification (runs on every open, guards internally).
    WeeklyDigestService.instance.init();
    // Show the in-app soft-ask for digest permission on first eligible Sunday.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WeeklyDigestService.instance.maybeShowPermissionAsk(context);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowJarMemory();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowAnniversaryBanner();
    });
    // FCM notification taps — both for backgrounded and terminated app states.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleFcmTaps();
    });
  }

  // Checks for an On This Day match; if found and not yet shown today,
  // shows the cinematic overlay first, then chains to the morning overlay.
  // Falls through to morning-only when there's no On This Day content.
  static const _kOnThisDayOverlayDate = 'on_this_day_overlay_date';

  Future<void> _maybeShowOnThisDayOrMorning() async {
    final matches = OnThisDayService.instance.matchesFor(
      DateTime.now().month, DateTime.now().day);

    if (matches.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final now = DateTime.now();
      final todayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}'
          '-${now.day.toString().padLeft(2, '0')}';

      if (prefs.getString(_kOnThisDayOverlayDate) != todayKey) {
        await prefs.setString(_kOnThisDayOverlayDate, todayKey);
        if (!mounted) return;

        // Resolve the contact for this entry.
        final entry = matches.first;
        DiaryContact? contact;
        for (final d in DiaryStore.instance.diaries) {
          if (d.id == entry.diaryId) { contact = d; break; }
        }

        // Show the cinematic overlay, then chain to morning overlay after
        // the user dismisses it.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) =>
                OnThisDayOverlay(entry: entry, contact: contact),
          );
          if (mounted) _maybeShowMorningOverlay();
        });
        return;
      }
    }

    // No On This Day content (or already shown today) — go straight to
    // morning overlay if applicable.
    _maybeShowMorningOverlay();
  }

  Future<void> _maybeShowMorningOverlay() async {
    if (!MorningService.instance.isMorning) return;
    final firstOpen = await MorningService.instance.isFirstOpenToday;
    if (!firstOpen || !mounted) return;
    await MorningService.instance.markOpened();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const MorningOverlay(),
      );
    });
  }

  Future<void> _maybeShowJarMemory() async {
    // Don't compete with morning ritual.
    if (MorningService.instance.isMorning) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    // Time gate: surface at most once every 18 hours so it becomes a
    // reliable daily habit rather than a random surprise.
    const kLastShownMs  = 'jar_last_shown_ms';
    const kLastShownId  = 'jar_last_shown_entry_id';
    const kGapMs        = 18 * 60 * 60 * 1000; // 18 h in ms

    final lastShownMs = prefs.getInt(kLastShownMs);
    if (lastShownMs != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastShownMs;
      if (elapsed < kGapMs) return;
    }

    // Collect every jarred entry across all diaries into a flat list.
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final store = DiaryStore.instance;
    final pairs = <({DiaryContact diary, String entryId})>[];
    for (final diary in store.diaries) {
      for (final id in store.jarredFor(diary.id)) {
        pairs.add((diary: diary, entryId: id));
      }
    }
    if (pairs.isEmpty) return;

    // Rotate in order so every starred memory surfaces over time.
    // If the jar changes between sessions, modulo keeps the index valid.
    final lastShownEntryId = prefs.getString(kLastShownId);
    int idx = 0;
    if (lastShownEntryId != null) {
      final lastIdx =
          pairs.indexWhere((p) => p.entryId == lastShownEntryId);
      if (lastIdx != -1) idx = (lastIdx + 1) % pairs.length;
    }

    final pair = pairs[idx];
    final entries = store.entriesFor(pair.diary.id);
    try {
      final entry = entries.firstWhere((e) => e.id == pair.entryId);
      final d = entry.createdAt;
      final dateStr = '${months[d.month]} ${d.day}';
      _bannerKey.currentState?.show(
        '✨ A memory from your jar — ${pair.diary.displayName}, $dateStr',
        pair.diary.id,
        SaanjhNotificationType.onThisDay,
      );
      // Persist both the timestamp and the entry shown so next session
      // knows where to continue the rotation.
      await prefs.setInt(
          kLastShownMs, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(kLastShownId, pair.entryId);
    } catch (_) {}
  }

  void _maybeShowAnniversaryBanner() {
    final anniversaries = DiaryStore.instance.diaryAnniversaries;
    if (anniversaries.isEmpty) return;

    final entry = anniversaries.entries.first;
    final diaryId = entry.key;
    final years = entry.value;

    final contact = DiaryStore.instance.diaries
        .cast<DiaryContact?>()
        .firstWhere((d) => d?.id == diaryId, orElse: () => null);
    final name = contact?.displayName ?? 'them';

    _bannerKey.currentState?.show(
      '🎂 $years year${years > 1 ? 's' : ''} with $name ♥',
      diaryId,
      SaanjhNotificationType.milestone,
      overrideRoute: AppRoutes.anniversary,
      overrideExtra: {
        'diaryId': diaryId,
        'contactName': name,
        'years': years,
      },
    );
  }

  void _onStoreChangeForWidget() => HomeWidgetService.instance.update();
  void _onUserStoreChange() => setState(() {});

  // Fires on every scroll pixel during page swipe. Only triggers a rebuild
  // when a tab crosses the visibility boundary (0.0 = fully off, 1.0 = overlap).
  void _onPageScroll() {
    if (!_pageCtrl.hasClients) return;
    final p = _pageCtrl.page ?? _navIndex.toDouble();
    for (int i = 1; i <= 3; i++) {
      final wasVisible = (_pagePos - i).abs() < 1.0;
      final nowVisible = (p - i).abs() < 1.0;
      if (wasVisible != nowVisible) {
        setState(() => _pagePos = p);
        return;
      }
    }
    _pagePos = p;
  }

  @override
  void dispose() {
    _flickerPollTimer?.cancel();
    _cancelSseStreams();
    if (FlickerStore.instance.onFlickerReceived == _onFlickerReceived) {
      FlickerStore.instance.onFlickerReceived = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.detach(DiaryStore.instance);
    DiaryStore.instance.removeListener(_onStoreChangeForWidget);
    FlickerStore.instance.removeListener(_onStoreChangeForWidget);
    UserStore.instance.removeListener(_onUserStoreChange);
    _fabCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SendQueueStore.instance.processQueue();
      FlickerStore.instance.loadFlickerStatus(DiaryStore.instance.diaries);
      _startFlickerPollTimer();
      _startSseStreams(); // reconnect after backgrounding
    } else if (state == AppLifecycleState.paused) {
      _flickerPollTimer?.cancel();
      _flickerPollTimer = null;
      _cancelSseStreams(); // release TCP connections while backgrounded
    }
  }

  void _startFlickerPollTimer() {
    _flickerPollTimer?.cancel();
    _flickerPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        FlickerStore.instance.loadFlickerStatus(DiaryStore.instance.diaries);
      }
    });
  }

  // ── SSE streams (one per connection) ──────────────────────────────────────

  void _startSseStreams() {
    _cancelSseStreams();
    for (final diary in DiaryStore.instance.diaries) {
      final sub = FlickerApi.instance
          .subscribeToEvents(diary.id)
          .listen(
            (raw) => _onSseEvent(diary.id, diary.name, raw),
            onError: (_) {}, // stream retries internally
            cancelOnError: false,
          );
      _sseSubscriptions.add(sub);
    }
  }

  void _cancelSseStreams() {
    for (final s in _sseSubscriptions) { s.cancel(); }
    _sseSubscriptions.clear();
  }

  void _onSseEvent(String diaryId, String contactName, String rawJson) {
    if (!mounted) return;
    try {
      final event = json.decode(rawJson) as Map<String, dynamic>;
      final type = event['type'] as String?;
      if (type == 'flicker_received') {
        FlickerStore.instance.handleSseFlickerReceived(
          diaryId: diaryId,
          personName: event['sender_name'] as String? ?? contactName,
          sentAt: DateTime.tryParse(event['sent_at'] as String? ?? '') ?? DateTime.now(),
        );
      } else if (type == 'new_entry') {
        final entryId = event['entry_id'] as String?;
        final authorId = event['author_id'] as String?;
        if (entryId != null && authorId != null) {
          _onNewEntryReceived(diaryId, entryId);
        }
      }
    } catch (_) {}
  }

  Future<void> _onNewEntryReceived(String diaryId, String entryId) async {
    if (!mounted) return;
    if (DiaryStore.instance.entriesFor(diaryId).any((e) => e.id == entryId)) return;
    try {
      final item = await EntriesApi.instance.getEntry(diaryId, entryId);
      if (!mounted) return;
      if (DiaryStore.instance.entriesFor(diaryId).any((e) => e.id == entryId)) return;
      final myUserId = UserStore.instance.userId;
      final dateStr = (item['recorded_at'] ?? item['created_at']) as String?;
      DiaryStore.instance.addEntry(DiaryEntry(
        id: item['id'] as String,
        diaryId: diaryId,
        isMine: (item['author_id'] as String?) == myUserId,
        type: item['entry_type'] as String? ?? 'voice',
        path: '',
        transcript: item['transcription'] as String?,
        createdAt: dateStr != null ? DateTime.parse(dateStr) : DateTime.now(),
        durationSeconds: item['duration_seconds'] as int? ?? 0,
        isExpired: item['is_expired'] as bool? ?? false,
        listenedAt: (item['play_count'] as int? ?? 0) > 0
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : null,
      ));
    } catch (_) {}
  }

  // ── Flicker received ───────────────────────────────────────────────────────

  void _onFlickerReceived(FlickerRecord record) {
    if (!mounted) return;
    final contact = DiaryStore.instance.diaries
        .cast<DiaryContact?>()
        .firstWhere((d) => d?.id == record.diaryId, orElse: () => null);
    if (contact == null) return;

    // Show the full-screen emotional overlay.
    FlickerReceivedOverlay.show(
      context,
      record: record,
      avatarColor: contact.avatarColor,
      senderInitial: contact.initial,
      onSendBack: () => context.push(
        AppRoutes.flicker,
        extra: {'targetDiaryId': record.diaryId},
      ),
    );

    // Also fire a local notification for ambient awareness
    // (visible as a system heads-up when the user is on another screen).
    _showFlickerLocalNotif(record.personName, record.diaryId);
  }

  Future<void> _initLocalNotif() async {
    if (_localNotifReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotif.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _localNotifReady = true;
  }

  Future<void> _showFlickerLocalNotif(String name, String diaryId) async {
    if (!_localNotifReady) return;
    const android = AndroidNotificationDetails(
      'saanjh_flicker',
      'Flicker Notifications',
      channelDescription: 'Real-time Flicker alerts',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: false, // haptics handled by overlay
    );
    const ios = DarwinNotificationDetails(presentAlert: true, presentSound: false);
    await _localNotif.show(
      42, // fixed ID — replaces any previous flicker notif
      '$name sent you a Flicker ✨',
      'They\'re thinking of you right now.',
      const NotificationDetails(android: android, iOS: ios),
      payload: 'flicker:$diaryId',
    );
  }

  // ── FCM notification tap handling ─────────────────────────────────────────

  void _handleFcmTaps() {
    // App was in background — user tapped the FCM notification to open it.
    FirebaseMessaging.onMessageOpenedApp.listen(_routeFcmMessage);

    // App was terminated — FCM notification was the launch trigger.
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) _routeFcmMessage(msg);
    });

    // Foreground FCM: suppress default heads-up (our overlay already shows).
    FirebaseMessaging.onMessage.listen((msg) {
      // Overlay is driven by polling — no duplicate action needed here.
      // The local notification from _showFlickerLocalNotif handles ambient alerts.
    });

    // Refresh FCM token on rotation (Firebase can rotate tokens).
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      _registerDeviceToken();
    });
  }

  void _routeFcmMessage(RemoteMessage message) {
    if (!mounted) return;
    final type    = message.data['type']     as String?;
    final diaryId = message.data['diary_id'] as String?;

    if (type == 'flicker' && diaryId != null) {
      context.push(AppRoutes.flicker, extra: {'targetDiaryId': diaryId});
    } else if (diaryId != null) {
      context.push(AppRoutes.diaryThread, extra: {'diaryId': diaryId});
    }
  }

  Future<void> _registerDeviceToken() async {
    try {
      final info = DeviceInfoPlugin();
      final String deviceId;
      final String platform;
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        deviceId = a.id;
        platform = 'android';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        deviceId = i.identifierForVendor ?? i.name;
        platform = 'ios';
      } else {
        return; // Desktop — no push notifications
      }

      final fcmToken = await FirebaseMessaging.instance.getToken() ?? '';
      if (fcmToken.isEmpty) return;

      try {
        await NotificationsApi.instance.registerDeviceToken(
          deviceId: deviceId,
          fcmToken: fcmToken,
          platform: platform,
        );
      } catch (_) {
        // Offline — queue for retry when connectivity returns.
        await SendQueueStore.instance.enqueueTokenReg(
          deviceId: deviceId,
          fcmToken: fcmToken,
          platform: platform,
        );
      }
    } catch (_) {}
  }

  void _onNavTap(int i) {
    if (_navIndex == i) return;
    HapticFeedback.selectionClick();
    setState(() => _navIndex = i);
    _pageCtrl.animateToPage(
      i,
      duration: AppMotion.page,
      curve: Curves.easeInOutCubic,
    );
  }

  void _showRecordPicker(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RecordPickerSheet(
        onVoice: () {
          Navigator.pop(context);
          context.push(AppRoutes.voiceRecord, extra: {'isVideo': false});
        },
        onVideo: () {
          Navigator.pop(context);
          context.push(AppRoutes.voiceRecord, extra: {'isVideo': true});
        },
        onBroadcast: () {
          Navigator.pop(context);
          _showBroadcastSheet(context);
        },
      ),
    );
  }

  void _showBroadcastSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BroadcastSheet(
        diaries: _store.diaries,
        onRecord: (ids, names, isVideo) {
          context.push(AppRoutes.voiceRecord, extra: {
            'isVideo': isVideo,
            'broadcastTo': ids,
            'broadcastNames': names,
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Simplified home for loved ones who prefer a minimal interface.
    if (UserStore.instance.isSimpleMode) {
      final diaries = _store.diaries;
      final diary = diaries.isNotEmpty ? diaries.first : null;
      return _ParentModeHome(diary: diary);
    }

    return PopScope(
      canPop: _navIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onNavTap(0);
      },
      child: ListenableBuilder(
      listenable: _store,
      builder: (_, w) {
        final diaries = _store.diaries;

        return Scaffold(
          backgroundColor: AppColors.ink,
          body: Stack(
            children: [
              PageView(
                controller: _pageCtrl,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) {
                  if (_navIndex == i) return;
                  HapticFeedback.selectionClick();
                  setState(() => _navIndex = i);
                },
                children: [
                  _KeepAlive(child: _DiariesTab(diaries: diaries)),
                  _KeepAlive(
                    child: TickerMode(
                      enabled: (_pagePos - 1).abs() < 1.0,
                      child: const FlickerScreen(isEmbedded: true),
                    ),
                  ),
                  _KeepAlive(
                    child: TickerMode(
                      enabled: (_pagePos - 2).abs() < 1.0,
                      child: const MemoryTreeScreen(isEmbedded: true),
                    ),
                  ),
                  _KeepAlive(
                    child: TickerMode(
                      enabled: (_pagePos - 3).abs() < 1.0,
                      child: const MeScreen(isEmbedded: true),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0, left: 0, right: 0,
                child: NotificationBanner(key: _bannerKey),
              ),
            ],
          ),
          floatingActionButton: _navIndex == 0 && diaries.isNotEmpty
              ? ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _fabCtrl,
                    curve: AppMotion.easeSpring,
                  ),
                  child: _RecordFab(
                    onTap: () => _showRecordPicker(context),
                    onLongPress: () => context.push(
                      AppRoutes.voiceRecord,
                      extra: {'isVideo': false},
                    ),
                  ),
                )
              : null,
          bottomNavigationBar: _BottomNav(
            index: _navIndex,
            onTap: _onNavTap,
          ),
        );
      },
      ),
    );
  }
}

// ─── Parent mode home ─────────────────────────────────────────────────────────

class _ParentModeHome extends StatefulWidget {
  final DiaryContact? diary;
  const _ParentModeHome({this.diary});

  @override
  State<_ParentModeHome> createState() => _ParentModeHomeState();
}

class _ParentModeHomeState extends State<_ParentModeHome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  Widget _fade(double delay, Widget child) {
    final anim = CurvedAnimation(
      parent: _enterCtrl,
      curve: Interval(delay, (delay + 0.55).clamp(0.0, 1.0),
          curve: AppMotion.easeOut),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
            offset: Offset(0, 16 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.diary?.displayName ?? '';
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(28, 28, 28, bottom + 16),
          child: Column(
            children: [
              // Contact avatar + greeting
              _fade(
                0.0,
                Column(
                  children: [
                    const SizedBox(height: 12),
                    if (widget.diary != null)
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              AppColors.ember.withValues(alpha: 0.18),
                          border: Border.all(
                              color: AppColors.emberWarm
                                  .withValues(alpha: 0.35),
                              width: 2),
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty
                                ? name.trim()[0].toUpperCase()
                                : '?',
                            style: AppTypography.title(
                                    size: 40,
                                    weight: FontWeight.w600)
                                .copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.emberWarm),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      name.isNotEmpty ? 'Hello, $name' : 'Saanjh',
                      style: AppTypography.title(
                          size: 30, weight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your shared diary',
                      style: AppTypography.serifItalic(
                          size: 16, color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Giant Listen button
              _fade(
                0.20,
                _ParentActionButton(
                  icon: Icons.play_circle_fill_rounded,
                  label: name.isNotEmpty
                      ? 'Listen to $name'
                      : 'Listen',
                  color: AppColors.azure,
                  onTap: widget.diary != null
                      ? () => context.push(AppRoutes.diaryThread,
                          extra: {'diaryId': widget.diary!.id})
                      : null,
                ),
              ),

              const SizedBox(height: 16),

              // Giant Record button
              _fade(
                0.32,
                _ParentActionButton(
                  icon: Icons.mic_rounded,
                  label: name.isNotEmpty
                      ? 'Record for $name'
                      : 'Record',
                  color: AppColors.ember,
                  onTap: widget.diary != null
                      ? () => context.push(AppRoutes.voiceRecord, extra: {
                            'isVideo': false,
                            'targetDiaryId': widget.diary!.id,
                            'autoStart': true,
                          })
                      : null,
                ),
              ),

              const Spacer(),

              // Exit parent mode
              _fade(
                0.50,
                TextButton(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await UserStore.instance.setSimpleMode(false);
                  },
                  child: Text(
                    'Exit simplified view',
                    style: AppTypography.label(
                        size: 12, color: AppColors.textFaint),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParentActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ParentActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  State<_ParentActionButton> createState() => _ParentActionButtonState();
}

class _ParentActionButtonState extends State<_ParentActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null;
    return GestureDetector(
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: active
          ? (_) {
              setState(() => _pressed = false);
              HapticFeedback.mediumImpact();
              widget.onTap!();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        width: double.infinity,
        height: 96,
        decoration: BoxDecoration(
          color: _pressed
              ? widget.color.withValues(alpha: 0.22)
              : widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _pressed
                ? widget.color.withValues(alpha: 0.60)
                : widget.color.withValues(alpha: 0.30),
            width: 1.5,
          ),
          boxShadow: _pressed
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, size: 36, color: widget.color),
            const SizedBox(width: 14),
            Text(
              widget.label,
              style: AppTypography.title(size: 20, weight: FontWeight.w600)
                  .copyWith(color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Diaries tab (tab 0) ──────────────────────────────────────────────────────

class _DiariesTab extends StatefulWidget {
  final List<DiaryContact> diaries;
  const _DiariesTab({required this.diaries});

  @override
  State<_DiariesTab> createState() => _DiariesTabState();
}

class _DiariesTabState extends State<_DiariesTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selectedIds = {};

  bool get _isSelecting => _selectedIds.isNotEmpty;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Returns matching diaries + transcript excerpt per diary id when matched via transcript.
  ({List<DiaryContact> diaries, Map<String, String> transcriptMatches})
      get _filteredWithMatches {
    if (_query.isEmpty) {
      return (diaries: widget.diaries, transcriptMatches: {});
    }
    final q = _query.toLowerCase();
    final results = <DiaryContact>[];
    final matches = <String, String>{};

    for (final d in widget.diaries) {
      if (d.displayName.toLowerCase().contains(q) ||
          d.relation.toLowerCase().contains(q)) {
        results.add(d);
        continue;
      }
      // Search entry transcripts
      for (final e in DiaryStore.instance.entriesFor(d.id)) {
        final t = e.transcript;
        if (t != null && t.toLowerCase().contains(q)) {
          final idx = t.toLowerCase().indexOf(q);
          final start = (idx - 15).clamp(0, t.length);
          final end = (idx + 45).clamp(0, t.length);
          matches[d.id] = '"${t.substring(start, end)}"';
          results.add(d);
          break;
        }
      }
    }
    return (diaries: results, transcriptMatches: matches);
  }

  List<DiaryContact> get _filtered => _filteredWithMatches.diaries;

  // ── Selection ──────────────────────────────────────────────────────────────

  void _enterSelection(String id) {
    HapticFeedback.mediumImpact();
    setState(() => _selectedIds.add(id));
  }

  void _toggleSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIds.contains(id)
          ? _selectedIds.remove(id)
          : _selectedIds.add(id);
    });
  }

  void _exitSelection() => setState(() => _selectedIds.clear());

  void _selectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(widget.diaries.map((d) => d.id));
    });
  }

  // ── Bulk actions ───────────────────────────────────────────────────────────

  void _pinSelected() {
    for (final id in _selectedIds) { DiaryStore.instance.togglePin(id); }
    _exitSelection();
  }

  void _muteSelected() {
    for (final id in _selectedIds) { DiaryStore.instance.toggleMute(id); }
    _exitSelection();
  }

  void _archiveSelected() {
    for (final id in _selectedIds) { DiaryStore.instance.archive(id); }
    _exitSelection();
  }

  void _deleteSelected(BuildContext ctx) async {
    final names = _selectedIds
        .map((id) {
          try {
            return widget.diaries.firstWhere((d) => d.id == id).name;
          } catch (_) {
            return id;
          }
        })
        .join(', ');
    final confirmed = await SaanjhDialog.showDestructive(
      ctx,
      title: 'Delete ${_selectedIds.length == 1 ? 'diary' : 'diaries'}?',
      body: 'This will remove all voice notes with $names. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    for (final id in _selectedIds) { DiaryStore.instance.remove(id); }
    _exitSelection();
  }

  void _favouriteSelected() {
    for (final id in _selectedIds) { DiaryStore.instance.toggleFavourite(id); }
    _exitSelection();
  }

  void _lockSelected() {
    for (final id in _selectedIds) { DiaryStore.instance.toggleLock(id); }
    _exitSelection();
  }

  void _clearChatSelected(BuildContext ctx) async {
    final confirmed = await SaanjhDialog.showDestructive(
      ctx,
      title: 'Clear chat?',
      body: 'All messages will be removed. This cannot be undone.',
      confirmLabel: 'Clear',
    );
    if (!confirmed || !mounted) return;
    for (final id in _selectedIds) { DiaryStore.instance.clearChat(id); }
    _exitSelection();
  }

  void _blockSelected(BuildContext ctx) async {
    final confirmed = await SaanjhDialog.showDestructive(
      ctx,
      title: 'Block contact?',
      body: 'They will be removed from your diaries. You can unblock them later.',
      confirmLabel: 'Block',
    );
    if (!confirmed || !mounted) return;
    for (final id in _selectedIds) { DiaryStore.instance.block(id); }
    _exitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final hasData = widget.diaries.isNotEmpty;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.6),
                radius: 0.9,
                colors: [
                  AppColors.ember.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Column(
          children: [
            // Contextual top bar: selection mode ↔ normal mode
            if (_isSelecting)
              _SelectionHeader(
                count: _selectedIds.length,
                onExit: _exitSelection,
                onPin: _pinSelected,
                onMute: _muteSelected,
                onArchive: _archiveSelected,
                onDelete: () => _deleteSelected(context),
                onFavourite: _favouriteSelected,
                onLock: _lockSelected,
                onClearChat: () => _clearChatSelected(context),
                onBlock: () => _blockSelected(context),
              )
            else
              _TopHeader(
                onDiscover: () => context.push(AppRoutes.discover),
                onProfile: () => context.push(AppRoutes.profile),
                onSelectAll: _selectAll,
              ),

            if (hasData && !_isSelecting) ...[
              // Occasion banner — highest priority, shown above On This Day
              if (_query.isEmpty) const _OccasionBanner(),
              // On This Day banner — shown above search bar when a past-year memory matches today
              if (_query.isEmpty)
                ListenableBuilder(
                  listenable: DiaryStore.instance,
                  builder: (_, _) {
                    final entry = DiaryStore.instance.onThisDayEntry;
                    if (entry == null) return const SizedBox.shrink();
                    return OnThisDayBanner(entry: entry);
                  },
                ),
              // Search bar sits above everything — filters both pulse strip and diaries
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 2, AppSpacing.xl, 0),
                child: _DiarySearchField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              ListenableBuilder(
                listenable: DiaryStore.instance,
                builder: (_, _) => DiaryStore.instance.isLoading
                    ? const _FlickerStripSkeleton()
                    : _FlickerStrip(
                        diaries: widget.diaries,
                        searchQuery: _query,
                      ),
              ),
            ],
            Expanded(
              child: ListenableBuilder(
                listenable: DiaryStore.instance,
                builder: (_, _) {
                  if (DiaryStore.instance.isLoading) {
                    return const _DiaryListSkeleton();
                  }
                  if (!hasData) {
                    return _EmptyState(
                      onDiscover: () => context.push(AppRoutes.discover),
                    );
                  }
                  if (filtered.isEmpty) {
                    return _DiaryNoResults(query: _query);
                  }
                  final fm = _filteredWithMatches;
                  return _DiaryList(
                    diaries: fm.diaries,
                    transcriptMatches: fm.transcriptMatches,
                    isSelecting: _isSelecting,
                    selectedIds: _selectedIds,
                    onEnterSelection: _enterSelection,
                    onToggleSelection: _toggleSelection,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Flicker strip ──────────────────────────────────────────────────────────────

class _FlickerStrip extends StatelessWidget {
  final List<DiaryContact> diaries;
  final String searchQuery;
  const _FlickerStrip({required this.diaries, this.searchQuery = ''});

  List<DiaryContact> _filtered() {
    if (searchQuery.isEmpty) return diaries;
    final q = searchQuery.toLowerCase();
    return diaries
        .where((d) => d.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (diaries.isEmpty) return const SizedBox.shrink();

    final visible = _filtered();

    // Collapse when a query is active but no pulse contacts match
    if (searchQuery.isNotEmpty && visible.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: FlickerStore.instance,
      builder: (_, w) {
        // Sort: received-not-sent first, then streak, then rest
        final ps = FlickerStore.instance;
        final sorted = [...visible]..sort((a, b) {
            int score(DiaryContact d) {
              if (ps.receivedToday(d.id) != null && !ps.hasMeFlickeredToday(d.id)) return 2;
              if (DiaryStore.instance.streakDays(d.id) > 0) return 1;
              return 0;
            }
            return score(b).compareTo(score(a));
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.emberWarm,
                      boxShadow: AppShadows.dotGlow(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    searchQuery.isNotEmpty
                        ? 'FLICKER · ${sorted.length}'
                        : 'FLICKER',
                    style: AppTypography.eyebrow(
                        size: 9.5, color: AppColors.emberBright),
                  ),
                  const Spacer(),
                  // "Pulse all" only shown when not filtering
                  if (searchQuery.isEmpty)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.push(AppRoutes.flicker);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite_rounded,
                            size: 11, color: AppColors.emberWarm),
                        const SizedBox(width: 4),
                        Text(
                          'Flicker all',
                          style: AppTypography.label(
                              size: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 78,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                itemCount: sorted.length,
                itemBuilder: (_, i) => _FlickerAvatarChip(
                  contact: sorted[i],
                  store: ps,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push(
                      AppRoutes.flicker,
                      extra: {'targetDiaryId': sorted[i].id},
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }
}

class _FlickerAvatarChip extends StatelessWidget {
  final DiaryContact contact;
  final FlickerStore store;
  final VoidCallback onTap;

  const _FlickerAvatarChip({
    required this.contact,
    required this.store,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final received = store.receivedToday(contact.id);
    final mePulsed = store.hasMeFlickeredToday(contact.id);
    final mutual = received != null && mePulsed;
    final receivedNotSent = received != null && !mePulsed;
    final streakDays = DiaryStore.instance.streakDays(contact.id);

    final Color ringColor;
    final double ringAlpha;
    if (mutual) {
      ringColor = AppColors.successGreen;
      ringAlpha = 0.72;
    } else if (receivedNotSent) {
      ringColor = AppColors.emberWarm;
      ringAlpha = 0.90;
    } else if (streakDays > 0) {
      ringColor = AppColors.emberWarm;
      ringAlpha = 0.28;
    } else {
      ringColor = Colors.white;
      ringAlpha = 0.10;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        contact.avatarColor,
                        contact.avatarColor.withValues(alpha: 0.68),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: ringColor.withValues(alpha: ringAlpha),
                      width: 2,
                    ),
                    boxShadow: ringAlpha > 0.3
                        ? [
                            BoxShadow(
                              color: ringColor.withValues(alpha: ringAlpha * 0.45),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: mePulsed && !mutual
                        ? Icon(
                            Icons.favorite_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.55),
                          )
                        : Text(
                            contact.initial,
                            style: AppTypography.title(size: 17).copyWith(
                              color: Colors.white,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                  ),
                ),
                // Incoming pulse dot
                if (receivedNotSent)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.emberWarm,
                        border:
                            Border.all(color: AppColors.ink, width: 1.5),
                        boxShadow: AppShadows.dotGlow(intensity: 0.7),
                      ),
                    ),
                  ),
                // Mutual check
                if (mutual)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.successGreen,
                        border: Border.all(color: AppColors.ink, width: 1.5),
                      ),
                      child: const Icon(Icons.favorite_rounded,
                          size: 8, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              contact.name.split(' ').first,
              style: AppTypography.label(
                size: 10.5,
                color: receivedNotSent
                    ? AppColors.emberBright
                    : Colors.white.withValues(alpha: 0.35),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Selection top bar ────────────────────────────────────────────────────────

class _SelectionHeader extends StatelessWidget {
  final int count;
  final VoidCallback onExit;
  final VoidCallback onPin;
  final VoidCallback onMute;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onFavourite;
  final VoidCallback onLock;
  final VoidCallback onClearChat;
  final VoidCallback onBlock;

  const _SelectionHeader({
    required this.count,
    required this.onExit,
    required this.onPin,
    required this.onMute,
    required this.onArchive,
    required this.onDelete,
    required this.onFavourite,
    required this.onLock,
    required this.onClearChat,
    required this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        // Vertical padding matches _TopHeader (16 top + 12 bottom) so the list
        // never shifts when toggling selection mode.
        padding: const EdgeInsets.fromLTRB(4, 16, 6, 12),
        child: SizedBox(
          height: 42, // matches _TopHeader two-line column height (eyebrow+gap+title-24)
          child: Row(
          children: [
            // Exit selection
            IconButton(
              icon: const Icon(Icons.close_rounded),
              color: AppColors.text,
              onPressed: () {
                HapticFeedback.selectionClick();
                onExit();
              },
            ),
            // Count
            Expanded(
              child: Text(
                count == 1 ? '1 selected' : '$count selected',
                style: AppTypography.title(size: 20),
              ),
            ),
            // Pin
            _SelBtn(icon: Icons.push_pin_rounded, tooltip: 'Pin', onTap: onPin),
            // Mute
            _SelBtn(
                icon: Icons.notifications_off_outlined,
                tooltip: 'Mute',
                onTap: onMute),
            // Archive
            _SelBtn(
                icon: Icons.archive_outlined,
                tooltip: 'Archive',
                onTap: onArchive),
            // Delete
            _SelBtn(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete',
                color: AppColors.destructive,
                onTap: onDelete),
            // More — bottom sheet avoids popup overflow
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => _SelectionMoreSheet(
                    onFavourite: () { Navigator.pop(context); onFavourite(); },
                    onLock: () { Navigator.pop(context); onLock(); },
                    onClearChat: () { Navigator.pop(context); onClearChat(); },
                    onBlock: () { Navigator.pop(context); onBlock(); },
                    onShortcut: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Home-screen shortcuts coming soon.',
                            style: AppTypography.label(size: 13, color: Colors.white)),
                        backgroundColor: AppColors.modalSurface,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ));
                    },
                    onContact: () { Navigator.pop(context); context.push(AppRoutes.discover); },
                  ),
                );
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                child: Icon(Icons.more_vert_rounded,
                    size: 20, color: AppColors.textMuted),
              ),
            ),
          ],
          ),   // Row
        ),     // SizedBox
      ),
    );
  }

}

// ─── Selection more sheet (replaces overflowing PopupMenuButton) ──────────────

class _SelectionMoreSheet extends StatelessWidget {
  final VoidCallback onFavourite;
  final VoidCallback onLock;
  final VoidCallback onClearChat;
  final VoidCallback onBlock;
  final VoidCallback onShortcut;
  final VoidCallback onContact;

  const _SelectionMoreSheet({
    required this.onFavourite,
    required this.onLock,
    required this.onClearChat,
    required this.onBlock,
    required this.onShortcut,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.80;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.modalSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),

            // Scrollable action list — handles short screens gracefully
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MoreAction(Icons.add_to_home_screen_rounded,
                        'Add diary shortcut', onShortcut),
                    _MoreDivider(),
                    _MoreAction(Icons.person_outline_rounded,
                        'View contact', onContact),
                    _MoreDivider(),
                    _MoreAction(Icons.star_outline_rounded,
                        'Add to favourite', onFavourite),
                    _MoreDivider(),
                    _MoreAction(
                        Icons.lock_outline_rounded, 'Lock diary', onLock),
                    _MoreDivider(),
                    _MoreAction(Icons.cleaning_services_outlined,
                        'Clear chat', onClearChat),
                    _MoreDivider(),
                    _MoreAction(Icons.block_rounded, 'Block', onBlock,
                        color: AppColors.destructive),
                  ],
                ),
              ),
            ),

            // Safe area bottom padding — always respected regardless of scroll
            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );
  }
}

class _MoreAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MoreAction(this.icon, this.label, this.onTap, {this.color});

  @override
  State<_MoreAction> createState() => _MoreActionState();
}

class _MoreActionState extends State<_MoreAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? AppColors.text;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        color: _pressed ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(widget.icon, size: 20, color: c.withValues(alpha: 0.85)),
            const SizedBox(width: 14),
            Text(widget.label,
                style: AppTypography.body(
                    size: 15, weight: FontWeight.w500, color: c)),
          ],
        ),
      ),
    );
  }
}

class _MoreDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 54, color: Colors.white.withValues(alpha: 0.05));
}

class _SelBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  const _SelBtn(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color ?? AppColors.textMuted,
      tooltip: tooltip,
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}

class _DiarySearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _DiarySearchField(
      {required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.08), width: 1),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTypography.body(size: 14),
        cursorColor: AppColors.emberWarm,
        decoration: InputDecoration(
          hintText: 'Search people & chats…',
          hintStyle:
              AppTypography.body(size: 14, color: AppColors.textFaint),
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: AppColors.textFaint),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _DiaryNoResults extends StatelessWidget {
  final String query;
  const _DiaryNoResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No diaries matching\n"$query"',
        style: AppTypography.body(size: 17, color: AppColors.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatefulWidget {
  final VoidCallback onDiscover;
  const _EmptyState({required this.onDiscover});

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with TickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final AnimationController _ringsCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _ringsCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _ringsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _enterCtrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_enterCtrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 20 * (1 - t)), child: child),
        );
      },
      child: SaanjhEmptyState(
        visual: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SaanjhLogo(size: 72),
            const SizedBox(height: 16),
            // Animated pulse rings below the logo
            SizedBox(
              width: 160,
              height: 60,
              child: AnimatedBuilder(
                animation: _ringsCtrl,
                builder: (_, _) => CustomPaint(
                  painter: _FlickerRingsPainter(_ringsCtrl.value),
                ),
              ),
            ),
          ],
        ),
        title: 'Your diaries\nare waiting.',
        body: 'Find family and friends already on Saanjh,\nor invite someone to start a diary with.',
        ctaLabel: 'Find connections →',
        onCta: widget.onDiscover,
        secondaryLabel: 'Invite someone →',
        onSecondary: () => context.push(AppRoutes.invite),
      ),
    );
  }
}

class _FlickerRingsPainter extends CustomPainter {
  final double progress; // 0.0 → 1.0 looping over 3s

  const _FlickerRingsPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    for (int i = 0; i < 2; i++) {
      final phase = (progress + i * 0.5) % 1.0;
      final r = 20 + phase * 60;
      final alpha = (1.0 - phase) * 0.30;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = AppColors.emberWarm.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_FlickerRingsPainter old) => old.progress != progress;
}

class _DiscoverButton extends StatefulWidget {
  final VoidCallback onTap;
  const _DiscoverButton({required this.onTap});

  @override
  State<_DiscoverButton> createState() => _DiscoverButtonState();
}

class _DiscoverButtonState extends State<_DiscoverButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppMotion.fast,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.emberGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.emberGlow(
              intensity: 0.42, blur: 36, offset: const Offset(0, 14)),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 10),
                Text('Find people on Saanjh',
                    style: AppTypography.button(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Diary list ───────────────────────────────────────────────────────────────

class _DiaryList extends StatelessWidget {
  final List<DiaryContact> diaries;
  final Map<String, String> transcriptMatches;
  final bool isSelecting;
  final Set<String> selectedIds;
  final void Function(String id) onEnterSelection;
  final void Function(String id) onToggleSelection;

  const _DiaryList({
    required this.diaries,
    this.transcriptMatches = const {},
    required this.isSelecting,
    required this.selectedIds,
    required this.onEnterSelection,
    required this.onToggleSelection,
  });

  // Number of entries sent by the contact that the user hasn't played yet.
  int _unlistenedCount(String diaryId) =>
      DiaryStore.instance
          .entriesFor(diaryId)
          .where((e) => !e.isMine && e.listenedAt == null)
          .length;

  @override
  Widget build(BuildContext context) {
    final store = DiaryStore.instance;

    // Sort: unlistened entries first (strongest pull-back signal),
    // then pinned, then default order.
    final sorted = [...diaries]..sort((a, b) {
        int priority(DiaryContact d) {
          if (_unlistenedCount(d.id) > 0) return 3;
          if (store.isPinned(d.id)) return 2;
          return 1;
        }
        return priority(b).compareTo(priority(a));
      });

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, MediaQuery.of(context).padding.bottom + 96),
      physics: const BouncingScrollPhysics(),
      itemCount: sorted.length,
      itemBuilder: (_, i) {
        final d = sorted[i];
        final unlistened = _unlistenedCount(d.id);

        return SaanjhStaggerItem(
          key: ValueKey(d.id),
          index: i,
          child: _DiaryCard(
            diary: d,
            isFirst: !isSelecting && i == 0,
            isSelecting: isSelecting,
            isSelected: selectedIds.contains(d.id),
            isPinned: store.isPinned(d.id),
            isMuted: store.isMuted(d.id),
            isFavourite: store.isFavourite(d.id),
            unlistenedCount: unlistened,
            transcriptMatch: transcriptMatches[d.id],
            onTap: isSelecting
                ? () => onToggleSelection(d.id)
                : () {
                    HapticFeedback.selectionClick();
                    context.push(
                      d.isGroup ? AppRoutes.groupThread : AppRoutes.diaryThread,
                      extra: {'diaryId': d.id},
                    );
                  },
            onLongPress: isSelecting ? null : () => onEnterSelection(d.id),
          ),
        );
      },
    );
  }
}

class _DiaryCard extends StatefulWidget {
  final DiaryContact diary;
  final bool isFirst;
  final bool isSelecting;
  final bool isSelected;
  final bool isPinned;
  final bool isMuted;
  final bool isFavourite;
  final int unlistenedCount;
  final String? transcriptMatch; // shown as snippet when search matched a transcript
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _DiaryCard({
    required this.diary,
    required this.isFirst,
    required this.isSelecting,
    required this.isSelected,
    required this.isPinned,
    required this.isMuted,
    required this.isFavourite,
    required this.unlistenedCount,
    this.transcriptMatch,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_DiaryCard> createState() => _DiaryCardState();
}

class _DiaryCardState extends State<_DiaryCard>
    with TickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _enterCtrl;
  // Slow pulse for dormant parent/partner diaries (re-engagement nudge).
  late final AnimationController _reengageCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _reengageCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _reengageCtrl.dispose();
    super.dispose();
  }

  // Relative time label from the most recent entry across all directions.
  static String _lastActivityLabel(List<DiaryEntry> entries) {
    if (entries.isEmpty) return 'No messages yet';
    final latest = entries.reduce(
        (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
    final diff = DateTime.now().difference(latest.createdAt);
    if (diff.inMinutes < 60) return 'just now';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[latest.createdAt.weekday - 1];
    }
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[latest.createdAt.month]} ${latest.createdAt.day}';
  }

  // True when the diary has been quiet for > 5 days and the relation is
  // a close bond that warrants a gentle re-engagement nudge.
  static bool _needsReengagementPulse(
      DiaryContact d, List<DiaryEntry> entries) {
    if (entries.isEmpty) return false;
    final latest = entries.reduce(
        (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
    if (DateTime.now().difference(latest.createdAt).inDays <= 5) return false;
    final rel = d.relation.toLowerCase();
    return rel.contains('parent') ||
        rel.contains('mother') || rel.contains('maa') ||
        rel.contains('father') || rel.contains('papa') ||
        rel.contains('baba') || rel.contains('partner') ||
        rel.contains('wife') || rel.contains('husband') ||
        rel.contains('spouse');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diary;
    return AnimatedBuilder(
      animation: _enterCtrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_enterCtrl.value);
        return Opacity(
          opacity: t,
          child:
              Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
        );
      },
      child: ListenableBuilder(
        listenable: Listenable.merge(
            [FlickerStore.instance, DiaryStore.instance, _reengageCtrl]),
        builder: (_, w) {
          final ps = FlickerStore.instance;
          final ds = DiaryStore.instance;
          final received = ps.receivedToday(d.id);
          final mePulsed = ps.hasMeFlickeredToday(d.id);
          final mutual = received != null && mePulsed;
          final receivedNotSent = received != null && !mePulsed;
          final streakDays = ds.streakDays(d.id);
          final atRisk = ds.streakAtRisk(d.id);
          final hasSentToday = ds.hasSentToday(d.id);
          final justBroke = ds.hasBrokeStreak(d.id);

          // All entries — drives last-activity label and re-engagement pulse.
          final entries = ds.entriesFor(d.id);

          // Start/stop re-engagement border pulse lazily so it responds even
          // after the 500 ms DiaryStore initial-load delay.
          final needsPulse = _needsReengagementPulse(d, entries);
          if (needsPulse && !_reengageCtrl.isAnimating) {
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _reengageCtrl.repeat(reverse: true));
          } else if (!needsPulse && _reengageCtrl.isAnimating) {
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _reengageCtrl.stop());
          }
          // Listener's receipt — most recent sent entry listened to?
          DiaryEntry? latestSent;
          for (final e in entries) {
            if (e.isMine) {
              if (latestSent == null ||
                  e.createdAt.isAfter(latestSent.createdAt)) {
                latestSent = e;
              }
            }
          }
          final hasListenedReceipt = latestSent?.listenedAt != null;
          final lastActivityLabel = _lastActivityLabel(entries);


          return GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? AppColors.ember.withValues(alpha: 0.10)
                    : receivedNotSent && !widget.isSelecting
                        ? AppColors.ember.withValues(alpha: 0.05)
                        : _pressed
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.isSelected
                      ? AppColors.emberWarm.withValues(alpha: 0.40)
                      : receivedNotSent && !widget.isSelecting
                          ? AppColors.emberWarm.withValues(alpha: 0.22)
                          : widget.isFirst
                              ? AppColors.emberWarm.withValues(alpha: 0.25)
                              : needsPulse
                                  ? Color.lerp(
                                      AppColors.borderSoft,
                                      AppColors.ember.withValues(alpha: 0.12),
                                      _reengageCtrl.value,
                                    )!
                                  : Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // ── Avatar with streak/pulse ring + unlistened badge ──
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SaanjhAvatar(
                        contact: d,
                        size: 52,
                        showRing: !widget.isSelecting,
                        showGroupBadge: true,
                        showSelectionOverlay: widget.isSelecting,
                        isSelected: widget.isSelected,
                      ),
                      if (!widget.isSelecting)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: AnimatedScale(
                            scale: widget.unlistenedCount > 0 ? 1.0 : 0.0,
                            duration: AppMotion.fast,
                            curve: AppMotion.easeSpring,
                            child: SaanjhCountBadge(
                                count: widget.unlistenedCount),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 12),

                  // ── Text content ──────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: name + metadata icons + last-activity time
                        Row(
                          children: [
                            if (widget.isPinned) ...[
                              Icon(Icons.push_pin_rounded,
                                  size: 11,
                                  color: AppColors.emberBright
                                      .withValues(alpha: 0.70)),
                              const SizedBox(width: 3),
                            ],
                            Expanded(
                              child: Text(
                                d.name,
                                style: AppTypography.body(
                                  size: 15,
                                  weight: receivedNotSent || widget.isFirst
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (!widget.isSelecting && widget.isMuted) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.notifications_off_rounded,
                                  size: 12,
                                  color: AppColors.textFaint
                                      .withValues(alpha: 0.55)),
                            ],
                            if (!widget.isSelecting && widget.isFavourite) ...[
                              const SizedBox(width: 3),
                              Icon(Icons.star_rounded,
                                  size: 12,
                                  color: AppColors.emberBright
                                      .withValues(alpha: 0.70)),
                            ],
                            const SizedBox(width: 6),
                            Text(
                              lastActivityLabel,
                              style: AppTypography.caption(
                                color: receivedNotSent || widget.isFirst
                                    ? AppColors.emberBright
                                    : AppColors.textFaint,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        // Bottom row: snippet + right badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                // Transcript match takes priority when search matched via transcript
                                widget.transcriptMatch ??
                                    (d.lastSnippet.isNotEmpty
                                        ? d.lastSnippet
                                        : d.relation),
                                style: AppTypography.label(
                                  size: 12.5,
                                  color: widget.transcriptMatch != null
                                      ? AppColors.emberWarm
                                          .withValues(alpha: 0.75)
                                      : d.lastSnippet.isNotEmpty
                                          ? AppColors.textMuted
                                          : AppColors.textFaint,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (!widget.isSelecting) ...[
                              const SizedBox(width: 8),
                              if (mutual)
                                const SaanjhMutualBadge()
                              else if (receivedNotSent)
                                SaanjhFlickeredYouBadge(
                                    timeLabel: received.timeLabel)
                              else if (justBroke)
                                const _StartAgainBadge()
                              else if (streakDays > 0)
                                SaanjhStreakBadge(
                                  days: streakDays,
                                  atRisk: atRisk,
                                  sentToday: hasSentToday,
                                )
                              else if (hasListenedReceipt)
                                const _ListenedBadge(),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Diary card badges ────────────────────────────────────────────────────────

class _StartAgainBadge extends StatelessWidget {
  const _StartAgainBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.10), width: 1),
      ),
      child: Text(
        '◦ Start again',
        style: AppTypography.label(
            size: 11,
            weight: FontWeight.w500,
            color: AppColors.textFaint),
      ),
    );
  }
}

class _ListenedBadge extends StatelessWidget {
  const _ListenedBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.headphones_rounded,
            size: 11, color: Color(0xFF7CD992)),
        const SizedBox(width: 4),
        Text(
          'listened',
          style: AppTypography.label(
            size: 11,
            weight: FontWeight.w600,
            color: const Color(0xFF7CD992),
          ),
        ),
      ],
    );
  }
}

// ─── Top header ───────────────────────────────────────────────────────────────

class _TopHeader extends StatelessWidget {
  final VoidCallback onDiscover;
  final VoidCallback onProfile;
  final VoidCallback onSelectAll;

  const _TopHeader({
    required this.onDiscover,
    required this.onProfile,
    required this.onSelectAll,
  });

  void _showQuickMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final maxH = MediaQuery.of(sheetCtx).size.height * 0.82;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.modalSurface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
              border:
                  Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                const SizedBox(height: 14),
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),

                // Scrollable menu items
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _QuickMenuItem(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Select diaries',
                          sub: 'Long-press any diary, or select all',
                          onTap: () {
                            Navigator.pop(context);
                            onSelectAll();
                          },
                        ),
                        _QuickMenuDivider(),
                        _QuickMenuItem(
                          icon: Icons.archive_outlined,
                          label: 'Archived chats',
                          sub: 'Diaries you\'ve archived',
                          onTap: () => Navigator.pop(context),
                        ),
                        _QuickMenuDivider(),
                        _QuickMenuItem(
                          icon: Icons.person_outline_rounded,
                          label: 'Profile',
                          sub: 'Edit name, photo, language',
                          onTap: () {
                            Navigator.pop(context);
                            context.push(AppRoutes.profile);
                          },
                        ),
                        _QuickMenuDivider(),
                        _QuickMenuItem(
                          icon: Icons.notifications_outlined,
                          label: 'Notifications',
                          sub: 'Manage alerts & reminders',
                          onTap: () => Navigator.pop(context),
                        ),
                        _QuickMenuDivider(),
                        _QuickMenuItem(
                          icon: Icons.card_giftcard_rounded,
                          label: 'Invite to Saanjh',
                          sub: 'Free · share with someone you love',
                          onTap: () {
                            Navigator.pop(context);
                            context.push(AppRoutes.inviteRecipient);
                          },
                          accent: true,
                        ),
                        _QuickMenuDivider(),
                        _QuickMenuItem(
                          icon: Icons.favorite_rounded,
                          label: 'Send a Flicker',
                          sub: 'One touch · once a day · no message',
                          accent: true,
                          onTap: () {
                            Navigator.pop(context);
                            context.push(AppRoutes.flicker);
                          },
                        ),
                        _QuickMenuDivider(),
                        _QuickMenuItem(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          sub: 'Privacy, language, account',
                          onTap: () {
                            Navigator.pop(context);
                            context.push(AppRoutes.settings);
                          },
                        ),
                        _QuickMenuDivider(),
                        _QuickMenuItem(
                          icon: Icons.logout_rounded,
                          label: 'Sign out',
                          onTap: () async {
                            Navigator.pop(context);
                            final confirmed = await SaanjhDialog.showDestructive(
                              context,
                              title: 'Sign out?',
                              body: 'You can sign back in anytime with your phone number.',
                              confirmLabel: 'Sign out',
                            );
                            if (!confirmed || !context.mounted) return;
                            HapticFeedback.mediumImpact();
                            context.go(AppRoutes.splash);
                          },
                          color: AppColors.destructive,
                        ),
                      ],
                    ),
                  ),
                ),

                // Device-aware bottom padding
                SizedBox(
                    height:
                        MediaQuery.of(sheetCtx).padding.bottom + 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
        child: Row(
          children: [
            Expanded(
              child: Text('Saanjh',
                  style: AppTypography.title(
                      size: 24, weight: FontWeight.w600)),
            ),
            _HeaderBtn(
                icon: Icons.person_search_rounded, onTap: onDiscover),
            const SizedBox(width: 8),
            _HeaderBtn(
              icon: Icons.more_vert_rounded,
              onTap: () => _showQuickMenu(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final bool accent;
  final Color? color;

  const _QuickMenuItem({
    required this.icon,
    required this.label,
    this.sub,
    required this.onTap,
    this.accent = false,
    this.color,
  });

  @override
  State<_QuickMenuItem> createState() => _QuickMenuItemState();
}

class _QuickMenuItemState extends State<_QuickMenuItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ??
        (widget.accent ? AppColors.emberWarm : AppColors.text);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        color: _pressed
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.accent
                    ? AppColors.ember.withValues(alpha: 0.12)
                    : widget.color != null
                        ? widget.color!.withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.06),
              ),
              child: Icon(widget.icon, size: 17, color: c),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                      style: AppTypography.body(size: 15, color: c,
                          weight: FontWeight.w500)),
                  if (widget.sub != null)
                    Text(widget.sub!,
                        style: AppTypography.label(
                            size: 12, color: AppColors.textFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickMenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
      height: 1,
      indent: 70,
      color: Colors.white.withValues(alpha: 0.05));
}

class _HeaderBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderBtn({required this.icon, required this.onTap});

  @override
  State<_HeaderBtn> createState() => _HeaderBtnState();
}

class _HeaderBtnState extends State<_HeaderBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.10), width: 1),
        ),
        child: Icon(widget.icon, size: 18, color: AppColors.emberBright),
      ),
    );
  }
}

// ─── Record FAB ───────────────────────────────────────────────────────────────

class _RecordFab extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _RecordFab({required this.onTap, required this.onLongPress});

  @override
  State<_RecordFab> createState() => _RecordFabState();
}

class _RecordFabState extends State<_RecordFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onLongPress();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: AppMotion.fast,
        curve: AppMotion.easeOut,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.emberGradient,
            boxShadow: AppShadows.emberGlow(
              intensity: 0.5, blur: 30, offset: const Offset(0, 12)),
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

// ─── Record picker sheet ──────────────────────────────────────────────────────

class _RecordPickerSheet extends StatelessWidget {
  final VoidCallback onVoice;
  final VoidCallback onVideo;
  final VoidCallback onBroadcast;

  const _RecordPickerSheet({
    required this.onVoice,
    required this.onVideo,
    required this.onBroadcast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0C0500),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border:
            Border(top: BorderSide(color: Color(0x18FFFFFF), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // Intimate header
              Text.rich(
                TextSpan(
                  style: AppTypography.display(size: 30)
                      .copyWith(height: 1.1),
                  children: [
                    const TextSpan(text: 'A moment\n'),
                    TextSpan(
                      text: 'for them.',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppColors.emberBright,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Up to 20 seconds · stored forever.',
                style: AppTypography.body(size: 14, color: AppColors.textMuted),
              ),

              const SizedBox(height: 24),

              // Two atmospheric record cards
              Row(
                children: [
                  Expanded(
                    child: _RecordCard(
                      isVoice: true,
                      onTap: onVoice,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RecordCard(
                      isVoice: false,
                      onTap: onVideo,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Broadcast — secondary quiet row
              _BroadcastRow(onTap: onBroadcast),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Atmospheric record card ──────────────────────────────────────────────────

class _RecordCard extends StatefulWidget {
  final bool isVoice;
  final VoidCallback onTap;
  const _RecordCard({required this.isVoice, required this.onTap});

  @override
  State<_RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<_RecordCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVoice = widget.isVoice;
    final accent = isVoice ? AppColors.emberWarm : AppColors.violet;
    final darkBg =
        isVoice ? const Color(0xFF2A0E00) : const Color(0xFF1A0535);
    final deepBg =
        isVoice ? const Color(0xFF100500) : const Color(0xFF0A0220);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: AppMotion.fast,
        child: AnimatedBuilder(
          animation: _breathe,
          builder: (_, child) {
            final b = _breathe.value;
            return Container(
              height: 172,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [darkBg, deepBg],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: accent.withValues(
                      alpha: _pressed ? 0.65 : 0.20 + b * 0.18),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(
                        alpha: _pressed ? 0.30 : 0.12 + b * 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Corner ambient glow
                  Positioned(
                    top: -18,
                    left: isVoice ? -18 : null,
                    right: isVoice ? null : -18,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(
                            alpha: 0.07 + b * 0.07),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Breathing icon circle
                        Transform.scale(
                          scale: 1.0 + 0.055 * b,
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: 0.15),
                              border: Border.all(
                                color: accent.withValues(
                                    alpha: 0.30 + b * 0.25),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(
                                      alpha: 0.20 + b * 0.20),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: Icon(
                              isVoice
                                  ? Icons.mic_rounded
                                  : Icons.videocam_rounded,
                              size: 26,
                              color: accent,
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Title
                        Text(
                          isVoice ? 'Voice' : 'Video',
                          style: AppTypography.title(size: 22).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Emotional sub copy
                        Text(
                          isVoice
                              ? 'Speak from\nthe heart'
                              : 'Let them\nsee you',
                          style: AppTypography.label(size: 13).copyWith(
                            color: Colors.white.withValues(alpha: 0.40),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Broadcast secondary row ──────────────────────────────────────────────────

class _BroadcastRow extends StatefulWidget {
  final VoidCallback onTap;
  const _BroadcastRow({required this.onTap});

  @override
  State<_BroadcastRow> createState() => _BroadcastRowState();
}

class _BroadcastRowState extends State<_BroadcastRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(
                alpha: _pressed ? 0.10 : 0.06),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.successGreen.withValues(alpha: 0.10),
              ),
              child: const Icon(Icons.people_rounded,
                  size: 18, color: Color(0xFF7CD992)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Broadcast',
                      style: AppTypography.body(
                          size: 15, weight: FontWeight.w500)),
                  Text(
                    'Same moment · multiple connections',
                    style: AppTypography.label(
                        size: 12, color: AppColors.textFaint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

// ─── Broadcast sheet ──────────────────────────────────────────────────────────

class _BroadcastSheet extends StatefulWidget {
  final List<DiaryContact> diaries;
  final void Function(List<String> ids, List<String> names, bool isVideo)
      onRecord;

  const _BroadcastSheet(
      {required this.diaries, required this.onRecord});

  @override
  State<_BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<_BroadcastSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.diaries.map((d) => d.id).toSet();
  }

  bool get _allSelected => _selected.length == widget.diaries.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected = widget.diaries.map((d) => d.id).toSet();
      }
    });
  }

  void _toggle(String id) {
    setState(() {
      _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    });
  }

  void _record(bool isVideo) {
    if (_selected.isEmpty) return;
    HapticFeedback.mediumImpact();
    final sel =
        widget.diaries.where((d) => _selected.contains(d.id)).toList();
    widget.onRecord(
      sel.map((d) => d.id).toList(),
      sel.map((d) => d.name).toList(),
      isVideo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canRecord = _selected.isNotEmpty;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Send to', style: AppTypography.title(size: 20)),
                const Spacer(),
                _AllToggleChip(
                  selected: _allSelected,
                  count: widget.diaries.length,
                  onTap: _toggleAll,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Contact list
          Flexible(
            child: widget.diaries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(36),
                    child: Text(
                      'Add connections first —\nthen broadcast to them.',
                      style: AppTypography.body(size: 16, color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    shrinkWrap: true,
                    itemCount: widget.diaries.length,
                    itemBuilder: (_, i) {
                      final d = widget.diaries[i];
                      return _ContactSelectRow(
                        contact: d,
                        selected: _selected.contains(d.id),
                        onTap: () => _toggle(d.id),
                      );
                    },
                  ),
          ),

          // Voice / Video buttons
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 14, 20,
                MediaQuery.of(context).padding.bottom + 16),
            child: Row(
              children: [
                Expanded(
                  child: _BroadcastRecordBtn(
                    icon: Icons.mic_rounded,
                    label: 'Voice',
                    color: AppColors.emberWarm,
                    enabled: canRecord,
                    onTap: () => _record(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BroadcastRecordBtn(
                    icon: Icons.videocam_rounded,
                    label: 'Video',
                    color: AppColors.violet,
                    enabled: canRecord,
                    onTap: () => _record(true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AllToggleChip extends StatelessWidget {
  final bool selected;
  final int count;
  final VoidCallback onTap;
  const _AllToggleChip(
      {required this.selected, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ember.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.emberWarm.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.09),
            width: 1,
          ),
        ),
        child: Text(
          selected ? 'All $count selected' : 'Select all',
          style: AppTypography.label(
            size: 12,
            weight: FontWeight.w600,
            color:
                selected ? AppColors.emberBright : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ContactSelectRow extends StatelessWidget {
  final DiaryContact contact;
  final bool selected;
  final VoidCallback onTap;
  const _ContactSelectRow(
      {required this.contact,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    contact.avatarColor,
                    contact.avatarColor.withValues(alpha: 0.65),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(
                  contact.initial,
                  style: AppTypography.title(size: 16).copyWith(
                      color: Colors.white, fontStyle: FontStyle.italic),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name,
                      style: AppTypography.body(
                          size: 15, weight: FontWeight.w600)),
                  Text(contact.relation,
                      style: AppTypography.label(
                          size: 12, color: AppColors.textFaint)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: AppMotion.fast,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? AppColors.ember
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? AppColors.emberWarm
                      : Colors.white.withValues(alpha: 0.20),
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BroadcastRecordBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _BroadcastRecordBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_BroadcastRecordBtn> createState() => _BroadcastRecordBtnState();
}

class _BroadcastRecordBtnState extends State<_BroadcastRecordBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.enabled
          ? (_) => setState(() => _pressed = false)
          : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _pressed = false)
          : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: widget.enabled
              ? widget.color.withValues(alpha: _pressed ? 0.22 : 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.enabled
                ? widget.color
                    .withValues(alpha: _pressed ? 0.50 : 0.28)
                : Colors.white.withValues(alpha: 0.07),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon,
                size: 22,
                color:
                    widget.enabled ? widget.color : AppColors.textFaint),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: AppTypography.label(
                size: 13,
                weight: FontWeight.w600,
                color: widget.enabled
                    ? widget.color
                    : AppColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Keep-alive wrapper ───────────────────────────────────────────────────────
// PageView discards off-screen pages by default. This wrapper opts each tab
// into the AutomaticKeepAlive protocol so scroll position and state survive
// when the user swipes away and back.

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ─── Bottom nav ───────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // (label, inactiveIcon, activeIcon, isPulseTab)
    const items = [
      ('Diaries',   Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,     false),
      ('Flicker',   Icons.favorite_border_rounded,     Icons.favorite_rounded,         true),
      ('Memories',  Icons.auto_awesome_outlined,       Icons.auto_awesome_rounded,     false),
      ('Me',        Icons.person_outline_rounded,      Icons.person_rounded,           false),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06), width: 1),
        ),
        color: AppColors.ink.withValues(alpha: 0.97),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 4, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final (label, icon, activeIcon, isPulse) = items[i];
          final active = i == index;
          final color = active ? AppColors.emberWarm : AppColors.textFaint;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: Icon(
                      active ? activeIcon : icon,
                      key: ValueKey(active),
                      size: isPulse ? 24 : 22,
                      color: color,
                    ),
                  ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: AppTypography.label(
                      size: 10.5,
                      color: color,
                      weight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Diary list skeleton ──────────────────────────────────────────────────────

class _DiaryListSkeleton extends StatelessWidget {
  const _DiaryListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, MediaQuery.of(context).padding.bottom + 96),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SaanjhShimmer(
          isLoading: true,
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.inkRaised,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.ink)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                          height: 14,
                          width: 120,
                          color: AppColors.ink,
                          margin: const EdgeInsets.only(bottom: 8)),
                      Container(height: 11, color: AppColors.ink),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Flicker strip skeleton ─────────────────────────────────────────────────────

class _FlickerStripSkeleton extends StatelessWidget {
  const _FlickerStripSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(
        children: List.generate(
          4,
          (i) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SaanjhShimmer(
              isLoading: true,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.inkRaised),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Occasion banner ──────────────────────────────────────────────────────────
// Shows when a festival is within 2 days, above the OnThisDay banner.

class _OccasionBanner extends StatefulWidget {
  const _OccasionBanner();

  @override
  State<_OccasionBanner> createState() => _OccasionBannerState();
}

class _OccasionBannerState extends State<_OccasionBanner> {
  bool _dismissed = false;

  static const _kDismissPrefix = 'occasion_dismissed_';

  Occasion? get _occasion => OccasionService.instance.upcomingOccasion();

  String get _dismissKey {
    final o = _occasion;
    if (o == null) return '';
    return '$_kDismissPrefix${o.name}_${DateTime.now().year}';
  }

  // Highest-streak diary name — used in the prompt copy.
  String get _contactName {
    final diaries = DiaryStore.instance.diaries;
    if (diaries.isEmpty) return 'them';
    final best = diaries.reduce((a, b) =>
        DiaryStore.instance.streakDays(a.id) >=
                DiaryStore.instance.streakDays(b.id)
            ? a
            : b);
    return best.displayName.split(' ').first;
  }

  @override
  void initState() {
    super.initState();
    _checkDismissed();
  }

  Future<void> _checkDismissed() async {
    final key = _dismissKey;
    if (key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (mounted && (prefs.getBool(key) == true)) {
      setState(() => _dismissed = true);
    }
  }

  Future<void> _dismiss() async {
    final key = _dismissKey;
    if (key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    if (mounted) setState(() => _dismissed = true);
  }

  void _record(BuildContext context, Occasion occasion) {
    context.push(AppRoutes.voiceRecord, extra: {
      'isVideo': false,
      'occasionTag': occasion.tag,
    });
  }

  @override
  Widget build(BuildContext context) {
    final occasion = _occasion;
    if (occasion == null || _dismissed) return const SizedBox.shrink();

    final prompt =
        OccasionService.instance.occasionPrompt(occasion, _contactName);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Container(
          decoration: BoxDecoration(
            color: occasion.tintColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.emberWarm.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Emoji
                Text(occasion.emoji,
                    style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),

                // Prompt copy + button
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prompt,
                        style: AppTypography.serifItalic(
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => _record(context, occasion),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: AppColors.emberGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Record a greeting →',
                            style: AppTypography.label(
                              size: 12,
                              color: Colors.white,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Dismiss
                GestureDetector(
                  onTap: _dismiss,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: AppColors.textFaint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



