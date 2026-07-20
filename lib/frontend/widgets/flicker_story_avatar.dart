import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// How long the user must hold to send a Flicker.
const Duration kFlickerHoldDuration = Duration(seconds: 3);

/// Story ring state — completely independent of Flicker.
/// Viewing a story only ever changes this; it never sends a Flicker and never
/// shows a heart.
enum StoryRingState {
  none,     // no active story
  unseen,   // new story  → orange ring
  seen,     // already viewed → subtle grey ring
}

/// Flicker relationship state — mirrors the backend's canonical current_state.
/// Only a Flicker ever produces a green ring or a heart badge.
enum FlickerRingState {
  none,
  iSent,     // I flickered them
  theySent,  // they flickered me
  mutual,    // both — double heart + premium glow
}

/// Avatar circle used in the Flicker/Stories strip.
///
/// Two independent rings, deliberately never conflated:
///   • inner ring  = story    (orange unseen / grey seen / absent)
///   • outer ring  = flicker  (green glow + heart badge, double for mutual)
///
/// Gestures:
///   • tap            → open the story (view only — never sends a Flicker)
///   • hold 3 seconds → send a Flicker, with a circular progress sweep and
///                      haptics; releasing early cancels with no side effect
class FlickerStoryAvatar extends StatefulWidget {
  final String initial;
  final Color avatarColor;
  final String? avatarUrl;
  final String label;
  final StoryRingState storyState;
  final FlickerRingState flickerState;
  final VoidCallback? onTap;
  final VoidCallback? onFlicker;

  const FlickerStoryAvatar({
    super.key,
    required this.initial,
    required this.avatarColor,
    required this.label,
    this.avatarUrl,
    this.storyState = StoryRingState.none,
    this.flickerState = FlickerRingState.none,
    this.onTap,
    this.onFlicker,
  });

  @override
  State<FlickerStoryAvatar> createState() => _FlickerStoryAvatarState();
}

