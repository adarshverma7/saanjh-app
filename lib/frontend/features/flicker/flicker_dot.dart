import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/diary_store.dart';
import '../../state/flicker_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// The 11px ambient dot that silently indicates a received flicker.
///
/// Design rules (from the concept spec):
///  • Received pulse → amber dot, opacity decaying through the day
///  • No pulse received → faint circular depression (15% opacity) if we've
///    previously received one, invisible otherwise
///  • 30-day streak → slightly brighter
///  • 60-day streak → subtle orbit ring
///  • 90-day streak → 2px outer halo ring, no label
///  • Tap → inline tooltip showing time only, auto-dismiss after 2.5s
class FlickerDot extends StatefulWidget {
  final String diaryId;
  final String personName;

  const FlickerDot({
    super.key,
    required this.diaryId,
    required this.personName,
  });

  @override
  State<FlickerDot> createState() => _FlickerDotState();
}

class _FlickerDotState extends State<FlickerDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitCtrl;
  bool _showTooltip = false;

  @override
  void initState() {
    super.initState();
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    final received = FlickerStore.instance.receivedToday(widget.diaryId);
    if (received == null) return;
    setState(() => _showTooltip = true);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showTooltip = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FlickerStore.instance,
      builder: (_, w) {
        final store = FlickerStore.instance;
        final received = store.receivedToday(widget.diaryId);
        final streakDays = DiaryStore.instance.streakDays(widget.diaryId);
        final opacity = store.dotOpacity(widget.diaryId);

        return GestureDetector(
          onTap: _onTap,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Outer halo — 90-day streak
              if (streakDays >= 90)
                Container(
                  width: 19, height: 19,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.emberWarm.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                ),

              // 60-day orbit ring (tiny animated arc)
              if (streakDays >= 60 && streakDays < 90)
                AnimatedBuilder(
                  animation: _orbitCtrl,
                  builder: (_, w) => CustomPaint(
                    size: const Size(22, 22),
                    painter: _OrbitPainter(
                      progress: _orbitCtrl.value,
                      color: AppColors.emberWarm.withValues(alpha: 0.50),
                    ),
                  ),
                ),

              // Core dot
              Container(
                width: 11, height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: received != null
                      ? AppColors.emberWarm.withValues(alpha: opacity)
                      : Colors.white.withValues(alpha: 0.12),
                  // 30+ day streak: brighter glow
                  boxShadow: received != null && streakDays >= 30
                      ? [
                          BoxShadow(
                            color: AppColors.emberWarm.withValues(alpha: 0.50),
                            blurRadius: 6,
                          )
                        ]
                      : null,
                ),
              ),

              // Tooltip (time only — nothing else)
              if (_showTooltip && received != null)
                Positioned(
                  bottom: 18,
                  child: _Tooltip(
                    name: widget.personName,
                    time: received.timeLabel,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final double progress;
  final Color color;
  _OrbitPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final dot = Offset(
      center.dx + radius * math.cos(progress * 2 * math.pi),
      center.dy + radius * math.sin(progress * 2 * math.pi),
    );
    canvas.drawCircle(dot, 1.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OrbitPainter o) => o.progress != progress;
}

class _Tooltip extends StatelessWidget {
  final String name;
  final String time;
  const _Tooltip({required this.name, required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xF0130A10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.emberWarm.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 14, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        '$name · $time',
        style: AppTypography.label(size: 12, color: AppColors.emberBright),
      ),
    );
  }
}

