import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../router/app_routes.dart';
import '../../state/diary_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';

class AnniversaryScreen extends StatefulWidget {
  final String diaryId;
  final String contactName;
  final int years;

  const AnniversaryScreen({
    super.key,
    required this.diaryId,
    required this.contactName,
    required this.years,
  });

  @override
  State<AnniversaryScreen> createState() => _AnniversaryScreenState();
}

class _AnniversaryScreenState extends State<AnniversaryScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breatheCtrl;
  late final AnimationController _enterCtrl;
  late final AnimationController _burstCtrl;

  AudioPlayer? _player;
  bool _audioPlaying = false;

  // Stats computed once from DiaryStore
  late final int _voiceCount;
  late final int _videoCount;
  late final int _seasonCount;

  @override
  void initState() {
    super.initState();

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _enterCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.xSlow,
    )..forward();

    _burstCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.hero,
    )..forward();

    // Haptic celebration
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 200),
        () => HapticFeedback.mediumImpact());

    // Compute stats
    final entries = DiaryStore.instance.entriesFor(widget.diaryId);
    _voiceCount  = entries.where((e) => e.type == 'voice').length;
    _videoCount  = entries.where((e) => e.type == 'video').length;
    _seasonCount = _countSeasons(entries);

    // Auto-play the oldest entry (the first memory ever recorded)
    _tryAutoPlay(entries);
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _enterCtrl.dispose();
    _burstCtrl.dispose();
    _player?.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  int _countSeasons(List<DiaryEntry> entries) {
    final seen = <String>{};
    for (final e in entries) {
      final month = e.createdAt.month;
      final season = month >= 3 && month <= 5 ? 'spring'
          : month >= 6 && month <= 8 ? 'summer'
          : month >= 9 && month <= 11 ? 'autumn'
          : 'winter';
      seen.add('${e.createdAt.year}-$season');
    }
    return seen.length;
  }

  String get _yearLabel => switch (widget.years) {
        1 => 'One year',
        2 => 'Two years',
        3 => 'Three years',
        4 => 'Four years',
        5 => 'Five years',
        _ => '${widget.years} years',
      };

  String get _statsLine {
    final parts = <String>[];
    if (_voiceCount > 0) parts.add('$_voiceCount voice');
    if (_videoCount > 0) parts.add('$_videoCount video');
    if (_seasonCount > 0) {
      parts.add('$_seasonCount ${_seasonCount == 1 ? 'season' : 'seasons'} together');
    }
    return parts.join(' · ');
  }

  Future<void> _tryAutoPlay(List<DiaryEntry> entries) async {
    if (entries.isEmpty) return;
    final oldest = entries.reduce(
        (a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);
    if (oldest.path.isEmpty) return;
    try {
      final player = AudioPlayer();
      _player = player;
      await player.setFilePath(oldest.path);
      await player.setVolume(0.6); // ambient — quieter than full playback
      await player.play();
      player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _audioPlaying = false);
        }
      });
      if (mounted) setState(() => _audioPlaying = true);
    } catch (_) {
      // No audio file — screen still works without ambient audio.
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final firstName = widget.contactName.split(' ').first;

    return Scaffold(
      backgroundColor: AppColors.inkDeep,
      body: Stack(
        children: [
          // Confetti burst
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _burstCtrl,
              builder: (_, _) => CustomPaint(
                painter: _AnniversaryBurstPainter(progress: _burstCtrl.value),
              ),
            ),
          ),

          // Ambient ember glow
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _breatheCtrl,
              builder: (_, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.1),
                    radius: 0.85,
                    colors: [
                      AppColors.emberWarm.withValues(
                          alpha: 0.05 + _breatheCtrl.value * 0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: AnimatedBuilder(
              animation: _enterCtrl,
              builder: (_, child) {
                final t = Curves.easeOutCubic.transform(_enterCtrl.value);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 32 * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
                child: Column(
                  children: [
                    // Close
                    Align(
                      alignment: Alignment.topLeft,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.pop();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                                width: 1),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0x9EF5EFE8)),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Year number — ember gradient via ShaderMask
                    AnimatedBuilder(
                      animation: _breatheCtrl,
                      builder: (_, child) => Transform.scale(
                        scale: 1.0 + 0.06 * _breatheCtrl.value,
                        child: child,
                      ),
                      child: ShaderMask(
                        shaderCallback: (bounds) =>
                            AppColors.emberGradient.createShader(bounds),
                        blendMode: BlendMode.srcIn,
                        child: Text(
                          '${widget.years}',
                          style: AppTypography.display(size: 96).copyWith(
                            color: Colors.white, // colour overridden by shader
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Headline
                    Text(
                      '$_yearLabel with $firstName.',
                      style: AppTypography.serifItalic(size: 26)
                          .copyWith(color: AppColors.text),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Stats
                    if (_statsLine.isNotEmpty)
                      Text(
                        _statsLine,
                        style: AppTypography.caption(
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),

                    // Ambient audio indicator
                    if (_audioPlaying) ...[
                      const SizedBox(height: 20),
                      _AmbientWave(ctrl: _breatheCtrl),
                    ],

                    const SizedBox(height: 48),

                    // Primary CTA — tree (emotionally correct)
                    _AnniCta(
                      label: 'See your tree →',
                      isEmber: true,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.pop();
                        context.push(
                          AppRoutes.memoryTree,
                          extra: {'diaryId': widget.diaryId},
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Secondary — self-purchase (soft)
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        context.pop();
                        context.push(
                          AppRoutes.memoryBook,
                          extra: {'diaryId': widget.diaryId},
                        );
                      },
                      child: Text(
                        'Turn it into a Memory Book →',
                        style: AppTypography.label(
                          size: 13,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ),
                    // Gift option — even softer
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        context.pop();
                        context.push(
                          AppRoutes.memoryBook,
                          extra: {
                            'diaryId': widget.diaryId,
                            'isGift': true,
                          },
                        );
                      },
                      child: Text(
                        '🎁  Gift them this moment as a book →',
                        style: AppTypography.label(
                          size: 12.5,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ember CTA button ─────────────────────────────────────────────────────────

class _AnniCta extends StatefulWidget {
  final String label;
  final bool isEmber;
  final VoidCallback onTap;
  const _AnniCta({required this.label, required this.isEmber, required this.onTap});

  @override
  State<_AnniCta> createState() => _AnniCtaState();
}

class _AnniCtaState extends State<_AnniCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppMotion.fast,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: widget.isEmber ? AppColors.emberGradient : null,
            color: widget.isEmber
                ? null
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.isEmber
                ? [
                    BoxShadow(
                      color: AppColors.ember.withValues(alpha: 0.40),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              widget.label,
              style: AppTypography.button(
                  color: widget.isEmber ? Colors.white : AppColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Ambient wave indicator (shows audio is playing) ─────────────────────────

class _AmbientWave extends StatelessWidget {
  final AnimationController ctrl;
  const _AmbientWave({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.music_note_rounded,
              size: 11,
              color: AppColors.textFaint.withValues(alpha: 0.50)),
          const SizedBox(width: 6),
          ...List.generate(5, (i) {
            final phase = math.sin((ctrl.value + i * 0.18) * math.pi * 2);
            final h = (3.0 + phase.abs() * 10).clamp(3.0, 13.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 2.5,
                height: h,
                decoration: BoxDecoration(
                  color: AppColors.emberWarm
                      .withValues(alpha: 0.35 + 0.20 * phase.abs()),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
          const SizedBox(width: 6),
          Text('First memory playing',
              style: AppTypography.caption(
                  color: AppColors.textFaint.withValues(alpha: 0.50))),
        ],
      ),
    );
  }
}

// ─── Confetti burst painter ───────────────────────────────────────────────────

class _AnniversaryBurstPainter extends CustomPainter {
  final double progress; // 0→1

  const _AnniversaryBurstPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final rng = math.Random(42);
    final cx = size.width / 2;
    final cy = size.height * 0.40;
    final fade = (1 - progress).clamp(0.0, 1.0);
    final expand = progress * size.height * 0.55;

    const colours = [
      AppColors.ember,
      AppColors.emberWarm,
      AppColors.emberBright,
      Color(0xFFFFD60A), // gold
      Color(0xFF30D158), // green
    ];

    for (int i = 0; i < 32; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final dist = expand * (0.5 + rng.nextDouble() * 0.5);
      final x = cx + math.cos(angle) * dist;
      final y = cy + math.sin(angle) * dist * 0.65; // slightly oval burst
      final r = (2.0 + rng.nextDouble() * 3.5) * fade;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = colours[i % colours.length].withValues(alpha: fade * 0.70),
      );
    }
  }

  @override
  bool shouldRepaint(_AnniversaryBurstPainter old) =>
      old.progress != progress;
}
