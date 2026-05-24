import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../router/app_routes.dart';
import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/onboarding_background.dart';

/// Invite sender screen — shown from ConnectFirst "Invite someone" or from
/// Discover when inviting a contact not yet on Saanjh.
class InviteScreen extends StatefulWidget {
  final String? prefillName;
  final String? prefillPhone;

  const InviteScreen({
    super.key,
    this.prefillName,
    this.prefillPhone,
  });

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _launchingWa = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _nameCtrl = TextEditingController(text: widget.prefillName ?? '');
    _phoneCtrl = TextEditingController(text: widget.prefillPhone ?? '');
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  bool get _hasName => _nameCtrl.text.trim().isNotEmpty;
  bool get _canSend =>
      _nameCtrl.text.trim().isNotEmpty &&
      _phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length >= 7;

  String get _senderName {
    final n = UserStore.instance.name;
    return n.isEmpty ? 'Someone' : n;
  }

  String get _shareMessage =>
      '$_senderName wants to share a voice diary with you on Saanjh.\n'
      'Download it here → https://saanjh.app/invite\n'
      'Your diary together starts the moment you join.';

  String get _whatsAppMessage =>
      '$_senderName ne tumhe Saanjh pe invite kiya hai. '
      'Yahan click karo: https://saanjh.app/invite';

  String get _whatsAppPhone {
    final raw = _phoneCtrl.text.replaceAll(RegExp(r'[^\d+]'), '');
    // If user typed number without country code, assume +91.
    if (raw.startsWith('+')) return raw;
    if (raw.startsWith('91') && raw.length > 10) return '+$raw';
    return '+91$raw';
  }

  Future<void> _shareViaSystem() async {
    HapticFeedback.mediumImpact();
    await Share.share(_shareMessage);
  }

