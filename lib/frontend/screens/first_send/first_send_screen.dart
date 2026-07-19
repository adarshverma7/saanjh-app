import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/diary_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/glow_background.dart';

class FirstSendScreen extends StatefulWidget {
  const FirstSendScreen({super.key});

  @override
  State<FirstSendScreen> createState() => _FirstSendScreenState();
}

class _FirstSendScreenState extends State<FirstSendScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    HapticFeedback.mediumImpact();
    // Target the newest diary — without a targetDiaryId the recording is
    // silently discarded by RecordScreen.
    final diaries = DiaryStore.instance.diaries;
    context.push(AppRoutes.voiceRecord, extra: {
      'isVideo': false,
      if (diaries.isNotEmpty) 'targetDiaryId': diaries.first.id,
    });
  }

  Future<void> _skip() async {
    if (_sending) return;
    HapticFeedback.selectionClick();
    setState(() => _sending = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: GlowBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
              child: Column(
                children: [
                  const Spacer(),
                  _fade(0.0, child: _IconBlock()),
                  const SizedBox(height: 36),
                  _fade(0.15,
                    child: Text.rich(
                      TextSpan(
                        style: AppTypography.display(size: 38).copyWith(
                            height: 1.1, letterSpacing: -0.02 * 38),
                        children: [
                          const TextSpan(text: 'Send your\nfirst '),
                          TextSpan(
                            text: 'hello.',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: AppColors.emberBright,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    )),
                  const SizedBox(height: 18),
                  _fade(0.25,
                    child: Text(
                      'Just 20 seconds. Say whatever comes naturally — "thinking of you", "had a long day", or just hum a little.',
                      style: AppTypography.serifItalic(size: 18),
                      textAlign: TextAlign.center,
                    )),
                  const Spacer(),
                  _fade(0.40,
                    child: _TipsRow()),
                  const SizedBox(height: 36),
                  _fade(0.50, child: CtaPrimary(
                    label: '🎙  Record a voice note',
                    onPressed: _record,
                  )),
                  const SizedBox(height: 12),
                  _fade(0.58,
                    child: TextButton(
                      onPressed: _skip,
                      child: Text(
                        _sending ? 'Going to diaries…' : 'I\'ll do it later',
                        style: AppTypography.label(
                            size: 13.5, color: AppColors.textMuted),
                      ),
                    )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fade(double delay, {required Widget child}) {
    final interval = Interval(delay, (delay + 0.5).clamp(0.0, 1.0),
        curve: AppMotion.easeOut);
    final anim = CurvedAnimation(parent: _entranceCtrl, curve: interval);
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
            offset: Offset(0, 14 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }
}

class _IconBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.emberGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.ember.withValues(alpha: 0.5),
            blurRadius: 50,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 44),
    );
  }
}

class _TipsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tips = [
      (Icons.timer_outlined, '20 seconds'),
      (Icons.lock_outline_rounded, 'Private'),
      (Icons.auto_awesome_rounded, 'Auto-transcript'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: tips.map((t) {
        final (icon, label) = t;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.emberBright),
              const SizedBox(height: 5),
              Text(label,
                  style: AppTypography.label(
                      size: 11.5, color: AppColors.textMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
