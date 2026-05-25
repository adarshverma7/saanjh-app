import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/cta.dart';
import '../../widgets/saanjh_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  const SettingsScreen({super.key, this.isEmbedded = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifVoiceNotes = true;
  bool _notifReminders = true;
  bool _notifOnThisDay = true;
  String _language = 'English';
  String _parentLanguage = 'हिंदी';
  bool _pulseTapMode = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _pulseTapMode = prefs.getBool('pulse_tap_mode') ?? false);
      }
    });
  }

  void _editProfile() {
    HapticFeedback.selectionClick();
    context.push(AppRoutes.profile);
  }

  void _signOut() async {
    HapticFeedback.selectionClick();
    final confirmed = await SaanjhDialog.showDestructive(
      context,
      title: 'Sign out?',
      body: 'You can sign back in anytime with your phone number.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed || !mounted) return;
    HapticFeedback.mediumImpact();
    await UserStore.instance.logout();
    if (!mounted) return;
    context.go(AppRoutes.splash);
  }

  void _showNotifications() {
    HapticFeedback.selectionClick();
    _showSheet(
      title: 'Notifications',
      child: StatefulBuilder(
        builder: (_, set) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetToggle(
              label: 'New voice notes',
              sub: 'When someone sends you a voice note',
              value: _notifVoiceNotes,
              onChanged: (v) {
                set(() => _notifVoiceNotes = v);
                setState(() => _notifVoiceNotes = v);
              },
            ),
            _SheetDivider(),
            _SheetToggle(
              label: 'Occasion reminders',
              sub: 'Record reminders before birthdays & festivals',
              value: _notifReminders,
              onChanged: (v) {
                set(() => _notifReminders = v);
                setState(() => _notifReminders = v);
              },
            ),
            _SheetDivider(),
            _SheetToggle(
              label: 'On This Day',
              sub: 'Surface memories from exactly 1 year ago',
              value: _notifOnThisDay,
              onChanged: (v) {
                set(() => _notifOnThisDay = v);
                setState(() => _notifOnThisDay = v);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLanguage() {
    HapticFeedback.selectionClick();
    _showSheet(
      title: 'Language',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetLabel('YOUR APP'),
          for (final lang in ['English', 'हिंदी', 'తెలుగు', 'தமிழ்', 'ਪੰਜਾਬੀ'])
            _SheetOption(
              label: lang,
              selected: _language == lang,
              onTap: () {
                setState(() => _language = lang);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 12),
          _SheetLabel("PARENT'S APP"),
          for (final lang in ['हिंदी', 'English', 'ಕನ್ನಡ', 'मराठी'])
            _SheetOption(
              label: lang,
              selected: _parentLanguage == lang,
              onTap: () {
                setState(() => _parentLanguage = lang);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showPrivacy() {
    HapticFeedback.selectionClick();
    _showSheet(
      title: 'Privacy',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetInfoTile(
            icon: Icons.contacts_rounded,
            label: 'Contact matching',
            sub: 'Encrypted phone hashes — we never store your contacts.',
            color: AppColors.successGreen,
          ),
          _SheetDivider(),
          _SheetInfoTile(
            icon: Icons.mic_none_rounded,
            label: 'Voice notes',
            sub: 'Stored end-to-end encrypted. Only you and your diary partner can hear them.',
            color: AppColors.emberWarm,
          ),
          _SheetDivider(),
          _SheetInfoTile(
            icon: Icons.location_off_rounded,
            label: 'No location tracking',
            sub: 'Saanjh never accesses your GPS. Presence uses only device signals.',
            color: AppColors.azure,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showPhoneNumber() {
    HapticFeedback.selectionClick();
    _showSheet(
      title: 'Phone number',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(0, 8, 0, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_rounded,
                    size: 20, color: AppColors.emberWarm),
                const SizedBox(width: 12),
                Text('+91 98765 43210',
                    style: AppTypography.body(
                        size: 16, weight: FontWeight.w600)),
              ],
            ),
          ),
          Text(
            'To change your number, sign out and sign in again with the new number. Your diaries will transfer automatically.',
            style:
                AppTypography.body(size: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showGift() {
    HapticFeedback.selectionClick();
    _showSheet(
      title: 'Invite to Saanjh',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saanjh is free.', style: AppTypography.title(size: 22)),
                const SizedBox(height: 6),
                Text('No ads · No subscription · No catch.',
                    style: AppTypography.label(
                        size: 13, color: AppColors.emberBright)),
                const SizedBox(height: 14),
                Text(
                  'Share the app with someone you love. They sign up in under a minute — no credit card, no trial, no friction.',
                  style: AppTypography.body(
                      size: 14, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CtaPrimary(
            label: 'Copy invite link',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Invite link copied!',
                      style: AppTypography.label(
                          size: 13, color: Colors.white)),
                  backgroundColor: AppColors.modalSurface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          CtaGhost(
            label: 'Share via WhatsApp',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showAbout() {
    HapticFeedback.selectionClick();
    _showSheet(
      title: 'About Saanjh',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: AppColors.emberGradient,
                ),
                child: const Icon(Icons.wb_twilight_rounded,
                    size: 28, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saanjh',
                      style: AppTypography.title(size: 22)),
                  Text('Version 1.0.0 (build 1)',
                      style: AppTypography.label(
                          size: 12.5, color: AppColors.textFaint)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Saanjh (सांझ — "dusk") is a living diary between the people who love each other most.\n\nBuilt for Indian families where words go unspoken and calls go unanswered.',
            style: AppTypography.serifItalic(size: 16),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showTerms() {
    HapticFeedback.selectionClick();
    _showSheet(
      title: 'Terms & Privacy',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Terms of Service',
              style: AppTypography.body(
                  size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'By using Saanjh you agree to use it to connect with family and friends — not for commercial or harmful purposes. We may remove content that violates these terms.',
            style: AppTypography.body(size: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Text('Privacy Policy',
              style: AppTypography.body(
                  size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Your voice notes are end-to-end encrypted. We use encrypted phone hashes for contact matching and never sell your data. You can delete your account at any time.',
            style: AppTypography.body(size: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showSheet({required String title, required Widget child}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: AppColors.modalSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
              top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(title, style: AppTypography.title(size: 20)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.of(context).padding.bottom + 8),
                physics: const BouncingScrollPhysics(),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverSafeArea(
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 18, 0),
                child: Row(
                  children: [
                    if (!widget.isEmbedded) ...[
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
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 14, color: Color(0x9EF5EFE8)),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SETTINGS',
                            style: AppTypography.eyebrow(
                                size: 10, color: AppColors.emberBright)),
                        Text('Your account',
                            style: AppTypography.title(size: 22)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            bottom: false,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).padding.bottom + 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileCard(onEdit: _editProfile),
                  const SizedBox(height: 20),
                  const _FreeBanner(),
                  const SizedBox(height: 24),
                  _SectionLabel('PREFERENCES'),
                  const SizedBox(height: 10),
                  _SettingsGroup(items: [
                    _SettingsTile(
                      icon: Icons.notifications_outlined,
                      label: 'Notifications',
                      sub: _notifVoiceNotes || _notifReminders
                          ? 'Enabled'
                          : 'All off',
                      onTap: _showNotifications,
                    ),
                    _SettingsTile(
                      icon: Icons.language_rounded,
                      label: 'Language',
                      sub: '$_language · $_parentLanguage',
                      onTap: _showLanguage,
                    ),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy',
                      sub: 'End-to-end encrypted',
                      onTap: _showPrivacy,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _SectionLabel('ACCESSIBILITY'),
                  const SizedBox(height: 10),
                  _SettingsGroup(items: [
                    _SettingsTileToggle(
                      icon: Icons.touch_app_rounded,
                      label: 'Tap instead of hold for Pulse',
                      sub: _pulseTapMode
                          ? 'One tap sends your pulse'
                          : 'Hold 3 seconds to send pulse',
                      value: _pulseTapMode,
                      onChanged: (v) async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('pulse_tap_mode', v);
                        if (mounted) setState(() => _pulseTapMode = v);
                      },
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _SectionLabel('ACCOUNT'),
                  const SizedBox(height: 10),
                  _SettingsGroup(items: [
                    _SettingsTile(
                      icon: Icons.phone_outlined,
                      label: 'Phone number',
                      sub: '+91 98765 43210',
                      onTap: _showPhoneNumber,
                    ),
                    _SettingsTile(
                      icon: Icons.card_giftcard_rounded,
                      label: 'Invite to Saanjh',
                      sub: 'Share the app with someone you love · Free',
                      onTap: _showGift,
                      accent: true,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _SectionLabel('ABOUT'),
                  const SizedBox(height: 10),
                  _SettingsGroup(items: [
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      label: 'About Saanjh',
                      sub: 'Version 1.0.0',
                      onTap: _showAbout,
                    ),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      label: 'Terms & Privacy',
                      onTap: _showTerms,
                    ),
                  ]),
                  const SizedBox(height: 32),
                  Center(
                    child: TextButton(
                      onPressed: _signOut,
                      child: Text(
                        'Sign out',
                        style: AppTypography.label(
                            size: 14,
                            color: AppColors.destructive,
                            weight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Profile card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final VoidCallback onEdit;
  const _ProfileCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (_, w) {
        final user = UserStore.instance;
        final name = user.hasName ? user.name : 'Your profile';
        final phone = user.hasPhone
            ? user.displayPhone
            : 'Add phone number';
        final initial = user.initial;

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.emberWarm.withValues(alpha: 0.14), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: user.hasName
                      ? LinearGradient(
                          colors: [user.avatarColor, user.avatarColor.withValues(alpha: 0.70)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : AppColors.emberGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ember.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: AppTypography.display(size: 26).copyWith(
                        color: Colors.white, fontStyle: FontStyle.italic),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.body(
                          size: 17,
                          weight: FontWeight.w600,
                          color: user.hasName
                              ? AppColors.text
                              : AppColors.textMuted),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      phone,
                      style: AppTypography.label(
                          size: 13,
                          color: user.hasPhone
                              ? AppColors.textMuted
                              : AppColors.textFaint),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.ember.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.emberWarm.withValues(alpha: 0.28),
                        width: 1),
                  ),
                  child: Text('Edit',
                      style: AppTypography.label(
                          size: 13,
                          weight: FontWeight.w600,
                          color: AppColors.emberBright)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Free banner ─────────────────────────────────────────────────────────────

class _FreeBanner extends StatelessWidget {
  const _FreeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.ember.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.favorite_rounded,
                size: 20, color: AppColors.emberWarm),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saanjh is free.',
                    style: AppTypography.body(
                        size: 15, weight: FontWeight.w700)),
                Text('No ads · No subscription · No catch.',
                    style: AppTypography.label(
                        size: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section label & group ────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: AppTypography.eyebrow(size: 10, color: AppColors.textFaint));
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> items;
  const _SettingsGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          return Column(
            children: [
              e.value,
              if (e.key < items.length - 1)
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.05),
                  indent: 52,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// Toggle variant of SettingsTile for accessibility options.
class _SettingsTileToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsTileToggle({
    required this.icon,
    required this.label,
    this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.body(size: 15)),
                if (sub != null)
                  Text(sub!,
                      style: AppTypography.label(
                          size: 12, color: AppColors.textFaint)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
            activeThumbColor: AppColors.emberWarm,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final bool accent;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.sub,
    this.onTap,
    this.accent = false,
  });

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.accent
                    ? AppColors.ember.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.06),
              ),
              child: Icon(widget.icon,
                  size: 16,
                  color: widget.accent
                      ? AppColors.emberWarm
                      : AppColors.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                      style: AppTypography.body(
                        size: 15,
                        weight: FontWeight.w500,
                        color: widget.accent
                            ? AppColors.emberWarm
                            : AppColors.text,
                      )),
                  if (widget.sub != null)
                    Text(widget.sub!,
                        style: AppTypography.label(
                            size: 12, color: AppColors.textFaint)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet helpers ────────────────────────────────────────────────────────────

class _SheetDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
      height: 1, color: Colors.white.withValues(alpha: 0.06));
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Text(text,
            style:
                AppTypography.eyebrow(size: 9.5, color: AppColors.textFaint)),
      );
}

class _SheetToggle extends StatelessWidget {
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SheetToggle({
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.body(
                        size: 15, weight: FontWeight.w500)),
                Text(sub,
                    style: AppTypography.label(
                        size: 12, color: AppColors.textFaint)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.emberWarm,
            activeTrackColor: AppColors.ember.withValues(alpha: 0.4),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
            inactiveThumbColor: AppColors.textFaint,
          ),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SheetOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.05), width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppTypography.body(
                    size: 15,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                    color:
                        selected ? AppColors.emberBright : AppColors.text,
                  )),
            ),
            if (selected)
              const Icon(Icons.check_rounded,
                  size: 16, color: AppColors.emberWarm),
          ],
        ),
      ),
    );
  }
}

class _SheetInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;

  const _SheetInfoTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.body(
                        size: 14.5, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(sub,
                    style: AppTypography.body(
                        size: 13.5, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


