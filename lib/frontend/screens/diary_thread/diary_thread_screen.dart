import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../../backend/connections_api.dart';
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
import '../../services/media_cache_service.dart';
import '../../services/share_card_service.dart';
import '../../widgets/milestone_share_card.dart';
import '../../widgets/motion/saanjh_skeleton.dart';
import '../../widgets/saanjh_dialog.dart';
import '../../widgets/voice_share_card.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/saanjh_shimmer.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

enum _EntryType { voice, video, text }

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
  final String? content;       // text entries only
  final bool savedToMoments;  // text entries only

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
    this.content,
    this.savedToMoments = false,
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

  final _actionBarKey = GlobalKey<_BottomActionBarState>();

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
    // If entries were already in the store (cached), jump to the bottom on the
    // first frame so the newest message is visible without the user having to scroll.
    if (_entries.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom(animate: false));
    }
  }

  // ── Entry mapping ────────────────────────────────────────────────────────

  List<_Entry> _buildEntries() {
    final storeEntries = DiaryStore.instance.entriesFor(widget.diaryId);
    // Only top-level entries — reactions are nested inside DiaryEntry.reactions.
    // Oldest first → newest last: newest message sits at the bottom of the list,
    // exactly like WhatsApp / Telegram. New messages appear below existing ones.
    final topLevel = storeEntries
        .where((e) => e.parentEntryId == null)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return topLevel.map((e) {
      final entryType = e.type == 'video'
          ? _EntryType.video
          : e.type == 'text'
              ? _EntryType.text
              : _EntryType.voice;
      // Use the local file path first (just-recorded entry).
      // Fall back to the signed URL delivered via SSE — but only if it has
      // not yet expired (URLs are valid for ~1 hour after the SSE event).
      String effectivePath = e.path;
      if (effectivePath.isEmpty && e.cachedMediaUrl != null) {
        final expires = e.urlExpiresAt;
        if (expires == null || DateTime.now().isBefore(expires)) {
          effectivePath = e.cachedMediaUrl!;
        }
      }

      return _Entry(
        id: e.id,
        isMine: e.isMine,
        type: entryType,
        duration: _formatDuration(e.durationSeconds > 0 ? e.durationSeconds : 20),
        durationSeconds: e.durationSeconds > 0 ? e.durationSeconds : 20,
        transcript: e.transcript,
        prompt: e.prompt,
        occasionTag: e.occasionTag,
        time: _formatTime(e.createdAt),
        listened: e.listenedAt != null,
        path: effectivePath,
        isExpired: e.isExpired,
        isPending: e.isPending,
        isFailed: e.isFailed,
        content: e.content,
        savedToMoments: e.savedToMoments,
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

  // Scrolls the conversation to the bottom so the newest message is visible.
  // Uses jumpTo on initial load (no animation) and animateTo for live updates.
  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (max <= 0) return;
      if (animate) {
        _scrollCtrl.animateTo(max,
            duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      } else {
        _scrollCtrl.jumpTo(max);
      }
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
          content: item['content'] as String?,
          transcript: item['transcription'] as String?,
          createdAt:
              dateStr != null ? DateTime.parse(dateStr) : DateTime.now(),
          durationSeconds: item['duration_seconds'] as int? ?? 0,
          isExpired: item['is_expired'] as bool? ?? false,
          savedToMoments: item['saved_to_moments'] as bool? ?? false,
          listenedAt: (item['play_count'] as int? ?? 0) > 0
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : null,
        ));
      }
      if (toAdd.isNotEmpty && mounted) {
        DiaryStore.instance.bulkAddEntries(toAdd);
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _onDiaryStoreChange() {
    final prevCount = _entries.length;
    setState(() => _entries = _buildEntries());
    // Auto-scroll to bottom when new messages arrive (sent or received).
    if (_entries.length > prevCount) _scrollToBottom();
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
    final queuedIds = {
      ...SendQueueStore.instance.uploads.map((u) => u.pendingLocalId),
      ...SendQueueStore.instance.texts.map((t) => t.pendingLocalId),
    };
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
          content: item['content'] as String?,
          transcript: item['transcription'] as String?,
          createdAt: dateStr != null ? DateTime.parse(dateStr) : DateTime.now(),
          durationSeconds: item['duration_seconds'] as int? ?? 0,
          isExpired: item['is_expired'] as bool? ?? false,
          savedToMoments: item['saved_to_moments'] as bool? ?? false,
          listenedAt: (item['play_count'] as int? ?? 0) > 0
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : null,
        ));
      }
      DiaryStore.instance.bulkAddEntries(toAdd);
      // Cursor for on-demand older pages (scroll-up pagination).
      _nextCursor = result['next_cursor'] as String?;
      _hasMoreOlder = result['has_more'] as bool? ?? false;
    } catch (_) {
      // Network failure — show whatever is already in the store.
    } finally {
      if (mounted) {
        setState(() => _isLoadingEntries = false);
        _scrollToBottom(animate: false);
      }
    }
  }

  String? _nextCursor;
  bool _hasMoreOlder = false;
  bool _loadingOlder = false;

  /// Scroll-up pagination: fetches the next (older) page on demand. Merges by
  /// id, so cached and freshly-synced entries never duplicate.
  Future<void> _loadOlderEntries() async {
    if (_loadingOlder || !_hasMoreOlder || _nextCursor == null) return;
    _loadingOlder = true;
    try {
      final result = await EntriesApi.instance
          .listEntries(widget.diaryId, cursor: _nextCursor);
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
          content: item['content'] as String?,
          transcript: item['transcription'] as String?,
          createdAt: dateStr != null ? DateTime.parse(dateStr) : DateTime.now(),
          durationSeconds: item['duration_seconds'] as int? ?? 0,
          isExpired: item['is_expired'] as bool? ?? false,
          savedToMoments: item['saved_to_moments'] as bool? ?? false,
        ));
      }
      DiaryStore.instance.bulkAddEntries(toAdd);
      _nextCursor = result['next_cursor'] as String?;
      _hasMoreOlder = result['has_more'] as bool? ?? false;
    } catch (_) {
      // Offline — the user keeps whatever is cached.
    } finally {
      _loadingOlder = false;
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    // Near the top (oldest visible) → pull the next older page on demand.
    if (_scrollCtrl.offset < 200) _loadOlderEntries();
    // Newest messages are at the BOTTOM (offset = max = 0.0 fraction = present/warm).
    // Scrolling UP reveals older messages → fraction approaches 1.0 = past/cooler.
    final fraction = (1.0 - _scrollCtrl.offset / max).clamp(0.0, 1.0);
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

    // ── Resolve playback source (offline-first) ──────────────────────────
    // 1. Local recording path (just sent from this device).
    // 2. Media cache — downloads at most once, then plays from disk forever.
    String? playSource = entry.path.isNotEmpty ? entry.path : null;
    if (playSource == null) {
      playSource = await MediaCacheService.instance.resolve(
        diaryId: widget.diaryId,
        entryId: entry.id,
        type: entry.type == _EntryType.video ? 'video' : 'voice',
      );
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
        onText: () {
          Navigator.pop(context);
          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted) _actionBarKey.currentState?.enterTextMode();
          });
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
        onDelete: () {
          Navigator.pop(context); // close the sheet; _confirmDelete pops the thread
          _confirmDelete();
        },
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
    try {
      await ConnectionsApi.instance.deleteConnection(widget.diaryId);
      DiaryStore.instance.remove(widget.diaryId);
      if (!mounted) return;
      context.pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Couldn't delete this diary — check your connection and try again."),
        ),
      );
    }
  }

  // ── Text messaging ────────────────────────────────────────────────────────

  Future<void> _sendTextMessage(String content) async {
    if (content.trim().isEmpty) return;
    HapticFeedback.selectionClick();

    final pendingId = 'text_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    // Add optimistic entry immediately and jump to bottom.
    DiaryStore.instance.addEntry(DiaryEntry(
      id: pendingId,
      diaryId: widget.diaryId,
      isMine: true,
      type: 'text',
      path: '',
      content: content.trim(),
      createdAt: now,
      durationSeconds: 0,
      isPending: true,
    ));
    _scrollToBottom();

    try {
      final data = await EntriesApi.instance.sendTextMessage(
        connectionId: widget.diaryId,
        content: content.trim(),
        recordedAt: now,
        clientMsgId: pendingId, // stable key — retry reuses the same server row
      );
      final entryId = data['id'] as String;
      DiaryStore.instance.markTextSent(pendingId, entryId);
    } catch (_) {
      // Offline — queue for retry
      await SendQueueStore.instance.enqueueText(
        pendingLocalId: pendingId,
        diaryId: widget.diaryId,
        content: content.trim(),
        recordedAt: now,
      );
      DiaryStore.instance.markTextFailed(pendingId);
    }
  }

  @override
  Widget build(BuildContext context) {
    // _scrollFraction: 0.0 at bottom (newest / present), 1.0 at top (oldest / past).
    // As the user scrolls UP into history the fraction rises and the background
    // cools — travelling back through time feels visually different from the present.
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
                      ? const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: ThreadSkeleton(),
                        )
                      : _entries.isEmpty
                          ? _EmptyThread(diaryId: widget.diaryId)
                          : ListView(
                          controller: _scrollCtrl,
                          padding:
                              const EdgeInsets.fromLTRB(14, 12, 14, 120),
                          physics: const BouncingScrollPhysics(),
                          children: [
                            for (int i = 0; i < _entries.length; i++)
                              if (_entries[i].isExpired)
                                _ExpiredBubble(entry: _entries[i])
                              else if (_entries[i].type == _EntryType.text)
                                _TextBubble(
                                  entry: _entries[i],
                                  diaryId: widget.diaryId,
                                  onShowBanner: (msg) =>
                                      _bannerKey.currentState?.show(
                                        msg,
                                        widget.diaryId,
                                        SaanjhNotificationType.milestone,
                                      ),
                                  onRetry: () =>
                                      SendQueueStore.instance.processQueue(),
                                )
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
                                  entry:   _entries[i],
                                  diaryId: widget.diaryId,
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
                key: _actionBarKey,
                diaryId: widget.diaryId,
                personName: _contact?.name ?? 'them',
                onRecord: _showRecordPicker,
                onSendText: _sendTextMessage,
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
                            final recType =
                                DiaryStore.instance.recordingType(diaryId);
                            if (recType != null) {
                              label = recType == 'video'
                                  ? '🎥 capturing a memory…'
                                  : '🎙 capturing a memory…';
                              color = AppColors.emberBright;
                            } else if (weather == DiaryWeather.quiet) {
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
  final String diaryId;
  const _EmptyThread({required this.diaryId});

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
                      'targetDiaryId': widget.diaryId,
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

// ─── Text bubble ─────────────────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  final _Entry entry;
  final String diaryId;
  final void Function(String msg) onShowBanner;
  final VoidCallback? onRetry;

  const _TextBubble({
    required this.entry,
    required this.diaryId,
    required this.onShowBanner,
    this.onRetry,
  });

  void _openContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TextBubbleContextSheet(
        entry: entry,
        diaryId: diaryId,
        onShowBanner: onShowBanner,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = entry.isMine;
    final text = entry.content ?? '';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: GestureDetector(
          onTap: (entry.isPending || entry.isFailed) ? onRetry : null,
          onLongPress: (entry.isPending || entry.isFailed)
              ? null
              : () => _openContextMenu(context),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: AppTypography.body(size: 15).copyWith(height: 1.45),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.savedToMoments) ...[
                      const Text('✨', style: TextStyle(fontSize: 10)),
                      const SizedBox(width: 4),
                    ],
                    if (entry.isPending)
                      Text(
                        'Sending…',
                        style: AppTypography.label(
                            size: 10.5,
                            color: AppColors.emberWarm.withValues(alpha: 0.65)),
                      )
                    else if (entry.isFailed)
                      Text(
                        '⚠ Failed · tap to retry',
                        style: AppTypography.label(
                            size: 10.5, color: AppColors.destructive),
                      )
                    else ...[
                      Text(
                        entry.time,
                        style: AppTypography.label(
                            size: 10.5, color: AppColors.textFaint),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.done_rounded,
                          size: 13,
                          color: AppColors.textFaint,
                        ),
                      ],
                    ],
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

// ─── Text bubble context sheet ────────────────────────────────────────────────

class _TextBubbleContextSheet extends StatefulWidget {
  final _Entry entry;
  final String diaryId;
  final void Function(String msg) onShowBanner;

  const _TextBubbleContextSheet({
    required this.entry,
    required this.diaryId,
    required this.onShowBanner,
  });

  @override
  State<_TextBubbleContextSheet> createState() =>
      _TextBubbleContextSheetState();
}

class _TextBubbleContextSheetState extends State<_TextBubbleContextSheet> {
  bool _savingToMoments = false;
  bool _removingFromMoments = false;

  Future<void> _saveToMoments() async {
    setState(() => _savingToMoments = true);
    try {
      await EntriesApi.instance.saveToMoments(widget.diaryId, widget.entry.id);
      DiaryStore.instance.markSavedToMoments(widget.entry.id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onShowBanner('✨ Saved to Memory Tree');
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingToMoments = false);
    }
  }

  Future<void> _removeFromMoments() async {
    setState(() => _removingFromMoments = true);
    try {
      await EntriesApi.instance.removeFromMoments(widget.diaryId, widget.entry.id);
      DiaryStore.instance.markRemovedFromMoments(widget.entry.id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onShowBanner('Removed from Memory Tree');
    } catch (_) {
      if (!mounted) return;
      setState(() => _removingFromMoments = false);
    }
  }

  void _copy() {
    if (widget.entry.content == null) return;
    Clipboard.setData(ClipboardData(text: widget.entry.content!));
    Navigator.pop(context);
    widget.onShowBanner('Copied to clipboard');
  }

  void _delete() {
    Navigator.pop(context);
    DiaryStore.instance.removeEntry(widget.entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final alreadySaved = widget.entry.savedToMoments;

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
              Center(
                child: Container(
                  width: 38, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Save / remove from Moments
              if (!alreadySaved)
                _SheetRow(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: AppColors.emberWarm,
                  label: 'Save to Moments ✨',
                  trailing: _savingToMoments
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: AppColors.emberWarm,
                          ),
                        )
                      : null,
                  onTap: _savingToMoments ? null : _saveToMoments,
                ),
              if (alreadySaved)
                _SheetRow(
                  icon: Icons.auto_awesome_outlined,
                  iconColor: AppColors.textFaint,
                  label: 'Remove from Moments',
                  trailing: _removingFromMoments
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: AppColors.textFaint,
                          ),
                        )
                      : null,
                  onTap: _removingFromMoments ? null : _removeFromMoments,
                ),

              // Copy
              _SheetRow(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: _copy,
              ),

              // Delete (mine only)
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
                                    extra: {
                                      'isVideo': false,
                                      'targetDiaryId': widget.diaryId,
                                    },
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

  void _react(String emoji) async {
    Navigator.pop(context);
    HapticFeedback.lightImpact();
    try {
      final raw = await EntriesApi.instance
          .toggleReaction(widget.diaryId, widget.entry.id, emoji);
      DiaryStore.instance.updateEntryReactions(
        widget.entry.id,
        raw.map((k, v) => MapEntry(k, (v as List).cast<String>())),
      );
    } catch (_) {
      widget.onShowBanner("Couldn't react — try again");
    }
  }

  void _togglePin() async {
    Navigator.pop(context);
    final entry = DiaryStore.instance
        .entriesFor(widget.diaryId)
        .cast<DiaryEntry?>()
        .firstWhere((e) => e?.id == widget.entry.id, orElse: () => null);
    final next = !(entry?.isPinned ?? false);
    try {
      await EntriesApi.instance.setPinned(widget.diaryId, widget.entry.id, next);
      DiaryStore.instance.setEntryPinned(widget.entry.id, next);
      widget.onShowBanner(next ? '📌 Pinned' : 'Unpinned');
    } catch (_) {
      widget.onShowBanner("Couldn't pin — try again");
    }
  }

  void _editCaption() async {
    final entry = DiaryStore.instance
        .entriesFor(widget.diaryId)
        .cast<DiaryEntry?>()
        .firstWhere((e) => e?.id == widget.entry.id, orElse: () => null);
    final ctrl = TextEditingController(text: entry?.caption ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.modalSurface,
        title: Text('Caption', style: AppTypography.title(size: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 280,
          maxLines: 3,
          style: AppTypography.body(size: 14),
          decoration: const InputDecoration(
              hintText: 'Say something about this memory…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == null || !mounted) return;
    Navigator.pop(context);
    try {
      await EntriesApi.instance
          .setCaption(widget.diaryId, widget.entry.id, saved.isEmpty ? null : saved);
      DiaryStore.instance
          .updateEntryCaption(widget.entry.id, saved.isEmpty ? null : saved);
      widget.onShowBanner('Caption saved');
    } catch (_) {
      widget.onShowBanner("Couldn't save caption");
    }
  }

  void _forward() async {
    final others = DiaryStore.instance.diaries
        .where((d) => d.id != widget.diaryId && !d.isGroup)
        .toList();
    if (others.isEmpty) {
      Navigator.pop(context);
      widget.onShowBanner('No other diaries to forward to yet');
      return;
    }
    final target = await showModalBottomSheet<DiaryContact>(
      context: context,
      backgroundColor: AppColors.modalSurface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Forward to…', style: AppTypography.title(size: 18)),
            const SizedBox(height: 8),
            for (final d in others)
              ListTile(
                leading: CircleAvatar(child: Text(d.initial)),
                title:
                    Text(d.displayName, style: AppTypography.body(size: 15)),
                onTap: () => Navigator.pop(ctx, d),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    Navigator.pop(context);
    try {
      await EntriesApi.instance
          .forwardEntry(widget.diaryId, widget.entry.id, target.id);
      widget.onShowBanner('↪️ Forwarded to ${target.displayName}');
    } catch (_) {
      widget.onShowBanner("Couldn't forward — try again");
    }
  }

  void _deleteForMe() async {
    Navigator.pop(context);
    try {
      await EntriesApi.instance.deleteForMe(widget.diaryId, widget.entry.id);
      DiaryStore.instance.removeEntry(widget.entry.id);
      widget.onDelete?.call();
    } catch (_) {
      widget.onShowBanner("Couldn't delete — try again");
    }
  }

  void _delete() async {
    Navigator.pop(context);
    try {
      await EntriesApi.instance.deleteEntry(widget.diaryId, widget.entry.id);
      DiaryStore.instance.removeEntry(widget.entry.id);
      widget.onDelete?.call();
    } on DioException catch (e) {
      final code = (e.response?.data is Map)
          ? ((e.response!.data as Map)['error']?['code'] ??
              (e.response!.data as Map)['error'])
          : null;
      widget.onShowBanner(code.toString().contains('DELETE_WINDOW')
          ? 'Too late to delete for everyone — use "Delete for me"'
          : "Couldn't delete — try again");
    } catch (_) {
      widget.onShowBanner("Couldn't delete — try again");
    }
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

              // Emoji reactions — one per user, tap again to remove
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in const ['❤️', '😂', '😮', '😢', '🙏', '🔥'])
                      GestureDetector(
                        onTap: () => _react(e),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                  ],
                ),
              ),

              // Save / remove jar
              _SheetRow(
                icon: _isJarred ? Icons.star_rounded : Icons.star_outline_rounded,
                iconColor: AppColors.emberWarm,
                label: _isJarred ? '✓ Saved · Remove from Jar' : '✨ Save to Memory Jar',
                onTap: _toggleJar,
              ),

              // Pin / unpin
              _SheetRow(
                icon: Icons.push_pin_outlined,
                label: '📌 Pin in this diary',
                onTap: _togglePin,
              ),

              // Caption (author only — media itself is never editable)
              if (widget.entry.isMine)
                _SheetRow(
                  icon: Icons.notes_rounded,
                  label: '✍️ Add / edit caption',
                  onTap: _editCaption,
                ),

              // Forward to another diary
              _SheetRow(
                icon: Icons.forward_rounded,
                label: '↪️ Forward to another diary',
                onTap: _forward,
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

              // Delete for me — hides from this user only
              _SheetRow(
                icon: Icons.visibility_off_outlined,
                iconColor: AppColors.destructive,
                label: 'Delete for me',
                labelColor: AppColors.destructive,
                onTap: _deleteForMe,
              ),

              // Delete for everyone (author only, within the server window)
              if (widget.entry.isMine)
                _SheetRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: AppColors.destructive,
                  label: 'Delete for everyone',
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
  final String diaryId;
  final VoidCallback? onRetry;
  const _VideoBubble({required this.entry, required this.diaryId, this.onRetry});

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  bool _pressed = false;
  bool _loading = false; // while fetching signed URL

  Future<void> _openVideoPlayer() async {
    HapticFeedback.selectionClick();

    // Local file (just-recorded entry — path is immediately available).
    if (widget.entry.path.isNotEmpty) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _VideoPlayerPage(
          url: widget.entry.path,
          durationSeconds: widget.entry.durationSeconds,
        ),
      ));
      return;
    }

    // Remote entry: offline-first — cached file if present, else download
    // exactly once into the media cache and play from disk.
    setState(() => _loading = true);
    try {
      final url = await MediaCacheService.instance.resolve(
        diaryId: widget.diaryId,
        entryId: widget.entry.id,
        type: 'video',
      );
      if (!mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This video has expired and is no longer playable.')));
        return;
      }
      await Navigator.of(context).push<void>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _VideoPlayerPage(
          url: url,
          durationSeconds: widget.entry.durationSeconds,
        ),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load video. Please try again.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.entry.isMine;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.70),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.entry.isPending
              ? null
              : widget.entry.isFailed
                  ? widget.onRetry
                  : _openVideoPlayer,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
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
                    ? AppColors.violet
                        .withValues(alpha: _pressed ? 0.55 : 0.35)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19).copyWith(
                bottomRight: isMine
                    ? const Radius.circular(3)
                    : const Radius.circular(19),
                bottomLeft: isMine
                    ? const Radius.circular(19)
                    : const Radius.circular(3),
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
                                ? [
                                    const Color(0xFF5A2090),
                                    const Color(0xFF280A50)
                                  ]
                                : [
                                    const Color(0xFF1C0A35),
                                    const Color(0xFF0D0520)
                                  ],
                          ),
                        ),
                      ),
                      if (widget.entry.isPending || _loading)
                        const SizedBox(
                          width: 48, height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 26, height: 26,
                              child: CircularProgressIndicator(
                                  color: Colors.white54, strokeWidth: 2.5),
                            ),
                          ),
                        )
                      else
                        AnimatedScale(
                          scale: _pressed ? 0.88 : 1.0,
                          duration: AppMotion.fast,
                          child: Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.entry.isFailed
                                  ? AppColors.destructive
                                      .withValues(alpha: 0.35)
                                  : Colors.black.withValues(alpha: 0.45),
                              border: Border.all(
                                color: widget.entry.isFailed
                                    ? AppColors.destructive
                                        .withValues(alpha: 0.7)
                                    : Colors.white.withValues(alpha: 0.55),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              widget.entry.isFailed
                                  ? Icons.refresh_rounded
                                  : Icons.play_arrow_rounded,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 8,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.videocam_rounded,
                                  size: 11, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                widget.entry.duration,
                                style: AppTypography.caption(
                                    size: 10.5,
                                    weight: FontWeight.w700,
                                    color: Colors.white),
                              ),
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
                          Text(
                            widget.entry.transcript!,
                            style: AppTypography.serifItalic(
                                size: 13.5, color: AppColors.textMuted),
                          ),
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
                                      size: 10.5,
                                      color: AppColors.textFaint)),
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

// ─── Fullscreen video player ──────────────────────────────────────────────────

class _VideoPlayerPage extends StatefulWidget {
  final String url;
  final int durationSeconds;

  const _VideoPlayerPage({required this.url, required this.durationSeconds});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    if (widget.url.startsWith('http')) {
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    } else {
      _ctrl = VideoPlayerController.file(File(widget.url));
    }
    _ctrl.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      _ctrl.play();
      _scheduleHideControls();
    });
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _togglePlayPause() {
    HapticFeedback.selectionClick();
    if (_ctrl.value.isPlaying) {
      _ctrl.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      _ctrl.play();
      _scheduleHideControls();
    }
  }

  void _onTapOverlay() {
    setState(() => _showControls = !_showControls);
    if (_showControls && _ctrl.value.isPlaying) _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _ctrl.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video ──────────────────────────────────────────────────────────
          GestureDetector(
            onTap: _onTapOverlay,
            child: _initialized
                ? Center(
                    child: AspectRatio(
                      aspectRatio: _ctrl.value.aspectRatio,
                      child: VideoPlayer(_ctrl),
                    ),
                  )
                : const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white70, strokeWidth: 2)),
          ),

          // ── Buffering indicator ────────────────────────────────────────────
          if (_initialized && _ctrl.value.isBuffering)
            const Center(
              child: CircularProgressIndicator(
                  color: Colors.white54, strokeWidth: 2),
            ),

          // ── Controls overlay ───────────────────────────────────────────────
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Stack(
                children: [
                  // Top gradient
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      height: pad.top + 72,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Close button
                  Positioned(
                    top: pad.top + 4,
                    left: 8,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),

                  // Center play/pause
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlayPause,
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.5),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.65),
                              width: 1.5),
                        ),
                        child: Icon(
                          _initialized && _ctrl.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ),

                  // Bottom gradient + scrubber
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: EdgeInsets.only(
                        left: 16, right: 16,
                        top: 40,
                        bottom: pad.bottom + 20,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            _ctrl,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Color(0x33FFFFFF),
                              backgroundColor: Color(0x1AFFFFFF),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _initialized
                                    ? _fmtDuration(_ctrl.value.position)
                                    : '00:00',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontFamily: 'monospace'),
                              ),
                              Text(
                                _initialized
                                    ? _fmtDuration(_ctrl.value.duration)
                                    : _fmtDuration(Duration(
                                        seconds: widget.durationSeconds)),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
  final Future<void> Function(String) onSendText;

  const _BottomActionBar({
    super.key,
    required this.diaryId,
    required this.personName,
    required this.onRecord,
    required this.onPulse,
    required this.onSendText,
  });

  @override
  State<_BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends State<_BottomActionBar>
    with SingleTickerProviderStateMixin {
  bool _pillPressed = false;
  bool _breakBannerDismissed = false;
  bool _textMode = false;
  late final AnimationController _pulseBreath;
  final _textCtrl = TextEditingController();
  final _textFocus = FocusNode();

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
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  // Called from parent via GlobalKey when "Text message" is chosen in sheet.
  void enterTextMode() {
    setState(() => _textMode = true);
    _textFocus.requestFocus();
  }

  void _enterTextMode() => enterTextMode();

  void _exitTextMode() {
    _textCtrl.clear();
    _textFocus.unfocus();
    setState(() => _textMode = false);
  }

  Future<void> _submit() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    _textFocus.unfocus();
    setState(() => _textMode = false);
    await widget.onSendText(text);
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
              child: AnimatedSwitcher(
                duration: AppMotion.medium,
                child: _textMode
                    ? _TextComposeRow(
                        key: const ValueKey('text'),
                        controller: _textCtrl,
                        focusNode: _textFocus,
                        onCancel: _exitTextMode,
                        onSend: _submit,
                      )
                    : Row(
                        key: const ValueKey('buttons'),
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

                          // ② Voice compose pill — tap = picker, long-press = instant voice
                          Expanded(
                            child: GestureDetector(
                              onTapDown: (_) =>
                                  setState(() => _pillPressed = true),
                              onTapUp: (_) =>
                                  setState(() => _pillPressed = false),
                              onTapCancel: () =>
                                  setState(() => _pillPressed = false),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onRecord();
                              },
                              onLongPress: () {
                                HapticFeedback.mediumImpact();
                                context.push(AppRoutes.voiceRecord, extra: {
                                  'isVideo': false,
                                  'autoStart': true,
                                  'targetDiaryId': widget.diaryId,
                                });
                              },
                              child: AnimatedScale(
                                scale: _pillPressed ? 0.97 : 1.0,
                                duration: AppMotion.fast,
                                child: Container(
                                  height: 50,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(25),
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.ember.withValues(alpha: 0.09),
                                        Colors.white.withValues(alpha: 0.03),
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    border: Border.all(
                                      color: AppColors.emberWarm.withValues(alpha: 0.24),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.mic_none_rounded,
                                          size: 18,
                                          color: AppColors.emberWarm.withValues(alpha: 0.65)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: RichText(
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: 'Hold to record',
                                                style: AppTypography.label(
                                                    size: 12.5,
                                                    color: AppColors.textMuted),
                                              ),
                                              TextSpan(
                                                text: ' · Tap for more',
                                                style: AppTypography.label(
                                                    size: 12.5,
                                                    color: AppColors.textFaint),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          // ③ Text compose button
                          GestureDetector(
                            onTap: _enterTextMode,
                            child: Container(
                              width: 50, height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.06),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.09),
                                    width: 1.5),
                              ),
                              child: Icon(Icons.edit_rounded,
                                  size: 19, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
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
      label: widget.meSent ? 'Flicker sent' : 'Send flicker',
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

// ── Text compose row ──────────────────────────────────────────────────────────

class _TextComposeRow extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _TextComposeRow({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<_TextComposeRow> createState() => _TextComposeRowState();
}

class _TextComposeRowState extends State<_TextComposeRow> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Cancel button
        GestureDetector(
          onTap: widget.onCancel,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08), width: 1),
            ),
            child: Icon(Icons.close_rounded,
                size: 18, color: AppColors.textFaint),
          ),
        ),
        const SizedBox(width: 10),

        // Text field
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              maxLines: null,
              maxLength: 2000,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: AppTypography.body(size: 15),
              decoration: InputDecoration(
                hintText: 'Say something…',
                hintStyle: AppTypography.body(
                    size: 15, color: AppColors.textFaint),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                      color: AppColors.emberWarm.withValues(alpha: 0.40),
                      width: 1),
                ),
              ),
              onSubmitted: (_) => widget.onSend(),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Send button
        GestureDetector(
          onTap: _hasText ? widget.onSend : null,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _hasText ? AppColors.emberGradient : null,
              color: _hasText ? null : Colors.white.withValues(alpha: 0.06),
              border: _hasText
                  ? null
                  : Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 1),
              boxShadow: _hasText
                  ? [
                      BoxShadow(
                        color: AppColors.ember.withValues(alpha: 0.40),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Icon(
              Icons.send_rounded,
              size: 20,
              color: _hasText ? Colors.white : AppColors.textFaint,
            ),
          ),
        ),
      ],
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
  final VoidCallback onText;

  const _RecordSheet({
    required this.recipientName,
    required this.onVoice,
    required this.onVideo,
    required this.onText,
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
              const SizedBox(height: 10),
              _PickerTile(
                icon: Icons.chat_bubble_outline_rounded,
                color: const Color(0xFF4DAFEA),
                title: 'Text message', sub: 'Quick note · save to Moments later ✨',
                onTap: onText,
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

