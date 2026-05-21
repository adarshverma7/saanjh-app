import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/diary_store.dart';
import '../../state/flicker_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';

enum _MsgType { voice, video, photo }

class _GroupEntry {
  final String id;
  final String sender;
  final String initial;
  final Color color;
  final bool isMine;
  final _MsgType type;
  final String content;      // transcript / caption
  final String duration;     // for voice/video
  final int durationSeconds; // for playback controller
  final String time;
  final bool seen;

  const _GroupEntry({
    required this.id,
    required this.sender,
    required this.initial,
    required this.color,
    required this.isMine,
    required this.type,
    required this.content,
    required this.duration,
    required this.durationSeconds,
    required this.time,
    required this.seen,
  });
}

final _entries = <_GroupEntry>[];

class GroupThreadScreen extends StatefulWidget {
  final String? diaryId;
  const GroupThreadScreen({super.key, this.diaryId});

  @override
  State<GroupThreadScreen> createState() => _GroupThreadScreenState();
}

class _GroupThreadScreenState extends State<GroupThreadScreen>
    with TickerProviderStateMixin {
  int? _playingIdx;
  AnimationController? _playCtrl;

  @override
  void dispose() {
    _playCtrl?.dispose();
    super.dispose();
  }

  void _togglePlay(int idx) {
    HapticFeedback.selectionClick();
    if (_playingIdx == idx) {
      _playCtrl?.stop();
      setState(() => _playingIdx = null);
      return;
    }
    _playCtrl?.stop();
    _playCtrl?.dispose();
    final entry = _entries[idx];
    _playCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: entry.durationSeconds),
    )..forward().whenComplete(() {
        if (mounted) setState(() => _playingIdx = null);
      });
    setState(() => _playingIdx = idx);
  }

  void _showRecordPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Send to the group',
                    style: AppTypography.title(size: 20)),
                const SizedBox(height: 6),
                Text('Everyone in Family Circle will see this.',
                    style: AppTypography.body(
                        size: 14, color: AppColors.textMuted)),
                const SizedBox(height: 18),
                _PickerTile(
                  icon: Icons.mic_rounded,
                  color: AppColors.emberWarm,
                  title: 'Voice note',
                  sub: 'Up to 20 seconds · auto-transcribed',
                  onTap: () {
                    Navigator.pop(context);
                    context.push(AppRoutes.voiceRecord,
                        extra: {'isVideo': false});
                  },
                ),
                const SizedBox(height: 10),
                _PickerTile(
                  icon: Icons.videocam_rounded,
                  color: AppColors.violet,
                  title: 'Video clip',
                  sub: 'Up to 20 seconds · saved in group Memory',
                  onTap: () {
                    Navigator.pop(context);
                    context.push(AppRoutes.voiceRecord,
                        extra: {'isVideo': true});
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMoreMenu() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              _MenuRow(
                icon: Icons.person_add_outlined,
                label: 'Add member',
                onTap: () {
                  Navigator.pop(context);
                  context.push(AppRoutes.discover);
                },
              ),
              _Divider(),
              _MenuRow(
                icon: Icons.park_rounded,
                label: 'Group Memory Tree',
                onTap: () {
                  Navigator.pop(context);
                  context.push(AppRoutes.memoryTree);
                },
              ),
              _Divider(),
              _MenuRow(
                icon: Icons.notifications_off_outlined,
                label: 'Mute group',
                onTap: () => Navigator.pop(context),
              ),
              _Divider(),
              _MenuRow(
                icon: Icons.exit_to_app_rounded,
                label: 'Leave group',
                color: AppColors.destructive,
                onTap: () {
                  Navigator.pop(context);
                  context.pop();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.inkRaised, AppColors.ink, AppColors.inkDeep],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Column(
            children: [
              _GroupHeader(
                onMore: _showMoreMenu,
                diaryId: widget.diaryId,
              ),
              // Group pulse row
              if (widget.diaryId != null)
                _GroupPulseRow(diaryId: widget.diaryId!),
              Expanded(
                child: _entries.isEmpty
                    ? _EmptyGroup()
                    : ListView(
                        padding:
                            const EdgeInsets.fromLTRB(14, 12, 14, 116),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          for (int i = 0; i < _entries.length; i++)
                            _buildEntry(i),
                        ],
                      ),
              ),
            ],
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _BottomBar(onRecord: _showRecordPicker),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(int i) {
    final e = _entries[i];
    switch (e.type) {
      case _MsgType.voice:
        return _VoiceBubble(
          entry: e,
          playing: _playingIdx == i,
          playCtrl: _playingIdx == i ? _playCtrl : null,
          onTap: () => _togglePlay(i),
        );
      case _MsgType.video:
        return _VideoBubble(entry: e);
      case _MsgType.photo:
        return _PhotoBubble(entry: e);
    }
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyGroup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 3 stacked abstract silhouettes
            SizedBox(
              width: 120,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 0, top: 10,
                    child: _Silhouette(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  Positioned(
                    right: 0, top: 10,
                    child: _Silhouette(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  Positioned(
                    top: 0,
                    child: _Silhouette(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Start the family diary.',
              style: AppTypography.title(size: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Who goes first?',
              style: AppTypography.serifItalic(size: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Silhouette extends StatelessWidget {
  final Color color;
  const _Silhouette({required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(height: 3),
        Container(
          width: 20, height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final VoidCallback onMore;
  final String? diaryId;
  const _GroupHeader({required this.onMore, this.diaryId});

  @override
  Widget build(BuildContext context) {
    // Resolve group diary — fall back to demo data if no diaryId.
    final group = diaryId != null
        ? DiaryStore.instance.diaries
            .cast<DiaryContact?>()
            .firstWhere((d) => d?.id == diaryId, orElse: () => null)
        : null;

    final members = group?.members ?? [];
    final memberCount = members.isEmpty ? 0 : members.length;
    final pulsedCount = members
        .where((m) => FlickerStore.instance.hasThemFlickeredToday(m.id))
        .length;
    final elderMemberId = group?.elderMemberId;

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.06), width: 1),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                context.pop();
              },
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 1),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 14, color: Color(0x9EF5EFE8)),
              ),
            ),
            const SizedBox(width: 12),

            // Stacked mini avatars from group members (max 3 + overflow)
            _MemberAvatarStack(
              members: members,
              elderMemberId: elderMemberId,
            ),

            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group?.displayName ?? 'Family Circle',
                      style: AppTypography.body(
                          size: 16, weight: FontWeight.w600)),
                  Row(
                    children: [
                      if (pulsedCount > 0) ...[
                        Container(
                          width: 7, height: 7,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.successGreen),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$pulsedCount here today',
                          style: AppTypography.label(
                              size: 11.5,
                              color: const Color(0xFF7CD992)),
                        ),
                        const SizedBox(width: 6),
                        Text('·',
                            style: AppTypography.label(
                                size: 11, color: AppColors.textFaint)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        memberCount > 0
                            ? '$memberCount members'
                            : 'Group',
                        style: AppTypography.label(
                            size: 11.5, color: AppColors.textFaint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => context.push(AppRoutes.memoryTree),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
                ),
                child: const Icon(Icons.park_outlined, size: 16, color: AppColors.emberBright),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onMore,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
                ),
                child: Icon(Icons.more_vert_rounded, size: 18, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String initial;
  final Color color;
  const _MiniAvatar(this.initial, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24, height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: Center(
        child: Text(initial,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

// ─── Member avatar stack ──────────────────────────────────────────────────────

class _MemberAvatarStack extends StatelessWidget {
  final List<DiaryContact> members;
  final String? elderMemberId;
  const _MemberAvatarStack(
      {required this.members, this.elderMemberId});

  @override
  Widget build(BuildContext context) {
    const maxShown = 3;
    final shown = members.take(maxShown).toList();
    final overflow = members.length - maxShown;

    if (shown.isEmpty) {
      // Fallback for groups with no members populated yet
      return SizedBox(
        width: 44, height: 40,
        child: Stack(
          children: [
            Positioned(left: 0, top: 0, child: _MiniAvatar('P', AppColors.ember)),
            Positioned(left: 14, top: 0, child: _MiniAvatar('M', const Color(0xFFFF6B8A))),
            Positioned(left: 7, top: 12, child: _MiniAvatar('K', AppColors.successGreen)),
          ],
        ),
      );
    }

    return SizedBox(
      width: 14.0 * shown.length + 10 + (overflow > 0 ? 20 : 0),
      height: 30,
      child: Stack(
        children: [
          ...shown.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            final isElder = m.id == elderMemberId;
            return Positioned(
              left: i * 14.0,
              top: 0,
              child: Stack(
                children: [
                  _MiniAvatar(m.initial, m.avatarColor),
                  if (isElder)
                    const Positioned(
                      right: 0, top: 0,
                      child: Text('👑', style: TextStyle(fontSize: 8)),
                    ),
                ],
              ),
            );
          }),
          if (overflow > 0)
            Positioned(
              left: shown.length * 14.0,
              top: 0,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.inkRaised,
                  border: Border.all(color: AppColors.ink, width: 1.5),
                ),
                child: Center(
                  child: Text('+$overflow',
                      style: const TextStyle(fontSize: 8, color: Colors.white60)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Group pulse row ──────────────────────────────────────────────────────────

class _GroupPulseRow extends StatelessWidget {
  final String diaryId;
  const _GroupPulseRow({required this.diaryId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [DiaryStore.instance, FlickerStore.instance]),
      builder: (_, _) {
        final group = DiaryStore.instance.diaries
            .cast<DiaryContact?>()
            .firstWhere((d) => d?.id == diaryId, orElse: () => null);
        if (group == null || group.members.isEmpty) {
          return const SizedBox.shrink();
        }

        final members = group.members;
        final pulsedCount = members
            .where((m) => FlickerStore.instance.hasThemFlickeredToday(m.id))
            .length;

        return GestureDetector(
          onTap: () => context.push(AppRoutes.flicker, extra: {
            'targetDiaryId': diaryId,
          }),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.04), width: 1),
              ),
            ),
            child: Row(
              children: [
                ...members.map((m) {
                  final pulsed =
                      FlickerStore.instance.hasThemFlickeredToday(m.id);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            m.avatarColor,
                            m.avatarColor.withValues(alpha: 0.65),
                          ],
                        ),
                        border: pulsed
                            ? Border.all(
                                color: AppColors.emberWarm
                                    .withValues(alpha: 0.75),
                                width: 2)
                            : Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Center(
                        child: Text(m.initial,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                Text(
                  '$pulsedCount/${members.length} here today',
                  style: AppTypography.label(
                      size: 11,
                      color: pulsedCount > 0
                          ? const Color(0xFF7CD992)
                          : AppColors.textFaint),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Bubble wrapper (avatar + name + content) ─────────────────────────────────

class _BubbleRow extends StatelessWidget {
  final _GroupEntry entry;
  final Widget bubble;

  const _BubbleRow({required this.entry, required this.bubble});

  @override
  Widget build(BuildContext context) {
    if (entry.isMine) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(child: bubble),
            const SizedBox(width: 8),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [entry.color, entry.color.withValues(alpha: 0.7)],
                ),
              ),
              child: Center(
                child: Text(entry.initial,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [entry.color, entry.color.withValues(alpha: 0.7)],
              ),
            ),
            child: Center(
              child: Text(entry.initial,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 4),
                  child: Text(entry.sender,
                      style: AppTypography.label(
                          size: 12, weight: FontWeight.w600, color: entry.color)),
                ),
                bubble,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Voice bubble ─────────────────────────────────────────────────────────────

class _VoiceBubble extends StatelessWidget {
  final _GroupEntry entry;
  final bool playing;
  final AnimationController? playCtrl;
  final VoidCallback onTap;

  const _VoiceBubble({
    required this.entry,
    required this.playing,
    required this.playCtrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = entry.isMine;
    final bubbleColor = isMine
        ? AppColors.ember.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.05);
    final borderColor = isMine
        ? AppColors.emberWarm.withValues(alpha: 0.28)
        : Colors.white.withValues(alpha: 0.08);

    final bubble = GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.70),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(18),
            bottomLeft: isMine ? const Radius.circular(18) : const Radius.circular(4),
          ),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Play/Pause
                AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: playing
                        ? AppColors.emberWarm
                        : isMine
                            ? AppColors.ember.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.08),
                    boxShadow: playing
                        ? [BoxShadow(color: AppColors.ember.withValues(alpha: 0.4),
                            blurRadius: 14, offset: const Offset(0, 4))]
                        : null,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 20,
                    color: playing
                        ? Colors.white
                        : isMine ? AppColors.emberBright : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120, height: 26,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _WavePainter(
                            color: (isMine ? AppColors.emberWarm : AppColors.textMuted)
                                .withValues(alpha: 0.35),
                            seed: entry.id.hashCode,
                          ),
                        ),
                      ),
                      if (playing && playCtrl != null)
                        AnimatedBuilder(
                          animation: playCtrl!,
                          builder: (_, w) => ClipRect(
                            clipper: _ProgressClipper(playCtrl!.value),
                            child: CustomPaint(
                              size: const Size(120, 26),
                              painter: _WavePainter(
                                color: isMine ? AppColors.emberWarm : AppColors.text,
                                seed: entry.id.hashCode,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: playCtrl ?? const AlwaysStoppedAnimation(0),
              builder: (_, w) {
                final elapsed = playing && playCtrl != null
                    ? (playCtrl!.value * entry.durationSeconds).floor()
                    : 0;
                return Text(
                  playing
                      ? '0:${elapsed.toString().padLeft(2, '0')} / ${entry.duration}'
                      : entry.duration,
                  style: AppTypography.label(
                      size: 10.5,
                      color: isMine ? AppColors.emberBright : AppColors.textFaint),
                );
              },
            ),
            if (entry.content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.content,
                  style: AppTypography.serifItalic(size: 13.5, color: AppColors.textMuted)),
            ],
            const SizedBox(height: 4),
            _Timestamp(entry: entry),
          ],
        ),
      ),
    );

    return _BubbleRow(entry: entry, bubble: bubble);
  }
}

// ─── Video bubble ─────────────────────────────────────────────────────────────

class _VideoBubble extends StatefulWidget {
  final _GroupEntry entry;
  const _VideoBubble({required this.entry});

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isMine = widget.entry.isMine;

    final bubble = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playing video…',
                style: AppTypography.label(size: 13, color: Colors.white)),
            backgroundColor: AppColors.modalSurface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.70),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(18),
              bottomLeft: isMine ? const Radius.circular(18) : const Radius.circular(4),
            ),
            border: Border.all(
              color: isMine
                  ? AppColors.violet.withValues(alpha: _pressed ? 0.5 : 0.32)
                  : Colors.white.withValues(alpha: 0.09),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17).copyWith(
              bottomRight: isMine ? const Radius.circular(3) : const Radius.circular(17),
              bottomLeft: isMine ? const Radius.circular(17) : const Radius.circular(3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isMine
                              ? [const Color(0xFF6B2FA0), const Color(0xFF3A0F70)]
                              : [const Color(0xFF1C0A35), const Color(0xFF0D0520)],
                        ),
                      ),
                    ),
                    AnimatedScale(
                      scale: _pressed ? 0.88 : 1.0,
                      duration: AppMotion.fast,
                      child: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            size: 26, color: Colors.white),
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
                                style: AppTypography.label(
                                    size: 10.5, weight: FontWeight.w700,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Caption
                Container(
                  color: isMine
                      ? AppColors.violet.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.035),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.entry.content.isNotEmpty)
                        Text(widget.entry.content,
                            style: AppTypography.serifItalic(
                                size: 13.5, color: AppColors.textMuted)),
                      const SizedBox(height: 4),
                      _Timestamp(entry: widget.entry),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return _BubbleRow(entry: widget.entry, bubble: bubble);
  }
}

// ─── Photo bubble ─────────────────────────────────────────────────────────────

class _PhotoBubble extends StatelessWidget {
  final _GroupEntry entry;
  const _PhotoBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isMine = entry.isMine;
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18).copyWith(
          bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(18),
          bottomLeft: isMine ? const Radius.circular(18) : const Radius.circular(4),
        ),
        child: Column(
          children: [
            Container(
              height: 130,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0A3A2A), Color(0xFF0D5040)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Icon(Icons.photo_rounded, size: 36, color: AppColors.successGreen),
              ),
            ),
            Container(
              color: Colors.white.withValues(alpha: 0.04),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.content.isNotEmpty)
                    Text(entry.content,
                        style: AppTypography.serifItalic(
                            size: 13.5, color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  _Timestamp(entry: entry),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return _BubbleRow(entry: entry, bubble: bubble);
  }
}

// ─── Timestamp row ────────────────────────────────────────────────────────────

class _Timestamp extends StatelessWidget {
  final _GroupEntry entry;
  const _Timestamp({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(entry.time,
            style: AppTypography.caption(size: 10, color: AppColors.textFaint)),
        if (entry.isMine) ...[
          const SizedBox(width: 4),
          Icon(
            entry.seen ? Icons.done_all_rounded : Icons.done_rounded,
            size: 12,
            color: entry.seen ? AppColors.emberWarm : AppColors.textFaint,
          ),
        ],
      ],
    );
  }
}

// ─── Waveform & progress ──────────────────────────────────────────────────────

class _WavePainter extends CustomPainter {
  final Color color;
  final int seed;
  _WavePainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const n = 20;
    final step = size.width / n;
    for (int i = 0; i < n; i++) {
      final h = size.height * (0.25 + 0.65 * rng.nextDouble());
      final x = i * step + step / 2;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.color != color || o.seed != seed;
}

class _ProgressClipper extends CustomClipper<Rect> {
  final double progress;
  _ProgressClipper(this.progress);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * progress, size.height);

  @override
  bool shouldReclip(_ProgressClipper o) => o.progress != progress;
}

// ─── Bottom bar ───────────────────────────────────────────────────────────────

class _BottomBar extends StatefulWidget {
  final VoidCallback onRecord;
  const _BottomBar({required this.onRecord});

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.ink.withValues(alpha: 0),
            AppColors.ink.withValues(alpha: 0.97),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: widget.onRecord,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mic_none_rounded, size: 18, color: AppColors.textFaint),
                    const SizedBox(width: 10),
                    Text('Voice or video for the group…',
                        style: AppTypography.label(size: 13, color: AppColors.textFaint)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.onRecord,
            child: AnimatedScale(
              scale: _pressed ? 0.93 : 1.0,
              duration: AppMotion.fast,
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.emberGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ember.withValues(alpha: 0.5),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Picker tile ──────────────────────────────────────────────────────────────

class _PickerTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.onTap,
  });

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
          color: _pressed
              ? widget.color.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _pressed
                ? widget.color.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.14),
              ),
              child: Icon(widget.icon, size: 22, color: widget.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                  Text(widget.sub,
                      style: AppTypography.label(size: 12, color: AppColors.textMuted)),
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

// ─── Menu helpers ─────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 14),
            Text(label, style: AppTypography.body(size: 15, color: c)),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
      height: 1, indent: 54, color: Colors.white.withValues(alpha: 0.05));
}

