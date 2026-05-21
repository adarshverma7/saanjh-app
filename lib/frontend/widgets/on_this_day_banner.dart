import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_routes.dart';
import '../services/on_this_day_service.dart';
import '../state/diary_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

class OnThisDayBanner extends StatefulWidget {
  final DiaryEntry entry;
  const OnThisDayBanner({super.key, required this.entry});

  @override
  State<OnThisDayBanner> createState() => _OnThisDayBannerState();
}

class _OnThisDayBannerState extends State<OnThisDayBanner>
    with SingleTickerProviderStateMixin {
  bool _dismissed = false;
  bool _isPlaying = false;
  late final AnimationController _waveCtrl;

  static const _kDismissPrefix = 'on_this_day_dismissed_';

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _checkDismissed();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = '$_kDismissPrefix${now.year}-${now.month}-${now.day}';
    if (mounted && prefs.getBool(key) == true) {
      setState(() => _dismissed = true);
    }
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = '$_kDismissPrefix${now.year}-${now.month}-${now.day}';
    await prefs.setBool(key, true);
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final svc = OnThisDayService.instance;
    final yearsLabel = svc.yearLabel(widget.entry);
    final name = svc.contactName(widget.entry);

    return Column(mainAxisSize: MainAxisSize.min, children: [AnimatedSize(
      duration: AppMotion.page,
      curve: Curves.easeInOutCubic,
      child: _dismissed
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: GestureDetector(
                onTap: () => context.push(AppRoutes.onThisDay),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF3A2200), Color(0xFF1A0C00)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.25),
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 4px golden left accent
                        Container(
                          width: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFB800),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(14),
                              bottomLeft: Radius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ON THIS DAY · ${yearsLabel.toUpperCase()}',
                                  style: AppTypography.eyebrow(
                                    size: 10,
                                    color: const Color(0xFFFFB800),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$name said something to you.',
                                  style: AppTypography.serifItalic(
                                    size: 16,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _isPlaying
                                    ? _MiniWaveformPlayer(
                                        ctrl: _waveCtrl,
                                        onStop: () =>
                                            setState(() => _isPlaying = false),
                                      )
                                    : Row(
                                        children: [
                                          _PlayChip(
                                            onTap: () => setState(
                                                () => _isPlaying = true),
                                          ),
                                          const SizedBox(width: 10),
                                          GestureDetector(
                                            onTap: () => context
                                                .push(AppRoutes.onThisDay),
                                            child: Text(
                                              'View all →',
                                              style: AppTypography.label(
                                                size: 12,
                                                color: const Color(0xFFFFB800)
                                                    .withValues(alpha: 0.65),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ],
                            ),
                          ),
                        ),
                        // Dismiss ✕
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
                          child: GestureDetector(
                            onTap: _dismiss,
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Secondary: personal reflection from last year
          if (OnThisDayService.instance.todayPersonalReflection != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: GestureDetector(
                onTap: () => context.push(AppRoutes.personalJournal),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF120A28).withValues(alpha: 0.80),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF9B7FF5)
                            .withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded,
                          size: 13, color: Color(0xFF9B7FF5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'A year ago, you recorded a private reflection. → Listen',
                          style: AppTypography.label(
                              size: 12,
                              color: const Color(0xFF9B7FF5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    ]);
  }
}

// ── Play chip ─────────────────────────────────────────────────────────────────

class _PlayChip extends StatelessWidget {
  final VoidCallback onTap;
  const _PlayChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFB800).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFFFB800).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded,
                color: Color(0xFFFFB800), size: 14),
            const SizedBox(width: 4),
            Text(
              '▶ Play',
              style: AppTypography.label(
                  size: 12, color: const Color(0xFFFFB800)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mini inline waveform player ───────────────────────────────────────────────

class _MiniWaveformPlayer extends StatelessWidget {
  final AnimationController ctrl;
  final VoidCallback onStop;
  const _MiniWaveformPlayer({required this.ctrl, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, _) {
        return Row(
          children: [
            // Stop button
            GestureDetector(
              onTap: onStop,
              child: const Icon(Icons.stop_rounded,
                  color: Color(0xFFFFB800), size: 18),
            ),
            const SizedBox(width: 8),
            // Waveform bars
            ...List.generate(12, (i) {
              final phase = math.sin((ctrl.value + i * 0.18) * math.pi * 2);
              final h = (4 + phase.abs() * 18).clamp(3.0, 22.0);
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
