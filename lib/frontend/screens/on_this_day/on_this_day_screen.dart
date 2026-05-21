import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/on_this_day_service.dart';
import '../../state/diary_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class OnThisDayScreen extends StatefulWidget {
  const OnThisDayScreen({super.key});

  @override
  State<OnThisDayScreen> createState() => _OnThisDayScreenState();
}

class _OnThisDayScreenState extends State<OnThisDayScreen> {
  late DateTime _browsing;

  @override
  void initState() {
    super.initState();
    _browsing = DateTime.now();
  }

  void _prevDay() => setState(
      () => _browsing = _browsing.subtract(const Duration(days: 1)));

  void _nextDay() {
    final next = _browsing.add(const Duration(days: 1));
    if (next.isAfter(DateTime.now())) return;
    setState(() => _browsing = next);
  }

  bool get _isToday {
    final now = DateTime.now();
    return _browsing.month == now.month && _browsing.day == now.day;
  }

  String get _dateLabel {
    const months = [
      '',
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[_browsing.month]} ${_browsing.day}';
  }

  @override
  Widget build(BuildContext context) {
    final svc = OnThisDayService.instance;
    final entries = svc.matchesFor(_browsing.month, _browsing.day);

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(dateLabel: _isToday ? 'Today' : _dateLabel),
            const SizedBox(height: 16),
            _CalendarBrowse(
              label: _isToday ? 'Today · $_dateLabel' : _dateLabel,
              onPrev: _prevDay,
              onNext: _isToday ? null : _nextDay,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: entries.isEmpty
                  ? _EmptyState(dateLabel: _dateLabel)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _EntryTile(entry: entries[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String dateLabel;
  const _Header({required this.dateLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: AppColors.textMuted),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On This Day', style: AppTypography.title(size: 22)),
              Text(
                'Memories from past years',
                style: AppTypography.label(
                    size: 12, color: AppColors.textFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Calendar browse row ──────────────────────────────────────────────────────

class _CalendarBrowse extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _CalendarBrowse({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0C00),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFFFFB800).withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left_rounded,
                  color: Color(0xFFFFB800)),
              iconSize: 22,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.label(
                  size: 14, color: const Color(0xFFFFB800)),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: onNext,
              icon: Icon(
                Icons.chevron_right_rounded,
                color: onNext == null
                    ? AppColors.textFaint
                    : const Color(0xFFFFB800),
              ),
              iconSize: 22,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String dateLabel;
  const _EmptyState({required this.dateLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📅', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 16),
            Text(
              'Nothing from $dateLabel in past years.',
              style: AppTypography.serifItalic(size: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Keep sending voice notes and your memories will resurface here next year.',
              style: AppTypography.label(
                  size: 13, color: AppColors.textFaint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Entry tile ───────────────────────────────────────────────────────────────

class _EntryTile extends StatefulWidget {
  final DiaryEntry entry;
  const _EntryTile({required this.entry});

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile>
    with SingleTickerProviderStateMixin {
  bool _isPlaying = false;
  late final AnimationController _waveCtrl;

  String get _yearLabel =>
      OnThisDayService.instance.yearLabel(widget.entry);
  String get _contactName =>
      OnThisDayService.instance.contactName(widget.entry);

  String get _dateFormatted {
    final d = widget.entry.createdAt;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  Color get _avatarColor {
    try {
      return DiaryStore.instance.diaries
          .firstWhere((d) => d.id == widget.entry.diaryId)
          .avatarColor;
    } catch (_) {
      return AppColors.ember;
    }
  }

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF2A1800), Color(0xFF150C00)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFB800).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _avatarColor.withValues(alpha: 0.25),
                ),
                child: Center(
                  child: Text(
                    _contactName.isNotEmpty
                        ? _contactName[0].toUpperCase()
                        : '?',
                    style: AppTypography.label(
                        size: 14, color: _avatarColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _contactName,
                      style: AppTypography.label(
                          size: 14, color: AppColors.text),
                    ),
                    Text(
                      '$_dateFormatted · $_yearLabel',
                      style: AppTypography.label(
                        size: 11,
                        color: const Color(0xFFFFB800)
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.ember.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.entry.type == 'video' ? '🎬' : '🎙',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),

          if (widget.entry.transcript != null) ...[
            const SizedBox(height: 10),
            Text(
              '"${widget.entry.transcript}"',
              style: AppTypography.serifItalic(
                  size: 14, color: AppColors.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 12),

          _isPlaying
              ? _InlineWaveform(
                  ctrl: _waveCtrl,
                  onStop: () => setState(() => _isPlaying = false),
                )
              : GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isPlaying = true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFFFB800)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded,
                            color: Color(0xFFFFB800), size: 16),
                        const SizedBox(width: 5),
                        Text(
                          'Play memory',
                          style: AppTypography.label(
                              size: 12,
                              color: const Color(0xFFFFB800)),
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

// ─── Inline animated waveform (visual stub — audio wired when backend ready) ──

class _InlineWaveform extends StatelessWidget {
  final AnimationController ctrl;
  final VoidCallback onStop;
  const _InlineWaveform({required this.ctrl, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, _) {
        return Row(
          children: [
            GestureDetector(
              onTap: onStop,
              child: const Icon(Icons.stop_rounded,
                  color: Color(0xFFFFB800), size: 20),
            ),
            const SizedBox(width: 8),
            ...List.generate(14, (i) {
              final phase =
                  math.sin((ctrl.value + i * 0.16) * math.pi * 2);
              final h = (3.0 + phase.abs() * 18).clamp(3.0, 21.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 3,
                  height: h,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