  Future<void> _sendViaWhatsApp() async {
    if (_launchingWa || !_canSend) return;
    HapticFeedback.mediumImpact();
    setState(() => _launchingWa = true);

    final encoded = Uri.encodeComponent(_whatsAppMessage);
    final url = Uri.parse('https://wa.me/$_whatsAppPhone?text=$encoded');

    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('WhatsApp not found. Message copied to clipboard.'),
        ));
        await Clipboard.setData(ClipboardData(text: _whatsAppMessage));
      }
    } catch (_) {
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: _whatsAppMessage));
      }
    }

    if (mounted) setState(() => _launchingWa = false);
  }

  Future<void> _activateSimpleMode() async {
    HapticFeedback.mediumImpact();
    await UserStore.instance.setSimpleMode(true);
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  void _showSimpleModeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SetupForThemSheet(onActivate: _activateSimpleMode),
    );
  }

  Widget _fade(double delay, Widget child) {
    final anim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(delay, (delay + 0.5).clamp(0.0, 1.0),
          curve: AppMotion.easeOut),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: OnboardingBackground()),
          SafeArea(
            child: Column(
              children: [
                _TopBar(onClose: () {
                  HapticFeedback.selectionClick();
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.home);
                  }
                }),
                Expanded(
                  child: _buildStandardBody(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Invite body ──────────────────────────────────────────────────────────

  Widget _buildStandardBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fade(
            0.04,
            Text('INVITE TO SAANJH',
                style: AppTypography.eyebrow(
                    size: 11, color: AppColors.emberBright)),
          ),
          const SizedBox(height: 14),
          _fade(
            0.10,
            Text(
              'Invite someone\nyou love',
              style: AppTypography.title(size: 34, weight: FontWeight.w600)
                  .copyWith(fontStyle: FontStyle.italic, height: 1.1),
            ),
          ),
          const SizedBox(height: 10),
          _fade(
            0.16,
            Text(
              'Choose WhatsApp, SMS, email, or any app — '
              'your phone handles the rest.',
              style: AppTypography.body(size: 14.5, color: AppColors.textMuted),
            ),
          ),
          const Spacer(),
          _fade(
            0.30,
            _SetupForThemCard(onTap: _showSimpleModeSheet),
          ),
          const SizedBox(height: 20),
          _fade(
            0.38,
            CtaPrimary(
              label: 'Share link  →',
              onPressed: _shareViaSystem,
            ),
          ),
          const SizedBox(height: 12),
          _fade(
            0.44,
            Center(
              child: TextButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.home);
                  }
                },
                child: Text('Cancel',
                    style: AppTypography.label(
                        size: 13, color: AppColors.textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step header ──────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final String step;
  final String label;
  const _StepHeader({required this.step, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.ember.withValues(alpha: 0.18),
            border: Border.all(
                color: AppColors.emberWarm.withValues(alpha: 0.35), width: 1),
          ),
          child: Center(
            child: Text(step,
                style: AppTypography.label(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.emberWarm)),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: AppTypography.eyebrow(
                size: 10, color: AppColors.textFaint)),
      ],
    );
  }
}

// ─── WhatsApp button ──────────────────────────────────────────────────────────

class _WhatsAppButton extends StatefulWidget {
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  const _WhatsAppButton(
      {required this.loading, required this.enabled, required this.onTap});

  @override
  State<_WhatsAppButton> createState() => _WhatsAppButtonState();
}

class _WhatsAppButtonState extends State<_WhatsAppButton> {
  bool _pressed = false;

  static const _waGreen = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !widget.loading;
    return GestureDetector(
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: active
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: active
              ? (_pressed
                  ? _waGreen.withValues(alpha: 0.85)
                  : _waGreen.withValues(alpha: 0.15))
              : AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? _waGreen.withValues(alpha: _pressed ? 0.9 : 0.45)
                : Colors.white.withValues(alpha: 0.06),
            width: 1.5,
          ),
        ),
        child: widget.loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _waGreen),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_rounded,
                      size: 20,
                      color: active ? _waGreen : AppColors.textFaint),
                  const SizedBox(width: 10),
                  Text(
                    'Send on WhatsApp  →',
                    style: AppTypography.label(
                      size: 15,
                      weight: FontWeight.w600,
                      color: active ? _waGreen : AppColors.textFaint,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Setup for them card ──────────────────────────────────────────────────────

class _SetupForThemCard extends StatefulWidget {
  final VoidCallback onTap;
  const _SetupForThemCard({required this.onTap});

  @override
  State<_SetupForThemCard> createState() => _SetupForThemCardState();
}

class _SetupForThemCardState extends State<_SetupForThemCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _pressed
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ember.withValues(alpha: 0.10),
                border: Border.all(
                    color: AppColors.emberWarm.withValues(alpha: 0.22),
                    width: 1),
              ),
              child: const Icon(Icons.phone_android_rounded,
                  size: 20, color: AppColors.emberWarm),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Have their phone nearby?',
                    style: AppTypography.body(
                        size: 14.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Switch this device to simple mode — '
                    'a simpler home screen just for them.',
                    style: AppTypography.caption(
                        size: 12.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

// ─── Setup for them sheet ─────────────────────────────────────────────────────

class _SetupForThemSheet extends StatefulWidget {
  final Future<void> Function() onActivate;
  const _SetupForThemSheet({required this.onActivate});

  @override
  State<_SetupForThemSheet> createState() => _SetupForThemSheetState();
}

class _SetupForThemSheetState extends State<_SetupForThemSheet> {
  bool _activating = false;

  Future<void> _activate() async {
    if (_activating) return;
    setState(() => _activating = true);
    await widget.onActivate();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottom + 24),
      decoration: BoxDecoration(
        color: const Color(0xFF130A10),
        borderRadius: BorderRadius.circular(28),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.ember.withValues(alpha: 0.12),
              border: Border.all(
                  color: AppColors.emberWarm.withValues(alpha: 0.28), width: 1),
            ),
            child: const Icon(Icons.phone_android_rounded,
                size: 28, color: AppColors.emberWarm),
          ),
          const SizedBox(height: 18),

          Text(
            'Setting up for them',
            style: AppTypography.title(size: 22, weight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'This switches the app to simple mode — a simpler home screen '
            'with just one play button and one record button. '
            'They can exit it anytime from Settings.',
            style: AppTypography.body(size: 14, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Steps
          _BulletRow(
            icon: Icons.play_circle_outline_rounded,
            text: 'One big "Listen" button',
          ),
          const SizedBox(height: 8),
          _BulletRow(
            icon: Icons.mic_none_rounded,
            text: 'One big "Record" button',
          ),
          const SizedBox(height: 8),
          _BulletRow(
            icon: Icons.hide_source_rounded,
            text: 'Everything else hidden',
          ),
          const SizedBox(height: 28),

          // Activate button
          GestureDetector(
            onTap: _activate,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.ember, AppColors.emberBright],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: _activating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.text),
                      )
                    : Text(
                        'Switch to simple mode',
                        style: AppTypography.label(
                            size: 15,
                            weight: FontWeight.w600,
                            color: AppColors.text),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: AppTypography.label(
                    size: 13, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BulletRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.emberWarm),
        const SizedBox(width: 10),
        Text(text,
            style:
                AppTypography.body(size: 13.5, color: AppColors.textMuted)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final VoidCallback onClose;
  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.eyebrow(size: 10, color: AppColors.textFaint),
      );
}

class _InviteField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;

  const _InviteField({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: AppTypography.body(size: 15),
      cursorColor: AppColors.emberWarm,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.body(size: 15, color: AppColors.textFaint),
        filled: true,
        fillColor: AppColors.surfaceTint,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: AppColors.borderSoft, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.emberWarm, width: 1.5),
        ),
      ),
    );
  }
}
