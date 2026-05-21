import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';

class MemoryDetailScreen extends StatefulWidget {
  const MemoryDetailScreen({super.key});

  @override
  State<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends State<MemoryDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _playing = false;
  late final AnimationController _playCtrl;

  @override
  void initState() {
    super.initState();
    _playCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  @override
  void dispose() {
    _playCtrl.dispose();
    super.dispose();
  }

  void _togglePlay() {
    HapticFeedback.lightImpact();
    setState(() => _playing = !_playing);
    if (_playing) {
      _playCtrl.forward();
    } else {
      _playCtrl.stop();
    }
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
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.pop();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.05),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 1),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0x9EF5EFE8)),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => HapticFeedback.selectionClick(),
                        child: const Icon(Icons.share_rounded,
                            size: 20, color: Color(0x9EF5EFE8)),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DateTag(),
                      const SizedBox(height: 24),
                      _AudioPlayer(
                        playing: _playing,
                        progress: _playCtrl,
                        onToggle: _togglePlay,
                      ),
                      const SizedBox(height: 28),
                      _TranscriptCard(),
                      const SizedBox(height: 28),
                      _MetaRow(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ON THIS DAY',
            style: AppTypography.eyebrow(
                size: 10, color: AppColors.emberBright)),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: AppTypography.title(size: 32, weight: FontWeight.w600)
                .copyWith(height: 1.1),
            children: [
              const TextSpan(text: 'A voice note\nfrom '),
              TextSpan(
                text: 'Papa.',
                style: TextStyle(
                    fontStyle: FontStyle.italic, color: AppColors.emberBright),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('16 May 2025 · 2 years ago',
            style: AppTypography.label(size: 12.5, color: AppColors.textFaint)),
      ],
    );
  }
}

class _AudioPlayer extends StatelessWidget {
  final bool playing;
  final AnimationController progress;
  final VoidCallback onToggle;

  const _AudioPlayer({
    required this.playing,
    required this.progress,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ember.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: AppColors.emberWarm.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: playing
                        ? const LinearGradient(
                            colors: [AppColors.emberWarm, AppColors.ember])
                        : null,
                    color: playing
                        ? null
                        : AppColors.ember.withValues(alpha: 0.2),
                    boxShadow: playing
                        ? [
                            BoxShadow(
                              color: AppColors.ember.withValues(alpha: 0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 30,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Voice note',
                        style: AppTypography.body(
                            size: 14, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    AnimatedBuilder(
                      animation: progress,
                      builder: (_, w) {
                        final elapsed =
                            (progress.value * 18).floor();
                        return Text(
                          '0:${elapsed.toString().padLeft(2, '0')} / 0:18',
                          style: AppTypography.label(
                              size: 12, color: AppColors.textMuted),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: progress,
            builder: (_, w) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.value,
                  backgroundColor:
                      Colors.white.withValues(alpha: 0.10),
                  valueColor: const AlwaysStoppedAnimation(AppColors.emberWarm),
                  minHeight: 3,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRANSCRIPT',
              style: AppTypography.eyebrow(
                  size: 9.5, color: AppColors.textFaint)),
          const SizedBox(height: 12),
          Text(
            '"Beta, aaj bahut yaad aaya tera. Khana khaya? Apna khayal rakhna. Hum sab theek hain. Papa ka pyaar."',
            style: AppTypography.serifItalic(size: 17, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MetaChip(icon: Icons.mic_rounded, label: '0:18'),
        const SizedBox(width: 10),
        _MetaChip(icon: Icons.calendar_today_rounded, label: '16 May 2025'),
        const SizedBox(width: 10),
        _MetaChip(icon: Icons.person_rounded, label: 'Papa'),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textFaint),
          const SizedBox(width: 5),
          Text(label,
              style:
                  AppTypography.caption(size: 11.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
