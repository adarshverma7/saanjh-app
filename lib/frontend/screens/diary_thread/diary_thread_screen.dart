import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../backend/entries_api.dart';
import '../../state/diary_store.dart';
import '../../state/flicker_store.dart';
import '../../state/send_queue_store.dart';
import '../../state/user_store.dart';
import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../services/audio_analysis_service.dart';
import '../../services/share_card_service.dart';
import '../../widgets/milestone_share_card.dart';
import '../../widgets/saanjh_dialog.dart';
import '../../widgets/voice_share_card.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/saanjh_shimmer.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

enum _EntryType { voice, video }

class _Entry {
  final String id;
  final bool isMine;
  final _EntryType type;
  final String duration;
  final int durationSeconds;
  final String? transcript;
  final String? prompt;
  final String? occasionTag; // e.g. "🪔 Diwali"
  final String time;
  final bool listened;
  final String path;
  final bool isExpired;
  final bool isPending;
  final bool isFailed;

  const _Entry({
    required this.id,
    required this.isMine,
    required this.type,
    required this.duration,
    required this.durationSeconds,
    required this.transcript,
    // ignore: unused_element_parameter
    this.prompt,
    // ignore: unused_element_parameter
    this.occasionTag,
    required this.time,
    required this.listened,
    // ignore: unused_element_parameter
    this.path = '',
    this.isExpired = false,
    this.isPending = false,
    this.isFailed = false,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class DiaryThreadScreen extends StatefulWidget {
  final String diaryId;
  const DiaryThreadScreen({super.key, required this.diaryId});

  @override
  State<DiaryThreadScreen> createState() => _DiaryThreadScreenState();
}

class _DiaryThreadScreenState extends State<DiaryThreadScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Resolved contact — looked up once on init from the diary store.
  late final DiaryContact? _contact;

  // Entries derived from DiaryStore — rebuilt whenever the store notifies.
  List<_Entry> _entries = const [];

  // Backend loading
  bool _isLoadingEntries = true;

  // Playback
  int? _playingIdx;
  AnimationController? _playCtrl;
  AudioPlayer? _player;
  double _playbackSpeed = 1.0;
  bool _showEndCard = false;
  int? _endCardEntryIdx;

  // Scroll position for historical colour shift
  final _scrollCtrl = ScrollController();
  double _scrollFraction = 0;

  // In-thread notification banner (e.g. "You're back 💛")
  final _bannerKey = GlobalKey<NotificationBannerState>();
  // Off-screen streak share card key
  final _streakCardKey = GlobalKey();

  // Polling timer — fetches new entries from the backend every 15 seconds.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    final matches = DiaryStore.instance.diaries
        .where((d) => d.id == widget.diaryId);
    _contact = matches.isEmpty ? null : matches.first;
    _entries = _buildEntries();
    // Skip the loading spinner when the store already has cached entries.
    _isLoadingEntries = _entries.isEmpty;
    DiaryStore.instance.addListener(_onDiaryStoreChange);
    WidgetsBinding.instance.addObserver(this);
    _loadEntriesFromBackend();
    _startPollTimer();
  }

  // ── Entry mapping ────────────────────────────────────────────────────────

  List<_Entry> _buildEntries() {
    final storeEntries = DiaryStore.instance.entriesFor(widget.diaryId);
    // Only top-level entries — reactions are nested inside DiaryEntry.reactions.
    // Newest first — user lands on the latest message, scrolls down into history.
    final topLevel = storeEntries
        .where((e) => e.parentEntryId == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return topLevel.map((e) {
      return _Entry(
        id: e.id,
        isMine: e.isMine,
        type: e.type == 'video' ? _EntryType.video : _EntryType.voice,
        // durationSeconds defaults to 20 (max recording length) until real
        // audio playback is wired in Prompt 22.
        duration: _formatDuration(e.durationSeconds > 0 ? e.durationSeconds : 20),
        durationSeconds: e.durationSeconds > 0 ? e.durationSeconds : 20,
        transcript: e.transcript,
        prompt: e.prompt,
        occasionTag: e.occasionTag,
        time: _formatTime(e.createdAt),
        listened: e.listenedAt != null,
        path: e.path,
        isExpired: e.isExpired,
        isPending: e.isPending,
        isFailed: e.isFailed,
      );
    }).toList();
  }

  String _formatDuration(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'am' : 'pm';
    return '${months[dt.month]} ${dt.day} · $hour:$minute $ampm';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    DiaryStore.instance.removeListener(_onDiaryStoreChange);
    _playCtrl?.dispose();
    _player?.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollNewEntries();
      _startPollTimer();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _startPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _pollNewEntries();
    });
  }