class _FlickerStoryAvatarState extends State<FlickerStoryAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: kFlickerHoldDuration,
  );

  // Slow breathing glow shown while a Flicker is active.
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool _fired = false;
  int _lastHapticStep = 0;

  @override
  void initState() {
    super.initState();
    _hold.addListener(_onHoldTick);
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed) _fire();
    });
    if (widget.flickerState != FlickerRingState.none) _glow.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant FlickerStoryAvatar old) {
    super.didUpdateWidget(old);
    final active = widget.flickerState != FlickerRingState.none;
    if (active && !_glow.isAnimating) {
      _glow.repeat(reverse: true);
    } else if (!active && _glow.isAnimating) {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    _glow.dispose();
    super.dispose();
  }

  // ── Hold-to-flicker ────────────────────────────────────────────────────────

  void _onHoldTick() {
    // Escalating ticks as the ring fills — the hold should feel like it's
    // building toward something.
    final step = (_hold.value * 3).floor();
    if (step != _lastHapticStep && step > 0) {
      _lastHapticStep = step;
      HapticFeedback.selectionClick();
    }
    setState(() {});
  }

  void _startHold() {
    if (widget.onFlicker == null) return;
    _fired = false;
    _lastHapticStep = 0;
    HapticFeedback.lightImpact();
    _hold.forward(from: 0);
  }

  void _cancelHold() {
    if (_fired) return; // already sent — nothing to cancel
    if (_hold.isAnimating || _hold.value > 0) {
      _hold.reverse();
      _hold.value = 0;
    }
    setState(() {});
  }

  void _fire() {
    _fired = true;
    HapticFeedback.heavyImpact();
    widget.onFlicker?.call();
    _hold.value = 0;
    setState(() {});
  }

  // ── Colours ────────────────────────────────────────────────────────────────

  Color? get _storyRingColor => switch (widget.storyState) {
        StoryRingState.unseen => AppColors.emberWarm,
        StoryRingState.seen => Colors.white.withValues(alpha: 0.22),
        StoryRingState.none => null,
      };

  bool get _hasFlicker => widget.flickerState != FlickerRingState.none;

  @override
  Widget build(BuildContext context) {
    final holding = _hold.value > 0;

    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: GestureDetector(
        // Tap opens the story. It must never send a Flicker.
        onTap: widget.onTap,
        onLongPressDown: (_) => _startHold(),
        onLongPressCancel: _cancelHold,
        onLongPressUp: _cancelHold,
        onLongPressEnd: (_) => _cancelHold(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Outer flicker ring + hold progress sweep
                  AnimatedBuilder(
                    animation: _glow,
                    builder: (_, _) => CustomPaint(
                      size: const Size(56, 56),
                      painter: _RingPainter(
                        flickerColor: _hasFlicker ? AppColors.successGreen : null,
                        glow: _hasFlicker ? _glow.value : 0,
                        isMutual: widget.flickerState == FlickerRingState.mutual,
                        holdProgress: _hold.value,
                      ),
                    ),
                  ),

                  // Inner circle: avatar + story ring
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: widget.avatarUrl == null
                          ? LinearGradient(
                              colors: [
                                widget.avatarColor,
                                widget.avatarColor.withValues(alpha: 0.68),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      image: widget.avatarUrl != null
                          ? DecorationImage(
                              image: NetworkImage(widget.avatarUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      border: _storyRingColor != null
                          ? Border.all(color: _storyRingColor!, width: 2)
                          : null,
                    ),
                    child: widget.avatarUrl != null
                        ? null
                        : Center(
                            child: Text(
                              widget.initial,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),

                  // Heart badge — ONLY ever means Flicker, never a story view.
                  if (_hasFlicker && !holding)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: _HeartBadge(
                        isMutual: widget.flickerState == FlickerRingState.mutual,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: widget.storyState == StoryRingState.unseen
                    ? AppColors.emberBright
                    : Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green heart for a Flicker; two overlapping hearts once it's mutual.
class _HeartBadge extends StatelessWidget {
  final bool isMutual;
  const _HeartBadge({required this.isMutual});

  @override
  Widget build(BuildContext context) {
    if (!isMutual) return const _SingleHeart();
    return SizedBox(
      width: 26,
      height: 17,
      child: Stack(
        clipBehavior: Clip.none,
        children: const [
          Positioned(left: 0, child: _SingleHeart()),
          Positioned(left: 9, child: _SingleHeart()),
        ],
      ),
    );
  }
}

class _SingleHeart extends StatelessWidget {
  const _SingleHeart();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.successGreen,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.successGreen.withValues(alpha: 0.5),
            blurRadius: 6,
          ),
        ],
      ),
      child: const Icon(Icons.favorite_rounded, size: 9, color: Colors.white),
    );
  }
}

/// Draws the outer Flicker ring (with breathing glow) and, while the user is
/// holding, the progress sweep that fills over three seconds.
class _RingPainter extends CustomPainter {
  final Color? flickerColor;
  final double glow;
  final bool isMutual;
  final double holdProgress;

  _RingPainter({
    required this.flickerColor,
    required this.glow,
    required this.isMutual,
    required this.holdProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (flickerColor != null) {
      // Mutual gets a wider, brighter ring — the "premium" state.
      final width = isMutual ? 3.0 : 2.2;
      final alpha = (isMutual ? 0.85 : 0.7) + glow * 0.15;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = flickerColor!.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );

      // Outer bloom
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 3
          ..color = flickerColor!
              .withValues(alpha: (0.18 + glow * 0.22).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isMutual ? 7 : 5),
      );
    }

    if (holdProgress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * holdProgress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = AppColors.successGreen,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.flickerColor != flickerColor ||
      old.glow != glow ||
      old.isMutual != isMutual ||
      old.holdProgress != holdProgress;
}
