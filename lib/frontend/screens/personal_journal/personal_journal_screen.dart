import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/personal_reflection_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';

class PersonalJournalScreen extends StatefulWidget {
  const PersonalJournalScreen({super.key});

  @override
  State<PersonalJournalScreen> createState() => _PersonalJournalScreenState();
}

class _PersonalJournalScreenState extends State<PersonalJournalScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;
  String? _playingId;

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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0820),
      floatingActionButton: _RecordFab(
        onTap: () {
          HapticFeedback.lightImpact();
          context.push(AppRoutes.voiceRecord, extra: {
            'isVideo': false,
            'isPrivateReflection': true,
          });
        },
      ),
      body: ListenableBuilder(
        listenable: PersonalReflectionStore.instance,
        builder: (_, _) {
          final reflections = PersonalReflectionStore.instance.all;
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            size: 20, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.lock_rounded,
                          size: 16, color: Color(0xFF9B7FF5)),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('My Journal · Private',
                              style: AppTypography.title(size: 22)),
                          Text(
                            'Only visible to you',
                            style: AppTypography.label(
                                size: 12, color: AppColors.textFaint),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: reflections.isEmpty
                      ? _EmptyState()
                      : ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(20, 4, 20, 32),
                          itemCount: reflections.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = reflections[i];
                            final isPlaying = _playingId == r.id;
                            return _ReflectionTile(
                              reflection: r,
                              isPlaying: isPlaying,
                              waveCtrl: _waveCtrl,
                              onPlay: () => setState(() {
                                _playingId = isPlaying ? null : r.id;
                              }),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded,
                size: 40, color: Color(0xFF9B7FF5)),
            const SizedBox(height: 16),
            Text(
              'Your journal is empty.',
              style: AppTypography.title(size: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Private voice notes you record will appear here.\nOnly you can hear them.',
              style: AppTypography.serifItalic(size: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reflection tile ──────────────────────────────────────────────────────────

class _ReflectionTile extends StatelessWidget {
  final PersonalReflection reflection;
  final bool isPlaying;
  final AnimationController waveCtrl;
  final VoidCallback onPlay;

  const _ReflectionTile({
    required this.reflection,
    required this.isPlaying,
    required this.waveCtrl,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF120A28).withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF9B7FF5).withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          // Lock badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF9B7FF5).withValues(alpha: 0.15),
            ),
            child: const Center(
              child: Icon(Icons.lock_rounded,
                  size: 16, color: Color(0xFF9B7FF5)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reflection.dateLabel,
                  style: AppTypography.label(
                      size: 13, color: AppColors.text),
                ),
                if (reflection.prompt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '"${reflection.prompt}"',
                    style: AppTypography.serifItalic(
                        size: 12, color: AppColors.textFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else
                  Text(
                    'Voice note',
                    style: AppTypography.label(
                        size: 11, color: AppColors.textFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Play button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onPlay();
            },
            child: isPlaying
                ? AnimatedBuilder(
                    animation: waveCtrl,
                    builder: (_, _) => _MiniWave(ctrl: waveCtrl),
                  )
                : Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          const Color(0xFF9B7FF5).withValues(alpha: 0.18),
                      border: Border.all(
                          color: const Color(0xFF9B7FF5)
                              .withValues(alpha: 0.40)),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        size: 18, color: Color(0xFF9B7FF5)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniWave extends StatelessWidget {
  final AnimationController ctrl;
  const _MiniWave({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36, height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(5, (i) {
          final phase = math.sin((ctrl.value + i * 0.2) * math.pi * 2);
          final h = (3.0 + phase.abs() * 14).clamp(3.0, 17.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Container(
              width: 3, height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF9B7FF5).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Record FAB ───────────────────────────────────────────────────────────────

class _RecordFab extends StatefulWidget {
  final VoidCallback onTap;
  const _RecordFab({required this.onTap});

  @override
  State<_RecordFab> createState() => _RecordFabState();
}

class _RecordFabState extends State<_RecordFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: AppMotion.fast,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: AppColors.emberGradient,
            borderRadius: BorderRadius.circular(26),
            boxShadow: AppShadows.emberGlow(
                intensity: 0.45, offset: const Offset(0, 6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text('Record',
                  style: AppTypography.button(color: Colors.white, size: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