  // Fetches only new entries from the backend and adds them to the store.
  // Skips the stale-entry cleanup done on initial load so active uploads
  // are not removed from the thread while they're in progress.
  Future<void> _pollNewEntries() async {
    try {
      final result = await EntriesApi.instance.listEntries(widget.diaryId);
      final items = (result['entries'] as List?) ?? [];
      final myUserId = UserStore.instance.userId;
      final existingIds = DiaryStore.instance
          .entriesFor(widget.diaryId)
          .map((e) => e.id)
          .toSet();

      final toAdd = <DiaryEntry>[];
      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        final id = item['id'] as String;
        if (existingIds.contains(id)) continue;

        final dateStr = (item['recorded_at'] ?? item['created_at']) as String?;
        toAdd.add(DiaryEntry(
          id: id,
          diaryId: widget.diaryId,
          isMine: (item['author_id'] as String?) == myUserId,
          type: item['entry_type'] as String? ?? 'voice',
          path: '',
          transcript: item['transcription'] as String?,
          createdAt:
              dateStr != null ? DateTime.parse(dateStr) : DateTime.now(),
          durationSeconds: item['duration_seconds'] as int? ?? 0,
          isExpired: item['is_expired'] as bool? ?? false,
          listenedAt: (item['play_count'] as int? ?? 0) > 0
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : null,
        ));
      }
      if (toAdd.isNotEmpty && mounted) {
        DiaryStore.instance.bulkAddEntries(toAdd);
      }
    } catch (_) {}
  }

  void _onDiaryStoreChange() {
    setState(() => _entries = _buildEntries());
    // Fire "You're back" notification when the first send after a break lands.
    if (DiaryStore.instance.justResumed(widget.diaryId)) {
      final name = _contact?.displayName ?? 'them';
      _bannerKey.currentState?.show(
        "You're back 💛 Day 1 with $name",
        widget.diaryId,
        SaanjhNotificationType.milestone,
      );
    }
    // Check for a freshly reached streak milestone.
    _maybeShowMilestone();
  }

  // Shown once per diary × milestone value — never twice for the same
  // combination (guarded by SharedPreferences across restarts).
  Future<void> _maybeShowMilestone() async {
    final milestone = DiaryStore.instance.milestoneReached(widget.diaryId);
    if (milestone == null) return;

    final guardKey =
        'streak_milestone_shown_${widget.diaryId}_$milestone';
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(guardKey) == true) return;
    await prefs.setBool(guardKey, true);
    if (!mounted) return;

    // Small delay so the voice-send animation settles before pushing.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    context.push(AppRoutes.streakMilestone, extra: {
      'diaryId': widget.diaryId,
      'contactName': _contact?.displayName ?? 'them',
      'milestone': milestone,
    });
  }

  Future<void> _loadEntriesFromBackend() async {
    // Remove stale pending/failed local entries not actively being retried.
    // This prevents duplicates when the screen is recreated and backend entries
    // are re-fetched alongside leftover local IDs from a previous session.
    final queuedIds = SendQueueStore.instance.uploads
        .map((u) => u.pendingLocalId)
        .toSet();
    final staleIds = DiaryStore.instance
        .entriesFor(widget.diaryId)
        .where((e) => (e.isPending || e.isFailed) && !queuedIds.contains(e.id))
        .map((e) => e.id)
        .toList();
    for (final id in staleIds) {
      DiaryStore.instance.removeEntry(id);
    }

    try {
      final result = await EntriesApi.instance.listEntries(widget.diaryId);
      final items = (result['entries'] as List?) ?? [];
      final myUserId = UserStore.instance.userId;
      final existingIds = DiaryStore.instance
          .entriesFor(widget.diaryId)
          .map((e) => e.id)
          .toSet();

      final toAdd = <DiaryEntry>[];
      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        final id = item['id'] as String;
        if (existingIds.contains(id)) continue;

        final dateStr = (item['recorded_at'] ?? item['created_at']) as String?;
        toAdd.add(DiaryEntry(
          id: id,
          diaryId: widget.diaryId,
          isMine: (item['author_id'] as String?) == myUserId,
          type: item['entry_type'] as String? ?? 'voice',
          path: '', // URL fetched lazily on play
          transcript: item['transcription'] as String?,
          createdAt: dateStr != null ? DateTime.parse(dateStr) : DateTime.now(),
          durationSeconds: item['duration_seconds'] as int? ?? 0,
          isExpired: item['is_expired'] as bool? ?? false,
          listenedAt: (item['play_count'] as int? ?? 0) > 0
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : null,
        ));
      }
      DiaryStore.instance.bulkAddEntries(toAdd);
    } catch (_) {
      // Network failure — show whatever is already in the store.
    } finally {
      if (mounted) setState(() => _isLoadingEntries = false);
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    final fraction = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
    if ((fraction - _scrollFraction).abs() > 0.02) {
      setState(() => _scrollFraction = fraction);
    }
  }

  // ── Playback ────────────────────────────────────────────────────────────

  Future<void> _togglePlay(int idx) async {
    // Pending/failed entries are not playable.
    if (idx < _entries.length &&
        (_entries[idx].isPending || _entries[idx].isFailed)) {
      return;
    }
    HapticFeedback.selectionClick();

    // Tap the playing entry → pause and reset.
    if (_playingIdx == idx && !(_showEndCard && _endCardEntryIdx == idx)) {
      _playCtrl?.stop();
      await _player?.stop();
      setState(() => _playingIdx = null);
      return;
    }

    // Dismiss the end-card to allow replay.
    if (_showEndCard && _endCardEntryIdx == idx) {
      setState(() { _showEndCard = false; _endCardEntryIdx = null; });
    }

    // Stop & dispose whatever was playing before.
    _playCtrl?.stop();
    _playCtrl?.dispose();
    _playCtrl = null;
    await _player?.stop();
    await _player?.dispose();
    _player = null;

    final entry = _entries[idx];
    if (!entry.isMine) DiaryStore.instance.markListened(entry.id);

    // ── Resolve playback source ──────────────────────────────────────────
    // Local path: use it directly.
    // No path (backend entry): fetch a 1-hour signed URL from the backend.
    String? playSource = entry.path.isNotEmpty ? entry.path : null;
    if (playSource == null) {
      try {
        final data = await EntriesApi.instance.getEntry(widget.diaryId, entry.id);
        playSource = data['media_url'] as String?;
      } catch (_) {}
      if (!mounted) return;
    }

    // ── Real audio playback ──────────────────────────────────────────────
    if (playSource != null) {
      try {
        final player = AudioPlayer();
        _player = player;

        final Duration? duration;
        if (playSource.startsWith('http')) {
          duration = await player.setUrl(playSource);
        } else {
          duration = await player.setFilePath(playSource);
        }
        if (!mounted) { await player.dispose(); _player = null; return; }

        final playDuration = duration ?? Duration(seconds: entry.durationSeconds);

        // AnimationController mirrors audio progress for the waveform clipper.
        _playCtrl = AnimationController(
          vsync: this,
          duration: playDuration,
        )..forward();

        // Audio completion → trigger end-card.
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (mounted) _onPlayComplete(idx);
          }
        });

        await player.setSpeed(_playbackSpeed);
        await player.play();

        setState(() { _playingIdx = idx; _showEndCard = false; });
        return;
      } catch (_) {
        // Fall through to simulated playback on any error.
        await _player?.dispose();
        _player = null;
      }
    }

    // ── Simulated playback (no file path or load error) ──────────────────
    _playCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: entry.durationSeconds),
    )..forward().whenComplete(() {
        if (mounted) _onPlayComplete(idx);
      });
    setState(() { _playingIdx = idx; _showEndCard = false; });
  }

  void _onPlayComplete(int idx) {
    setState(() {
      _showEndCard = true;
      _endCardEntryIdx = idx;
      _playingIdx = null;
    });
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted && _showEndCard && _endCardEntryIdx == idx) {
        setState(() { _showEndCard = false; _endCardEntryIdx = null; });
      }
    });

    // Trigger amplitude analysis after first playback.
    // moodEnergy is set async — tint appears on second play. Intentional.
    if (idx < _entries.length) {
      final entryId = _entries[idx].id;
      final diaryEntries = DiaryStore.instance.entriesFor(widget.diaryId);
      try {
        final real = diaryEntries.firstWhere((e) => e.id == entryId);
        if (real.moodEnergy == null) {
          AudioAnalysisService.analyse(real.path).then((r) {
            if (r != null) {
              DiaryStore.instance.updateEntryMood(real.id, r.energy);
            }
          });
        }
      } catch (_) {}
    }
  }

  // ── Record picker ────────────────────────────────────────────────────────

  void _showRecordPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordSheet(
        recipientName: _contact?.name ?? 'them',
        onVoice: () {
          Navigator.pop(context);
          context.push(AppRoutes.voiceRecord,
              extra: {'isVideo': false, 'targetDiaryId': widget.diaryId});
        },
        onVideo: () {
          Navigator.pop(context);
          context.push(AppRoutes.voiceRecord,
              extra: {'isVideo': true, 'targetDiaryId': widget.diaryId});
        },
      ),
    );
  }

  // ── More menu ────────────────────────────────────────────────────────────

  void _showMoreMenu() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoreMenuSheet(
        onWish: () {
          Navigator.pop(context);
          context.push(AppRoutes.wish, extra: {'name': _contact?.name ?? 'them'});
        },
        onMemoryBook: DiaryStore.instance.streakDays(widget.diaryId) >= 30
            ? () {
                Navigator.pop(context);
                context.push(AppRoutes.memoryBook,
                    extra: {'diaryId': widget.diaryId});
              }
            : null,
        memoryBookStreak: DiaryStore.instance.streakDays(widget.diaryId),
        onMemoryTree: () {
          Navigator.pop(context);
          context.push(AppRoutes.memoryTree);
        },
        onOccasion: () {
          Navigator.pop(context);
          context.push(AppRoutes.occasionPlan);
        },
        onDelete: _confirmDelete,
        onShareStreak: DiaryStore.instance.streakDays(widget.diaryId) > 0
            ? () {
                Navigator.pop(context);
                final streak =
                    DiaryStore.instance.streakDays(widget.diaryId);
                final name = _contact?.displayName ?? 'them';
                ShareCardService.instance
                    .shareStreakCard(_streakCardKey, streak, name);
              }
            : null,
      ),
    );
  }

  void _confirmDelete() async {
    final confirmed = await SaanjhDialog.showDestructive(
      context,
      title: 'Delete diary?',
      body: 'This will remove all voice notes with '
          '${_contact?.name ?? 'this person'}. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    HapticFeedback.mediumImpact();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    // _scrollFraction: 0.0 at top (newest / present), 1.0 at bottom (oldest / past).
    // As fraction increases the background cools and the ember warmth fades —
    // scrolling down through the list feels like travelling back through time.
    final historyBg = Color.lerp(
      AppColors.ink,
      const Color(0xFF080508), // cooler, more desaturated past-tint
      _scrollFraction * 0.4,
    )!;

    return Scaffold(
      backgroundColor: historyBg,
      body: Stack(
        children: [
          // Base gradient — tinted toward the past background as scroll deepens
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(AppColors.inkRaised,
                        const Color(0xFF080508), _scrollFraction * 0.35)!,
                    historyBg,
                    historyBg,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Ember warmth overlay — glows at present (top), fades into the past
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.6),
                    radius: 0.85,
                    colors: [
                      AppColors.ember.withValues(
                          alpha: 0.07 * (1.0 - _scrollFraction)),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content column
          Column(
            children: [
              _ThreadHeader(
                onBack: () => context.pop(),
                onMore: _showMoreMenu,
                contactName: _contact?.name ?? 'Diary',
                contactInitial: _contact?.initial ?? '?',
                contactColor: _contact?.avatarColor ?? AppColors.ember,
                diaryId: widget.diaryId,
              ),
                Expanded(
                  child: _isLoadingEntries
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.ember,
                            strokeWidth: 2,
                          ),
                        )
                      : _entries.isEmpty
                          ? _EmptyThread()
                          : ListView(
                          controller: _scrollCtrl,
                          padding:
                              const EdgeInsets.fromLTRB(14, 12, 14, 120),
                          physics: const BouncingScrollPhysics(),
                          children: [
                            for (int i = 0; i < _entries.length; i++)
                              if (_entries[i].isExpired)
                                _ExpiredBubble(entry: _entries[i])
                              else if (_entries[i].type == _EntryType.voice)
                                _VoiceBubble(
                                  entry: _entries[i],
                                  diaryId: widget.diaryId,
                                  playing: _playingIdx == i,
                                  playCtrl:
                                      _playingIdx == i ? _playCtrl : null,
                                  speed: _playbackSpeed,
                                  onToggleSpeed: () {
                                    final next = _playbackSpeed == 1.0
                                        ? 1.5
                                        : _playbackSpeed == 1.5
                                            ? 2.0
                                            : 1.0;
                                    setState(() => _playbackSpeed = next);
                                    _player?.setSpeed(next);
                                  },
                                  isShowingEndCard:
                                      _showEndCard && _endCardEntryIdx == i,
                                  contactName:
                                      _contact?.displayName ?? '',
                                  contactColor:
                                      _contact?.avatarColor ?? AppColors.ember,
                                  onTap: () => _togglePlay(i),
                                  onShowBanner: (msg) =>
                                      _bannerKey.currentState?.show(
                                        msg,
                                        widget.diaryId,
                                        SaanjhNotificationType.milestone,
                                      ),
                                  onDelete: () {
                                    final removedId = _entries[i].id;
                                    DiaryStore.instance.removeEntry(removedId);
                                    setState(() {
                                      _entries = [
                                        ..._entries,
                                      ]..removeWhere((e) => e.id == removedId);
                                    });
                                  },
                                  onRetry: () =>
                                      SendQueueStore.instance.processQueue(),
                                )
                              else if (_entries[i].type == _EntryType.video)
                                _VideoBubble(
                                  entry: _entries[i],
                                  onRetry: () =>
                                      SendQueueStore.instance.processQueue(),
                                ),
                          ],
                        ),
                ),
              ],
            ),

            // ── Off-screen streak share card ──
            Offstage(
              child: ListenableBuilder(
                listenable: DiaryStore.instance,
                builder: (_, _) => MilestoneShareCard(
                  key: _streakCardKey,
                  streakDays: DiaryStore.instance.streakDays(widget.diaryId),
                  contactName: _contact?.displayName ?? 'them',
                  milestoneLabel: DiaryStore.instance.streakLabel(widget.diaryId),
                ),
              ),
            ),

            // ── In-thread notification banner ──
            Positioned(
              top: 0, left: 0, right: 0,
              child: NotificationBanner(key: _bannerKey),
            ),

            // ── Bottom action bar (Pulse · Compose · Record) ──
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _BottomActionBar(
                diaryId: widget.diaryId,
                personName: _contact?.name ?? 'them',
                onRecord: _showRecordPicker,
                onPulse: () => context.push(
                  AppRoutes.flicker,
                  extra: {'targetDiaryId': widget.diaryId},
                ),
              ),
            ),
          ],
        ),
    );
  }
}

