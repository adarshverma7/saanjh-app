import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../router/app_routes.dart';
import '../state/diary_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

class OnThisDayOverlay extends StatefulWidget {
  final DiaryEntry entry;
  final DiaryContact? contact;

  const OnThisDayOverlay({
    super.key,
    required this.entry,
    this.contact,
  });

  @override
  State<OnThisDayOverlay> createState() => _OnThisDayOverlayState();
}

class _OnThisDayOverlayState extends State<OnThisDayOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _driftCtrl;
  late final AnimationController _enterCtrl;

  @override
  void initState() {
    super.initState();
    // Slow drift for ambient particles (8 s — matches AppMotion.breatheSlow)
    _driftCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.breatheSlow,
    )..repeat(reverse: true);
    // Content entry fade + rise
    _enterCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    )..forward();
  }

  @override
  void dispose() {
    _driftCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  // ── Date label ─────────────────────────────────────────────────────────────

  String get _dateLabel {
    final now = DateTime.now();
    final d = widget.entry.createdAt;
    const months = [
      '',
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final monthDay = '${months[d.month]} ${d.day}';
    final years = now.year - d.year;
    if (years == 1) return '$monthDay, a year ago';
    return '$monthDay, $years years ago';
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasTranscript = widget.entry.transcript?.isNotEmpty == true;
    final contactName = widget.contact?.displayName;

    return GestureDetector(
      // Tap anywhere on the background to dismiss.
      onTap: () => Navigator.pop(context),
      child: Container(
        // Full-height sheet — rounded top like other overlays.
        height: MediaQuery.of(context).size.height * 0.94,
        decoration: const BoxDecoration(
          color: AppColors.inkDeep,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Stack(
          children: [
            // ── Amber particle drift ──────────────────────────────────────
            Positioned.fill(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _driftCtrl,
                    builder: (_, _) => CustomPaint(
                      painter:
                          _AmberParticlePainter(drift: _driftCtrl.value),
                    ),
                  ),
                ),
              ),
            ),

            // ── Content ───────────────────────────────────────────────────
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderSoft,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: AnimatedBuilder(
                      animation: _enterCtrl,
                      builder: (_, child) {
                        final t = Curves.easeOutCubic
                            .transform(_enterCtrl.value);
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 24 * (1 - t)),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(36, 0, 36, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(),

                            // "On this day…"
                            Text(
                              'On this day…',
                              style: AppTypography.display(size: 52),
                            ),

                            const SizedBox(height: 10),

                            // Date label
                            Text(
                              _dateLabel,
                              style: AppTypography.serifItalic(
                                size: 20,
                                color: AppColors.emberWarm,
                              ),
                            ),

                            if (contactName != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'with $contactName',
                                style: AppTypography.caption(
                                  size: 13,
                                  color: AppColors.textFaint,
                                ),
                              ),
                            ],

                            const SizedBox(height: 36),

                            // Pull-quote (transcript)
                            if (hasTranscript)
                              _PullQuote(
                                  text: widget.entry.transcript!),

                            const SizedBox(height: 32),

                            // Listen CTA
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                Navigator.pop(context);
                                context.push(AppRoutes.onThisDay);
                              },
                              child: _ListenButton(
                                hasTranscript: hasTranscript,
                              ),
                            ),

                            const Spacer(),

                            // Dismiss hint
                            Center(
                              child: Text(
                                'Tap anywhere to continue',
                                style: AppTypography.caption(
                                  color: AppColors.textFaint
                                      .withValues(alpha: 0.50),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pull-quote card ──────────────────────────────────────────────────────────

class _PullQuote extends StatelessWidget {
  final String text;
  const _PullQuote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.emberWarm.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“', // left double quotation mark
            style: AppTypography.display(size: 32).copyWith(
              color: AppColors.emberWarm.withValues(alpha: 0.45),
              height: 0.75,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.serifItalic(size: 17),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Listen button ────────────────────────────────────────────────────────────

class _ListenButton extends StatelessWidget {
  final bool hasTranscript;
  const _ListenButton({required this.hasTranscript});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.ember.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.emberWarm.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.ember.withValues(alpha: 0.22),
            ),
            child: const Icon(Icons.play_arrow_rounded,
                size: 18, color: AppColors.emberWarm),
          ),
          const SizedBox(width: 12),
          Text(
            hasTranscript ? 'Listen to this memory' : 'Open this memory',
            style: AppTypography.label(
              size: 14,
              weight: FontWeight.w600,
              color: AppColors.emberWarm,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_rounded,
              size: 14, color: AppColors.emberWarm.withValues(alpha: 0.70)),
        ],
      ),
    );
  }
}

// ─── Amber particle painter ───────────────────────────────────────────────────
// Reuses the winter-particles visual pattern from _TreePainter, adapted to
// amber colour and a slow upward drift driven by the 8s animation controller.

class _AmberParticlePainter extends CustomPainter {
  final double drift; // 0.0–1.0 from AnimationController.repeat(reverse:true)

  const _AmberParticlePainter({required this.drift});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42); // fixed seed → stable positions per session

    for (int i = 0; i < 32; i++) {
      final baseX   = rng.nextDouble() * size.width;
      final baseY   = rng.nextDouble() * size.height;
      final radius  = 0.8 + rng.nextDouble() * 2.2;
      final phase   = rng.nextDouble();

      // Sine horizontal sway + slow upward rise.
      final driftX = math.sin((drift + phase) * math.pi * 2) * 10;
      final rawY   = baseY - drift * size.height * 0.18 * (0.4 + phase * 0.6);
      // Wrap so particles re-enter from the bottom when they leave the top.
      final driftY = rawY % size.height;

      // Shimmer: alpha pulses gently with drift and per-particle phase.
      final alpha = (0.07 +
              rng.nextDouble() * 0.10 +
              0.04 * math.sin((drift + phase) * math.pi * 2))
          .clamp(0.04, 0.22);

      canvas.drawCircle(
        Offset(baseX + driftX, driftY),
        radius,
        Paint()
          ..color = AppColors.emberWarm.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_AmberParticlePainter old) => old.drift != drift;
}

