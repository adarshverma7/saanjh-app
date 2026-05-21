import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/onboarding_background.dart';

class InviteRecipientScreen extends StatefulWidget {
  final String? prefillName;
  final String? prefillPhone;

  const InviteRecipientScreen({
    super.key,
    this.prefillName,
    this.prefillPhone,
  });

  @override
  State<InviteRecipientScreen> createState() => _InviteRecipientScreenState();
}

class _InviteRecipientScreenState extends State<InviteRecipientScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final String _inviteCode;
  String _relation = 'parent';
  bool _linkCopied = false;
  bool _sharing = false;

  static const _relations = [
    ('parent', '🌅', 'Parent'),
    ('sibling', '🌱', 'Sibling'),
    ('child', '👶', 'Child'),
    ('partner', '💛', 'Partner'),
    ('other', '✨', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _inviteCode = _generateCode();
  }

  static String _generateCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String get _inviteLink => 'https://saanjh.app/join/$_inviteCode';

  String get _shareMessage =>
      'Hey! I\'d love to share quiet moments with you on Saanjh 🌙\n\n'
      'Tap to join: $_inviteLink';

  Future<void> _share() async {
    if (_sharing) return;
    HapticFeedback.mediumImpact();
    setState(() => _sharing = true);
    await Share.share(_shareMessage);
    if (mounted) setState(() => _sharing = false);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _inviteLink));
    HapticFeedback.selectionClick();
    setState(() => _linkCopied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _linkCopied = false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: OnboardingBackground()),
          SafeArea(
            child: Column(
              children: [
                _TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad + 24),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fade(0.05,
                            child: Text('INVITE TO SAANJH',
                                style: AppTypography.eyebrow(
                                    size: 11, color: AppColors.emberBright))),
                        const SizedBox(height: 14),
                        _fade(
                          0.12,
                          child: Text.rich(
                            TextSpan(
                              style: AppTypography.title(
                                      size: 32, weight: FontWeight.w600)
                                  .copyWith(height: 1.15),
                              children: [
                                const TextSpan(text: 'Share your\n'),
                                TextSpan(
                                  text: 'invite link',
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.emberBright),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _fade(
                          0.18,
                          child: Text(
                            'Send it however you like — WhatsApp, iMessage, email, anywhere.',
                            style: AppTypography.body(
                                size: 14.5, color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Link card ──────────────────────────────────────
                        _fade(0.24, child: _LinkCard(
                          link: _inviteLink,
                          copied: _linkCopied,
                          onCopy: _copyLink,
                        )),
                        const SizedBox(height: 28),

                        // ── Relationship ───────────────────────────────────
                        _fade(0.30,
                            child: Text('RELATIONSHIP',
                                style: AppTypography.eyebrow(
                                    size: 10, color: AppColors.textFaint))),
                        const SizedBox(height: 10),
                        _fade(
                          0.30,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: _relations.map((r) {
                                final (id, emoji, label) = r;
                                final sel = id == _relation;
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _relation = id);
                                  },
                                  child: AnimatedContainer(
                                    duration: AppMotion.fast,
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? AppColors.ember
                                              .withValues(alpha: 0.14)
                                          : Colors.white
                                              .withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: sel
                                            ? AppColors.emberWarm
                                                .withValues(alpha: 0.45)
                                            : Colors.white
                                                .withValues(alpha: 0.08),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(emoji,
                                            style:
                                                const TextStyle(fontSize: 15)),
                                        const SizedBox(width: 6),
                                        Text(label,
                                            style: AppTypography.label(
                                              size: 13,
                                              weight: FontWeight.w500,
                                              color: sel
                                                  ? AppColors.emberBright
                                                  : AppColors.textMuted,
                                            )),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ── Share CTA ──────────────────────────────────────
                        _fade(0.38,
                            child: CtaPrimary(
                              label: 'Share invite  →',
                              loading: _sharing,
                              onPressed: _share,
                            )),
                        const SizedBox(height: 12),
                        _fade(
                          0.44,
                          child: Center(
                            child: TextButton(
                              onPressed: () => context.pop(),
                              child: Text('Cancel',
                                  style: AppTypography.label(
                                      size: 13,
                                      color: AppColors.textMuted)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fade(double delay, {required Widget child}) {
    final interval = Interval(delay, (delay + 0.5).clamp(0.0, 1.0),
        curve: AppMotion.easeOut);
    final anim = CurvedAnimation(parent: _ctrl, curve: interval);
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
            offset: Offset(0, 12 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }
}

// ── Link card ─────────────────────────────────────────────────────────────────

class _LinkCard extends StatelessWidget {
  final String link;
  final bool copied;
  final VoidCallback onCopy;

  const _LinkCard({
    required this.link,
    required this.copied,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.ember.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.emberWarm.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              link,
              style: AppTypography.label(
                size: 13,
                color: AppColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onCopy,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: copied
                    ? AppColors.ember.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: copied
                      ? AppColors.emberWarm.withValues(alpha: 0.40)
                      : Colors.white.withValues(alpha: 0.10),
                  width: 1,
                ),
              ),
              child: AnimatedSwitcher(
                duration: AppMotion.fast,
                child: Text(
                  copied ? 'Copied!' : 'Copy',
                  key: ValueKey(copied),
                  style: AppTypography.label(
                    size: 12,
                    weight: FontWeight.w600,
                    color: copied
                        ? AppColors.emberBright
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
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
                    color: Colors.white.withValues(alpha: 0.08), width: 1),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 16, color: Color(0x9EF5EFE8)),
            ),
          ),
        ],
      ),
    );
  }
}