// ─── Thread header ────────────────────────────────────────────────────────────

class _ThreadHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onMore;
  final String contactName;
  final String contactInitial;
  final Color contactColor;
  final String diaryId;

  const _ThreadHeader({
    required this.onBack,
    required this.onMore,
    required this.contactName,
    required this.contactInitial,
    required this.contactColor,
    required this.diaryId,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DiaryStore.instance,
      builder: (_, w) {
        final ds = DiaryStore.instance;
        final streak = ds.streakDays(diaryId);
        final atRisk = ds.streakAtRisk(diaryId);
        final hasSentToday = ds.hasSentToday(diaryId);
        final justBroke = ds.hasBrokeStreak(diaryId);

        return SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10), width: 1),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 14, color: Color(0xAAF5EFE8)),
                  ),
                ),
                const SizedBox(width: 12),

                // Avatar with streak ring — long-press for colour picker
                GestureDetector(
                  onLongPress: () {
                    final contact = DiaryStore.instance.diaries
                        .cast<DiaryContact?>()
                        .firstWhere((d) => d?.id == diaryId,
                            orElse: () => null);
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => _ColourPickerSheet(
                        currentIndex:
                            contact?.avatarColorIndex ?? -1,
                        onSelect: (i) {
                          DiaryStore.instance
                              .updateAvatarColorIndex(diaryId, i);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                  child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        contactColor,
                        contactColor.withValues(alpha: 0.70),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: streak > 0
                        ? Border.all(
                            color: atRisk
                                ? AppColors.destructive.withValues(alpha: 0.70)
                                : hasSentToday
                                    ? AppColors.emberWarm.withValues(alpha: 0.75)
                                    : AppColors.emberWarm.withValues(alpha: 0.35),
                            width: 2,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: streak > 0
                            ? (atRisk
                                ? AppColors.destructive
                                : AppColors.emberWarm)
                                .withValues(alpha: hasSentToday ? 0.40 : 0.20)
                            : contactColor.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      contactInitial,
                      style: AppTypography.title(size: 18).copyWith(
                          color: Colors.white, fontStyle: FontStyle.italic),
                    ),
                  ),
                ),
                ), // close GestureDetector
                const SizedBox(width: 12),

                // Name + streak badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    contactName,
                                    style: AppTypography.body(
                                        size: 16, weight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // ✏ label editor
                                GestureDetector(
                                  onTap: () {
                                    final current = DiaryStore.instance.diaries
                                        .cast<DiaryContact?>()
                                        .firstWhere(
                                            (d) => d?.id == diaryId,
                                            orElse: () => null)
                                        ?.customLabel ?? '';
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: Colors.transparent,
                                      isScrollControlled: true,
                                      builder: (_) => _LabelEditorSheet(
                                        initialValue: current,
                                        onSave: (label) {
                                          DiaryStore.instance
                                              .updateCustomLabel(diaryId, label);
                                          Navigator.pop(context);
                                        },
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 5),
                                    child: Icon(Icons.edit_rounded,
                                        size: 12, color: AppColors.textFaint),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (streak > 0 || justBroke) ...[
                            const SizedBox(width: 8),
                            _StreakChip(
                              days: streak,
                              atRisk: atRisk,
                              sentToday: hasSentToday,
                              justBroke: justBroke && streak == 0,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.lock_rounded,
                              size: 9,
                              color: AppColors.textFaint.withValues(alpha: 0.55)),
                          const SizedBox(width: 5),
                          Builder(builder: (_) {
                            final weather = ds.weatherState(diaryId);
                            final String label;
                            final Color color;
                            if (weather == DiaryWeather.quiet) {
                              label = '🌧 Quiet lately · say something?';
                              color = AppColors.textFaint;
                            } else if (weather == DiaryWeather.clearingUp) {
                              label = '🌤 Back together 💛';
                              color = AppColors.ember;
                            } else {
                              label = streak > 0
                                  ? DiaryStore.instance.streakLabel(diaryId)
                                  : 'Private diary';
                              color = streak > 0 && hasSentToday
                                  ? AppColors.emberBright.withValues(alpha: 0.65)
                                  : AppColors.textFaint;
                            }
                            return Text(label,
                                style: AppTypography.label(
                                    size: 11.5, color: color));
                          }),
                        ],
                      ),
                    ],
                  ),
                ),

                GestureDetector(
                  onTap: () => context.push(
                    AppRoutes.memoryTree,
                    extra: {'diaryId': diaryId},
                  ),
                  child: _IconBtn(
                      icon: Icons.park_outlined, color: AppColors.emberBright),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onMore,
                  child: _IconBtn(
                      icon: Icons.more_vert_rounded, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Snapchat-style streak chip shown in the thread header.
class _StreakChip extends StatelessWidget {
  final int days;
  final bool atRisk;
  final bool sentToday;
  final bool justBroke;
  const _StreakChip({
    required this.days,
    required this.atRisk,
    required this.sentToday,
    this.justBroke = false,
  });

  @override
  Widget build(BuildContext context) {
    // Streak just broke — grey "◦ Start again" pill
    if (justBroke) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.10), width: 1),
        ),
        child: Text(
          '◦ Start again',
          style: AppTypography.label(
            size: 11,
            weight: FontWeight.w500,
            color: AppColors.textFaint,
          ),
        ),
      );
    }

    final Color color;
    if (atRisk) {
      color = AppColors.destructive;
    } else if (sentToday) {
      color = AppColors.emberWarm;
    } else {
      color = AppColors.emberWarm.withValues(alpha: 0.50);
    }
    final bg = atRisk
        ? AppColors.destructive.withValues(alpha: 0.12)
        : sentToday
            ? AppColors.ember.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.05);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            atRisk ? '⏳' : '🔥',
            style: const TextStyle(fontSize: 11, height: 1.2),
          ),
          const SizedBox(width: 3),
          Text(
            '$days',
            style: AppTypography.label(
              size: 11,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBtn({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08), width: 1),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

// ─── Empty thread state ───────────────────────────────────────────────────────

class _EmptyThread extends StatefulWidget {
  @override
  State<_EmptyThread> createState() => _EmptyThreadState();
}

class _EmptyThreadState extends State<_EmptyThread> {
  static const _allPrompts = [
    'Tell them what made you smile today 🌤',
    'Share something that happened this week 💬',
    "Say something you've been meaning to say 💛",
    'What are you having for dinner? 🍛',
    'What would you tell them if you called right now? 📞',
    'Tell them one thing only they would understand ✨',
  ];

  late final List<String> _prompts;
  late final PageController _pageCtrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    final shuffled = [..._allPrompts]..shuffle();
    _prompts = shuffled.take(3).toList();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'सांझ',
              style: AppTypography.display(size: 52).copyWith(
                color: AppColors.emberWarm.withValues(alpha: 0.28),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No moments yet.',
              style: AppTypography.title(size: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Prompt cards — full width, paged
            SizedBox(
              height: 158,
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _prompts.length,
                itemBuilder: (_, i) => _PromptCard(
                  prompt: _prompts[i],
                  onActivate: () => context.push(
                    AppRoutes.voiceRecord,
                    extra: {
                      'isVideo': false,
                      'autoStart': true,
                      'prompt': _prompts[i],
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _prompts.length,
                (i) => _PromptDot(active: i == _page),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptCard extends StatefulWidget {
  final String prompt;
  final VoidCallback onActivate;
  const _PromptCard({required this.prompt, required this.onActivate});

  @override
  State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onActivate();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onLongPress: widget.onActivate,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          decoration: BoxDecoration(
            color: AppColors.ember.withValues(alpha: _pressed ? 0.11 : 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.emberWarm
                  .withValues(alpha: _pressed ? 0.44 : 0.22),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.prompt,
                style: AppTypography.serifItalic(size: 17),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Text(
                'Hold to record this →',
                style: AppTypography.label(
                    size: 12, color: AppColors.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptDot extends StatelessWidget {
  final bool active;
  const _PromptDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 16.0 : 6.0,
      height: 6,
      decoration: BoxDecoration(
        color: active
            ? AppColors.emberWarm
            : AppColors.emberWarm.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// ─── Expired bubble (tombstone) ───────────────────────────────────────────────

class _ExpiredBubble extends StatelessWidget {
  final _Entry entry;
  const _ExpiredBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isMine = entry.isMine;
    final icon = entry.type == _EntryType.video
        ? Icons.videocam_off_rounded
        : Icons.mic_off_rounded;
    final label = entry.type == _EntryType.video ? 'Video' : 'Voice note';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(20),
            bottomLeft: isMine ? const Radius.circular(20) : const Radius.circular(4),
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textFaint.withValues(alpha: 0.45)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.label(
                    size: 12,
                    color: AppColors.textFaint.withValues(alpha: 0.50),
                  ),
                ),
                Text(
                  entry.time,
                  style: AppTypography.label(
                    size: 10.5,
                    color: AppColors.textFaint.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Voice bubble ─────────────────────────────────────────────────────────────

class _VoiceBubble extends StatefulWidget {
  final _Entry entry;
  final String diaryId;
  final bool playing;
  final AnimationController? playCtrl;
  final double speed;
  final VoidCallback onToggleSpeed;
  final bool isShowingEndCard;
  final String contactName;
  final Color contactColor;
  final VoidCallback onTap;
  final void Function(String msg) onShowBanner;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;

  const _VoiceBubble({
    required this.entry,
    required this.diaryId,
    required this.playing,
    required this.playCtrl,
    required this.speed,
    required this.onToggleSpeed,
    required this.isShowingEndCard,
    required this.contactName,
    required this.contactColor,
    required this.onTap,
    required this.onShowBanner,
    this.onDelete,
    this.onRetry,
  });

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  bool _transcriptExpanded = false;

  void _openContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _VoiceBubbleContextSheet(
        entry: widget.entry,
        diaryId: widget.diaryId,
        onShowBanner: widget.onShowBanner,
        onDelete: widget.onDelete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.entry.isMine;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: GestureDetector(
          onTap: widget.entry.isPending ? null
              : widget.entry.isFailed ? widget.onRetry
              : widget.onTap,
          onLongPress: (widget.entry.isPending || widget.entry.isFailed)
              ? null
              : () => _openContextMenu(context),
          child: ListenableBuilder(
            listenable: DiaryStore.instance,
            builder: (_, _) {
              final isJarred =
                  DiaryStore.instance.isJarred(widget.diaryId, widget.entry.id);

              // Mood energy tint — looked up from DiaryStore each rebuild.
              double? moodEnergy;
              try {
                moodEnergy = DiaryStore.instance
                    .entriesFor(widget.diaryId)
                    .firstWhere((e) => e.id == widget.entry.id)
                    .moodEnergy;
              } catch (_) {}
              final Color? moodTint;
              final double moodAlpha;
              if (moodEnergy == null || moodEnergy > 0.3 && moodEnergy <= 0.6) {
                moodTint = null;
                moodAlpha = 0;
              } else if (moodEnergy <= 0.3) {
                moodTint = const Color(0xFF0A5AC2);
                moodAlpha = 0.03;
              } else if (moodEnergy <= 0.8) {
                moodTint = const Color(0xFFFF9500);
                moodAlpha = 0.04;
              } else {
                moodTint = const Color(0xFFFF6B00);
                moodAlpha = 0.06;
              }

              return Stack(
                children: [
                  AnimatedContainer(
                    duration: AppMotion.fast,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(14),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: isMine
                          ? AppColors.ember.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20).copyWith(
                        bottomRight: isMine
                            ? const Radius.circular(4)
                            : const Radius.circular(20),
                        bottomLeft: isMine
                            ? const Radius.circular(20)
                            : const Radius.circular(4),
                      ),
                      border: Border.all(
                        color: isMine
                            ? AppColors.emberWarm.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Received notes: faint avatar colour tint
                        if (!isMine)
                          Positioned.fill(
                            child: Container(
                              color: widget.contactColor.withValues(alpha: 0.05),
                            ),
                          ),
                        // Mood energy tint (all entries, appears after first play)
                        if (moodTint != null)
                          Positioned.fill(
                            child: Container(
                              color: moodTint.withValues(alpha: moodAlpha),
                            ),
                          ),
                        AnimatedSwitcher(
                          duration: AppMotion.medium,
                          child: widget.isShowingEndCard
                              ? _EndCard(
                                  key: const ValueKey('end'),
                                  contactFirstName: widget.contactName
                                      .split(' ')
                                      .first,
                                  duration: widget.entry.duration,
                                  time: widget.entry.time,
                                  onPlayAgain: widget.onTap,
                                  onRecordBack: () => context.push(
                                    AppRoutes.voiceRecord,
                                    extra: {'isVideo': false},
                                  ),
                                )
                              : _BubbleBody(
                                  key: const ValueKey('body'),
                                  entry: widget.entry,
                                  isMine: isMine,
                                  playing: widget.playing,
                                  playCtrl: widget.playCtrl,
                                  speed: widget.speed,
                                  onToggleSpeed: widget.onToggleSpeed,
                                  transcriptExpanded: _transcriptExpanded,
                                  onToggleTranscript: () => setState(
                                    () => _transcriptExpanded =
                                        !_transcriptExpanded,
                                  ),
                                  isPending: widget.entry.isPending,
                                  isFailed: widget.entry.isFailed,
                                ),
                        ),
                      ],
                    ),
                  ),
                  // Jar indicator — bottom-left ✨
                  if (isJarred)
                    const Positioned(
                      bottom: 6,
                      left: 6,
                      child: Text('✨', style: TextStyle(fontSize: 10)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Bubble body (extracted so AnimatedSwitcher can swap it for _EndCard) ─────

class _BubbleBody extends StatelessWidget {
  final _Entry entry;
  final bool isMine;
  final bool playing;
  final AnimationController? playCtrl;
  final double speed;
  final VoidCallback onToggleSpeed;
  final bool transcriptExpanded;
  final VoidCallback onToggleTranscript;
  final bool isPending;
  final bool isFailed;

  const _BubbleBody({
    super.key,
    required this.entry,
    required this.isMine,
    required this.playing,
    required this.playCtrl,
    required this.speed,
    required this.onToggleSpeed,
    required this.transcriptExpanded,
    required this.onToggleTranscript,
    this.isPending = false,
    this.isFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
                // Occasion tag chip — shown when note was a festival greeting
                if (entry.occasionTag != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emberWarm.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.emberWarm.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      entry.occasionTag!,
                      style: AppTypography.label(
                          size: 11, color: AppColors.emberWarm),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Prompt label — shown when the note was recorded from a prompt
                if (entry.prompt != null) ...[
                  Text(
                    '💬 ${entry.prompt!.length > 30 ? '${entry.prompt!.substring(0, 30)}…' : entry.prompt!}',
                    style: AppTypography.label(
                        size: 11, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Play / pending / failed button
                    if (isPending)
                      SizedBox(
                        width: 40, height: 40,
                        child: Center(
                          child: SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              color: AppColors.emberWarm.withValues(alpha: 0.65),
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      )
                    else if (isFailed)
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.destructive.withValues(alpha: 0.15),
                        ),
                        child: const Icon(Icons.refresh_rounded,
                            size: 20, color: AppColors.destructive),
                      )
                    else
                      AnimatedContainer(
                        duration: AppMotion.fast,
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: playing
                              ? AppColors.emberWarm
                              : isMine
                                  ? AppColors.ember.withValues(alpha: 0.35)
                                  : Colors.white.withValues(alpha: 0.10),
                          boxShadow: playing
                              ? [BoxShadow(
                                  color: AppColors.ember.withValues(alpha: 0.5),
                                  blurRadius: 16, offset: const Offset(0, 4))]
                              : null,
                        ),
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 22,
                          color: playing
                              ? Colors.white
                              : isMine
                                  ? AppColors.emberBright
                                  : AppColors.textMuted,
                        ),
                      ),
                    const SizedBox(width: 10),
                    // Waveform + progress + speed toggle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 28,
                            child: (isPending || entry.path.isEmpty)
                                // Shimmer waveform while pending/loading
                                ? SaanjhShimmer(
                                    isLoading: true,
                                    child: Container(
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: AppColors.inkRaised,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                    ),
                                  )
                                : Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _WaveformPainter(
                                      color: (isFailed
                                              ? AppColors.destructive
                                              : isMine
                                                  ? AppColors.emberWarm
                                                  : AppColors.textMuted)
                                          .withValues(alpha: 0.4),
                                      seed: entry.id.hashCode,
                                    ),
                                  ),
                                ),
                                if (playing && playCtrl != null)
                                  AnimatedBuilder(
                                    animation: playCtrl!,
                                    builder: (_, w) => ClipRect(
                                      clipper:
                                          _ProgressClipper(playCtrl!.value),
                                      child: CustomPaint(
                                        size: const Size(double.infinity, 28),
                                        painter: _WaveformPainter(
                                          color: isMine
                                              ? AppColors.emberWarm
                                              : AppColors.text,
                                          seed: entry.id.hashCode,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Duration / status + speed toggle
                          Row(
                            children: [
                              Expanded(
                                child: isPending
                                    ? Text(
                                        'Sending…',
                                        style: AppTypography.label(
                                          size: 11,
                                          color: AppColors.emberWarm
                                              .withValues(alpha: 0.65),
                                        ),
                                      )
                                    : isFailed
                                        ? Text(
                                            '⚠ Failed · tap to retry',
                                            style: AppTypography.label(
                                              size: 11,
                                              color: AppColors.destructive,
                                            ),
                                          )
                                        : AnimatedBuilder(
                                            animation: playCtrl ??
                                                const AlwaysStoppedAnimation(0),
                                            builder: (_, w) {
                                              final totalSecs =
                                                  playCtrl?.duration?.inSeconds ??
                                                      entry.durationSeconds;
                                              final elapsed =
                                                  playing && playCtrl != null
                                                      ? (playCtrl!.value * totalSecs)
                                                          .floor()
                                                      : 0;
                                              final totalLabel =
                                                  '0:${totalSecs.toString().padLeft(2, '0')}';
                                              return Text(
                                                playing
                                                    ? '0:${elapsed.toString().padLeft(2, '0')} / $totalLabel'
                                                    : entry.duration,
                                                style: AppTypography.label(
                                                  size: 11,
                                                  color: isMine
                                                      ? AppColors.emberBright
                                                      : AppColors.textFaint,
                                                ),
                                              );
                                            },
                                          ),
                              ),
                              if (!isPending && !isFailed)
                                // Speed toggle — cycles 1×→1.5×→2×→1×
                                GestureDetector(
                                  onTap: onToggleSpeed,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.textFaint
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      // Remove trailing .0: "1.0×" → "1×"
                                      '${speed == speed.truncate() ? speed.truncate() : speed}×',
                                      style: AppTypography.label(
                                        size: 10,
                                        weight: FontWeight.w700,
                                        color: speed > 1.0
                                            ? AppColors.emberBright
                                            : AppColors.textFaint,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Transcript preview — prefer DiaryStore transcript over _Entry.transcript (item 2)
                Builder(builder: (ctx) {
                  // Look up DiaryEntry for a real transcript (added via _send())
                  DiaryEntry? storeEntry;
                  try {
                    storeEntry = DiaryStore.instance
                        .entriesFor(entry.id.split('_').first.isNotEmpty
                            ? entry.id
                            : '')
                        .firstWhere((e) => e.id == entry.id);
                  } catch (_) {}
                  final transcript =
                      storeEntry?.transcript ?? entry.transcript;
                  if (transcript == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: GestureDetector(
                      onTap: transcript.length > 60
                          ? onToggleTranscript
                          : null,
                      child: AnimatedSize(
                        duration: AppMotion.medium,
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              transcriptExpanded || transcript.length <= 60
                                  ? transcript
                                  : transcript.substring(0, 60),
                              style: AppTypography.serifItalic(
                                  size: 13, color: AppColors.textMuted),
                            ),
                            if (transcript.length > 60 && !transcriptExpanded)
                              Text(
                                '... more',
                                style: AppTypography.label(
                                    size: 11, color: AppColors.textFaint),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                if (!isPending && !isFailed)
                  ListenableBuilder(
                    listenable: DiaryStore.instance,
                    builder: (_, _) {
                      final listenedLabel =
                          DiaryStore.instance.listenedAtLabel(entry.id);
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            entry.time,
                            style: AppTypography.label(
                                size: 10.5, color: AppColors.textFaint),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 5),
                            AnimatedSwitcher(
                              duration: AppMotion.medium,
                              child: listenedLabel != null
                                  ? _ListenedLabel(
                                      time: listenedLabel,
                                      key: const ValueKey('listened'),
                                    )
                                  : Icon(
                                      Icons.done_rounded,
                                      key: const ValueKey('sent'),
                                      size: 13,
                                      color: AppColors.textFaint,
                                    ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
              ],
    );
  }
}

// ─── End card (shown 3s after playback completes) ────────────────────────────

class _EndCard extends StatelessWidget {
  final String contactFirstName;
  final String duration;
  final String time;
  final VoidCallback onPlayAgain;
  final VoidCallback onRecordBack;

  const _EndCard({
    super.key,
    required this.contactFirstName,
    required this.duration,
    required this.time,
    required this.onPlayAgain,
    required this.onRecordBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "$contactFirstName's voice",
            style: AppTypography.caption(color: AppColors.textFaint),
          ),
          const SizedBox(height: 6),
          Text(
            duration,
            style: AppTypography.serifItalic(
                size: 22, color: AppColors.emberWarm),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: AppTypography.caption(color: AppColors.textFaint),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: onPlayAgain,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
                child: Text(
                  '↻ Play again',
                  style: AppTypography.label(
                      size: 12, color: AppColors.textMuted),
                ),
              ),
              Container(
                width: 1, height: 14,
                color: AppColors.borderSoft,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),
              TextButton(
                onPressed: onRecordBack,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
                child: Text(
                  '🎙 Record back',
                  style: AppTypography.label(
                      size: 12, color: AppColors.emberWarm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Voice bubble context sheet ───────────────────────────────────────────────

class _VoiceBubbleContextSheet extends StatefulWidget {
  final _Entry entry;
  final String diaryId;
  final void Function(String msg) onShowBanner;
  final VoidCallback? onDelete;

  const _VoiceBubbleContextSheet({
    required this.entry,
    required this.diaryId,
    required this.onShowBanner,
    this.onDelete,
  });

  @override
  State<_VoiceBubbleContextSheet> createState() =>
      _VoiceBubbleContextSheetState();
}

class _VoiceBubbleContextSheetState extends State<_VoiceBubbleContextSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  bool get _isJarred =>
      DiaryStore.instance.isJarred(widget.diaryId, widget.entry.id);

  String get _contactName {
    try {
      return DiaryStore.instance.diaries
          .firstWhere((d) => d.id == widget.diaryId)
          .displayName;
    } catch (_) {
      return 'them';
    }
  }

  DateTime get _createdAt {
    try {
      return DiaryStore.instance
          .entriesFor(widget.diaryId)
          .firstWhere((e) => e.id == widget.entry.id)
          .createdAt;
    } catch (_) {
      return DateTime.now();
    }
  }

  void _toggleJar() {
    if (_isJarred) {
      DiaryStore.instance.unjarEntry(widget.diaryId, widget.entry.id);
    } else {
      DiaryStore.instance.jarEntry(widget.diaryId, widget.entry.id);
      widget.onShowBanner('✨ Saved to your Memory Jar');
    }
    setState(() {});
    Navigator.pop(context);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    await ShareCardService.instance
        .shareVoiceCard(_cardKey, _contactName);
    if (mounted) {
      setState(() => _sharing = false);
      Navigator.pop(context);
    }
  }

  void _copyTranscript() {
    if (widget.entry.transcript == null) return;
    Clipboard.setData(ClipboardData(text: widget.entry.transcript!));
    Navigator.pop(context);
    widget.onShowBanner('Transcript copied');
  }

  void _delete() {
    Navigator.pop(context);
    DiaryStore.instance.removeEntry(widget.entry.id);
    widget.onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Off-screen card — zero layout size, captured by ShareCardService
              Offstage(
                child: VoiceShareCard(
                  key: _cardKey,
                  contactName: _contactName,
                  duration: widget.entry.duration,
                  createdAt: _createdAt,
                  seed: widget.entry.id.hashCode.abs(),
                ),
              ),

              // Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Save / remove jar
              _SheetRow(
                icon: _isJarred ? Icons.star_rounded : Icons.star_outline_rounded,
                iconColor: AppColors.emberWarm,
                label: _isJarred ? '✓ Saved · Remove from Jar' : '✨ Save to Memory Jar',
                onTap: _toggleJar,
              ),

              // Share
              _SheetRow(
                icon: Icons.ios_share_rounded,
                label: 'Share this moment →',
                trailing: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: AppColors.emberWarm,
                        ),
                      )
                    : null,
                onTap: _sharing ? null : _share,
              ),

              // Copy transcript (only if transcript exists)
              if (widget.entry.transcript != null)
                _SheetRow(
                  icon: Icons.copy_rounded,
                  label: 'Copy transcript',
                  onTap: _copyTranscript,
                ),

              // Delete (isMine only)
              if (widget.entry.isMine)
                _SheetRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: AppColors.destructive,
                  label: 'Delete',
                  labelColor: AppColors.destructive,
                  onTap: _delete,
                ),

              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SheetRow({
    required this.icon,
    this.iconColor,
    required this.label,
    this.labelColor,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.textMuted;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: AppTypography.body(
          size: 15,
          color: labelColor ?? AppColors.text,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

// ─── Listened receipt label ───────────────────────────────────────────────────

// ─── Label editor sheet ───────────────────────────────────────────────────────

class _LabelEditorSheet extends StatefulWidget {
  final String initialValue;
  final void Function(String) onSave;
  const _LabelEditorSheet(
      {required this.initialValue, required this.onSave});

  @override
  State<_LabelEditorSheet> createState() => _LabelEditorSheetState();
}

class _LabelEditorSheetState extends State<_LabelEditorSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.modalSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Custom label',
                    style: AppTypography.title(size: 18)),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  style: AppTypography.body(size: 16),
                  decoration: InputDecoration(
                    hintText: 'e.g. Mama, Best friend…',
                    hintStyle: AppTypography.body(
                        size: 16,
                        color: AppColors.textFaint),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: widget.onSave,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => widget.onSave(''),
                        child: Text('Clear label',
                            style: AppTypography.label(
                                size: 14, color: AppColors.textFaint)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onSave(_ctrl.text.trim()),
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: AppColors.emberGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text('Save',
                                style:
                                    AppTypography.button(color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Colour picker sheet ──────────────────────────────────────────────────────

class _ColourPickerSheet extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onSelect;
  const _ColourPickerSheet(
      {required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Choose a colour', style: AppTypography.title(size: 18)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                    DiaryContact.avatarPalette.length, (i) {
                  final color = DiaryContact.avatarPalette[i];
                  final selected = i == currentIndex;
                  return GestureDetector(
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: selected
                            ? Border.all(color: Colors.white, width: 2.5)
                            : null,
                        boxShadow: selected
                            ? [BoxShadow(
                                color: color.withValues(alpha: 0.55),
                                blurRadius: 12)]
                            : null,
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded,
                              size: 16, color: Colors.white)
                          : null,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Listened receipt label ───────────────────────────────────────────────────

class _ListenedLabel extends StatelessWidget {
  final String time;
  const _ListenedLabel({required this.time, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.done_all_rounded,
            size: 13, color: Color(0xFF7CD992)),
        const SizedBox(width: 3),
        Text(
          'Listened $time',
          style: AppTypography.label(
            size: 10.5,
            weight: FontWeight.w600,
            color: const Color(0xFF7CD992),
          ),
        ),
      ],
    );
  }
}

// ─── Video bubble ─────────────────────────────────────────────────────────────

class _VideoBubble extends StatefulWidget {
  final _Entry entry;
  final VoidCallback? onRetry;
  const _VideoBubble({required this.entry, this.onRetry});

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isMine = widget.entry.isMine;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.70),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.entry.isPending
              ? null
              : widget.entry.isFailed
                  ? widget.onRetry
                  : () {
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Playing video…',
                              style: AppTypography.label(
                                  size: 13, color: Colors.white)),
                          backgroundColor: AppColors.modalSurface,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
          child: AnimatedContainer(
            duration: AppMotion.fast,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20).copyWith(
                bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(20),
                bottomLeft:  isMine ? const Radius.circular(20) : const Radius.circular(4),
              ),
              border: Border.all(
                color: isMine
                    ? AppColors.violet.withValues(alpha: _pressed ? 0.55 : 0.35)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19).copyWith(
                bottomRight: isMine ? const Radius.circular(3) : const Radius.circular(19),
                bottomLeft:  isMine ? const Radius.circular(19) : const Radius.circular(3),
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isMine
                                ? [const Color(0xFF5A2090), const Color(0xFF280A50)]
                                : [const Color(0xFF1C0A35), const Color(0xFF0D0520)],
                          ),
                        ),
                      ),
                      if (widget.entry.isPending)
                        const SizedBox(
                          width: 48, height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 26, height: 26,
                              child: CircularProgressIndicator(
                                color: Colors.white54,
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        )
                      else
                        AnimatedScale(
                          scale: _pressed ? 0.88 : 1.0,
                          duration: AppMotion.fast,
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.entry.isFailed
                                  ? AppColors.destructive.withValues(alpha: 0.35)
                                  : Colors.white.withValues(alpha: 0.18),
                              border: Border.all(
                                  color: widget.entry.isFailed
                                      ? AppColors.destructive.withValues(alpha: 0.7)
                                      : Colors.white.withValues(alpha: 0.4),
                                  width: 1.5),
                            ),
                            child: Icon(
                              widget.entry.isFailed
                                  ? Icons.refresh_rounded
                                  : Icons.play_arrow_rounded,
                              size: 26,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 8, left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.videocam_rounded, size: 11, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(widget.entry.duration,
                                  style: AppTypography.caption(size: 10.5,
                                      weight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    color: isMine
                        ? AppColors.violet.withValues(alpha: 0.18)
                        : Colors.black.withValues(alpha: 0.40),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.entry.transcript != null)
                          Text(widget.entry.transcript!,
                              style: AppTypography.serifItalic(size: 13.5, color: AppColors.textMuted)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.entry.isPending)
                              Text('Sending…',
                                  style: AppTypography.caption(
                                      size: 10.5,
                                      color: AppColors.emberWarm
                                          .withValues(alpha: 0.65)))
                            else if (widget.entry.isFailed)
                              Text('⚠ Failed · tap to retry',
                                  style: AppTypography.caption(
                                      size: 10.5,
                                      color: AppColors.destructive))
                            else ...[
                              Text(widget.entry.time,
                                  style: AppTypography.caption(
                                      size: 10.5, color: AppColors.textFaint)),
                              if (isMine) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  widget.entry.listened
                                      ? Icons.done_all_rounded
                                      : Icons.done_rounded,
                                  size: 13,
                                  color: widget.entry.listened
                                      ? AppColors.violet
                                      : AppColors.textFaint,
                                ),
                              ],
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Waveform painter ─────────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final Color color;
  final int seed;
  _WaveformPainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()..color = color..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    const n = 26;
    final step = size.width / n;
    for (int i = 0; i < n; i++) {
      final h = size.height * (0.25 + 0.65 * rng.nextDouble());
      final x = i * step + step / 2;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter o) => o.color != color || o.seed != seed;
}

class _ProgressClipper extends CustomClipper<Rect> {
  final double progress;
  _ProgressClipper(this.progress);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * progress, size.height);
  @override
  bool shouldReclip(_ProgressClipper o) => o.progress != progress;
}

// ─── Bottom action bar ────────────────────────────────────────────────────────
// Three intentional actions in one bar: Pulse · Compose · Record.

class _BottomActionBar extends StatefulWidget {
  final String diaryId;
  final String personName;
  final VoidCallback onRecord;
  final VoidCallback onPulse;

  const _BottomActionBar({
    required this.diaryId,
    required this.personName,
    required this.onRecord,
    required this.onPulse,
  });

  @override
  State<_BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends State<_BottomActionBar>
    with SingleTickerProviderStateMixin {
  bool _recordPressed = false;
  bool _breakBannerDismissed = false;
  late final AnimationController _pulseBreath;

  @override
  void initState() {
    super.initState();
    _pulseBreath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseBreath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([FlickerStore.instance, DiaryStore.instance]),
      builder: (_, w) {
        final ps = FlickerStore.instance;
        final ds = DiaryStore.instance;

        final received   = ps.receivedToday(widget.diaryId);
        final hasPulsed  = received != null;
        final isMutual   = ps.isMutualToday(widget.diaryId);
        final meSent     = ps.hasMeFlickeredToday(widget.diaryId);
        final showPulseBanner = hasPulsed && !meSent;

        final streakDays = ds.streakDays(widget.diaryId);
        final atRisk     = ds.streakAtRisk(widget.diaryId);
        final sentToday  = ds.hasSentToday(widget.diaryId);
        final justBroke  = ds.hasBrokeStreak(widget.diaryId);
        final showStreakBanner = streakDays > 0 && atRisk && !sentToday;
        final showBreakBanner  = justBroke && !_breakBannerDismissed;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Streak just-broke banner ──────────────────────────────────
            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.easeOut,
              child: showBreakBanner
                  ? _StreakBreakBanner(
                      previousDays: DiaryStore.instance
                          .brokeStreakPreviousDays(widget.diaryId),
                      personName: widget.personName,
                      onRecord: widget.onRecord,
                      onDismiss: () =>
                          setState(() => _breakBannerDismissed = true),
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Streak at-risk warning ────────────────────────────────────
            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.easeOut,
              child: showStreakBanner
                  ? _StreakAtRiskBanner(
                      days: streakDays,
                      personName: widget.personName,
                      onRecord: widget.onRecord,
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Contextual pulse banner ──────────────────────────────────
            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.easeOut,
              child: showPulseBanner
                  ? _PulseBanner(
                      personName: widget.personName,
                      receivedTime: received.timeLabel,
                      onTap: widget.onPulse,
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Three-button action bar ──────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                  14, 10, 14, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                border: Border(
                  top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06), width: 1),
                ),
              ),
              child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ① Pulse button (left FAB)
                        _PulseButton(
                          hasPulsed: hasPulsed,
                          isMutual: isMutual,
                          meSent: meSent,
                          breatheCtrl: _pulseBreath,
                          onTap: widget.onPulse,
                        ),

                        const SizedBox(width: 10),

                        // ② Compose pill — tap = picker, hold = record voice
                        Expanded(
                          child: GestureDetector(
                            onTap: widget.onRecord,
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              context.push(AppRoutes.voiceRecord,
                                  extra: {'isVideo': false, 'autoStart': true});
                            },
                            child: Container(
                              height: 50,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    width: 1),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.mic_none_rounded,
                                      size: 17, color: AppColors.textFaint),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      'Hold to record · Tap for more',
                                      style: AppTypography.label(
                                          size: 12.5,
                                          color: AppColors.textFaint),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                  const SizedBox(width: 10),

                  // ③ Record FAB (right) — tap = picker, hold = instant voice
                  GestureDetector(
                    onTapDown: (_) =>
                        setState(() => _recordPressed = true),
                    onTapUp: (_) =>
                        setState(() => _recordPressed = false),
                    onTapCancel: () =>
                        setState(() => _recordPressed = false),
                    onTap: widget.onRecord,
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      context.push(AppRoutes.voiceRecord,
                          extra: {'isVideo': false, 'autoStart': true});
                    },
                    child: AnimatedScale(
                      scale: _recordPressed ? 0.92 : 1.0,
                      duration: AppMotion.fast,
                      child: Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.emberGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.ember
                                  .withValues(alpha: 0.50),
                              blurRadius: 20,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Pulse button (left FAB) ───────────────────────────────────────────────────

class _PulseButton extends StatefulWidget {
  final bool hasPulsed;
  final bool isMutual;
  final bool meSent;
  final AnimationController breatheCtrl;
  final VoidCallback onTap;

  const _PulseButton({
    required this.hasPulsed,
    required this.isMutual,
    required this.meSent,
    required this.breatheCtrl,
    required this.onTap,
  });

  @override
  State<_PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<_PulseButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Colour states
    final Color iconColor;
    final Color bgColor;
    final Color borderColor;
    final List<BoxShadow> shadows;
    final IconData icon;

    if (widget.isMutual) {
      icon        = Icons.favorite_rounded;
      iconColor   = AppColors.successGreen;
      bgColor     = AppColors.successGreen.withValues(alpha: 0.14);
      borderColor = AppColors.successGreen.withValues(alpha: 0.50);
      shadows     = [BoxShadow(
        color: AppColors.successGreen.withValues(alpha: 0.35),
        blurRadius: 18, offset: const Offset(0, 5),
      )];
    } else if (widget.hasPulsed && !widget.meSent) {
      // Received but not sent back — most important state, amber glow
      icon        = Icons.favorite_rounded;
      iconColor   = AppColors.emberWarm;
      bgColor     = AppColors.ember.withValues(alpha: 0.18);
      borderColor = AppColors.emberWarm.withValues(alpha: 0.55);
      shadows     = [BoxShadow(
        color: AppColors.ember.withValues(alpha: 0.40),
        blurRadius: 20, offset: const Offset(0, 6),
      )];
    } else if (widget.meSent) {
      // Sent, waiting for theirs — dim amber
      icon        = Icons.favorite_rounded;
      iconColor   = AppColors.emberWarm.withValues(alpha: 0.45);
      bgColor     = Colors.white.withValues(alpha: 0.04);
      borderColor = Colors.white.withValues(alpha: 0.08);
      shadows     = [];
    } else {
      // Nothing yet — quiet amber outline
      icon        = Icons.favorite_border_rounded;
      iconColor   = AppColors.emberWarm.withValues(alpha: 0.45);
      bgColor     = AppColors.ember.withValues(alpha: 0.06);
      borderColor = AppColors.emberWarm.withValues(alpha: 0.20);
      shadows     = [];
    }

    // Breathing scale only when received but not sent back
    final breathes = widget.hasPulsed && !widget.meSent && !widget.isMutual;

    return Semantics(
      label: widget.meSent ? 'Pulse sent' : 'Send pulse',
      button: true,
      child: GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: widget.breatheCtrl,
        builder: (_, child) {
          final breatheScale = breathes
              ? 1.0 + 0.045 * widget.breatheCtrl.value
              : 1.0;
          return AnimatedScale(
            scale: _pressed ? 0.90 : breatheScale,
            duration: _pressed
                ? AppMotion.fast
                : const Duration(milliseconds: 80),
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: AppMotion.medium,
          width: 50, height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: shadows,
          ),
          child: Center(
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
      ), // close Semantics
    );
  }
}

// ── Streak break banner ────────────────────────────────────────────────────────

class _StreakBreakBanner extends StatelessWidget {
  final int previousDays;
  final String personName;
  final VoidCallback onRecord;
  final VoidCallback onDismiss;

  const _StreakBreakBanner({
    required this.previousDays,
    required this.personName,
    required this.onRecord,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final first = personName.split(' ').first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0800),
        border: Border(
          top: BorderSide(
              color: AppColors.emberWarm.withValues(alpha: 0.15), width: 1),
          bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.03), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.favorite_rounded,
              size: 16, color: AppColors.emberWarm.withValues(alpha: 0.55)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  previousDays > 0
                      ? 'Your $previousDays-day streak paused. It\'s okay. $first\'s still there.'
                      : 'Your streak paused. It\'s okay. $first\'s still there.',
                  style: AppTypography.serifItalic(size: 14)
                      .copyWith(color: AppColors.textMuted),
                ),
                TextButton(
                  onPressed: onRecord,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Record something now →',
                    style: AppTypography.label(
                        size: 12,
                        weight: FontWeight.w600,
                        color: AppColors.emberBright),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close_rounded,
                  size: 14,
                  color: AppColors.textFaint.withValues(alpha: 0.60)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Streak at-risk banner ──────────────────────────────────────────────────────

class _StreakAtRiskBanner extends StatelessWidget {
  final int days;
  final String personName;
  final VoidCallback onRecord;

  const _StreakAtRiskBanner({
    required this.days,
    required this.personName,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRecord,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.destructive.withValues(alpha: 0.08),
          border: Border(
            top: BorderSide(
                color: AppColors.destructive.withValues(alpha: 0.28), width: 1),
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.03), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Pulsing hourglass
            Text('⏳', style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: AppTypography.label(
                      size: 13, color: AppColors.textMuted),
                  children: [
                    TextSpan(
                      text: '🔥 $days-day streak ',
                      style: TextStyle(
                          color: const Color(0xFFFF8A82),
                          fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                        text: 'with ${personName.split(' ').first} · send a note to keep it'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Record →',
              style: AppTypography.label(
                size: 12,
                weight: FontWeight.w700,
                color: const Color(0xFFFF8A82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Contextual pulse received banner ─────────────────────────────────────────

class _PulseBanner extends StatelessWidget {
  final String personName;
  final String receivedTime;
  final VoidCallback onTap;

  const _PulseBanner({
    required this.personName,
    required this.receivedTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.ember.withValues(alpha: 0.10),
          border: Border(
            top: BorderSide(
                color: AppColors.emberWarm.withValues(alpha: 0.22), width: 1),
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.04), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Amber pulse dot
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.emberWarm,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.emberWarm.withValues(alpha: 0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: AppTypography.label(
                      size: 13, color: AppColors.textMuted),
                  children: [
                    TextSpan(
                      text: personName,
                      style: TextStyle(
                          color: AppColors.emberBright,
                          fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: ' was here at $receivedTime'),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Hold ♥ to say you\'re here',
              style: AppTypography.label(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: AppColors.emberBright),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Record mode picker sheet ─────────────────────────────────────────────────

class _RecordSheet extends StatelessWidget {
  final String recipientName;
  final VoidCallback onVoice;
  final VoidCallback onVideo;

  const _RecordSheet({
    required this.recipientName,
    required this.onVoice,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              Text('Send to $recipientName', style: AppTypography.title(size: 20)),
              const SizedBox(height: 16),
              _PickerTile(
                icon: Icons.mic_rounded, color: AppColors.emberWarm,
                title: 'Voice note', sub: 'Up to 20 seconds · auto-transcribed',
                onTap: onVoice,
              ),
              const SizedBox(height: 10),
              _PickerTile(
                icon: Icons.videocam_rounded, color: AppColors.violet,
                title: 'Video clip', sub: 'Up to 20 seconds · saved in Memory Tree',
                onTap: onVideo,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _PickerTile({required this.icon, required this.color,
      required this.title, required this.sub, required this.onTap});

  @override
  State<_PickerTile> createState() => _PickerTileState();
}

class _PickerTileState extends State<_PickerTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _pressed ? widget.color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _pressed ? widget.color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.14)),
              child: Icon(widget.icon, size: 22, color: widget.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                  Text(widget.sub, style: AppTypography.label(size: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

// ─── More menu sheet ──────────────────────────────────────────────────────────

class _MoreMenuSheet extends StatelessWidget {
  final VoidCallback onWish;
  final VoidCallback? onMemoryBook; // null = locked (streak < 30)
  final int memoryBookStreak;
  final VoidCallback onMemoryTree;
  final VoidCallback onOccasion;
  final VoidCallback onDelete;
  final VoidCallback? onShareStreak;

  const _MoreMenuSheet({
    required this.onWish,
    required this.onMemoryBook,
    required this.memoryBookStreak,
    required this.onMemoryTree,
    required this.onOccasion,
    required this.onDelete,
    this.onShareStreak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            _MenuRow(icon: Icons.star_rounded, label: 'Send a Wish  ✨',
                color: const Color(0xFFFFD60A), onTap: onWish),
            _Divider(),
            onMemoryBook != null
                ? _MenuRow(
                    icon: Icons.menu_book_rounded,
                    label: '📖 Memory Book',
                    onTap: onMemoryBook!,
                  )
                : _MenuRowDisabled(
                    icon: Icons.menu_book_rounded,
                    label: '📖 Memory Book',
                    sub: 'Preview · unlocks at 30 days'
                        ' ($memoryBookStreak/30)',
                  ),
            _Divider(),
            _MenuRow(icon: Icons.park_rounded, label: 'View Memory Tree', onTap: onMemoryTree),
            _Divider(),
            _MenuRow(icon: Icons.calendar_today_rounded, label: 'Set a reminder', onTap: onOccasion),
            _Divider(),
            if (onShareStreak != null) ...[
              _Divider(),
              _MenuRow(
                icon: Icons.share_rounded,
                label: 'Share streak →',
                onTap: onShareStreak!,
              ),
            ],
            _Divider(),
            _MenuRow(icon: Icons.delete_outline_rounded, label: 'Delete this diary',
                color: AppColors.destructive, onTap: onDelete),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MenuRow({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 20, color: c),
          const SizedBox(width: 14),
          Text(label, style: AppTypography.body(size: 15, color: c)),
          const Spacer(),
        ]),
      ),
    );
  }
}

class _MenuRowDisabled extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  const _MenuRowDisabled({
    required this.icon,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.textFaint),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTypography.body(size: 15, color: AppColors.textFaint)),
            Text(sub,
                style: AppTypography.caption(size: 11.5,
                    color: AppColors.textFaint.withValues(alpha: 0.6))),
          ],
        ),
        const Spacer(),
        Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textFaint),
      ]),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
      height: 1, indent: 54, color: Colors.white.withValues(alpha: 0.05));
}

