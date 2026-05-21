import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../router/app_routes.dart';
import '../../services/notification_service.dart';
import '../../services/on_this_day_service.dart';
import '../../services/weekly_digest_service.dart';
import '../../services/share_card_service.dart';
import '../../state/diary_store.dart';
import '../../state/personal_reflection_store.dart';
import '../../state/flicker_store.dart';
import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/milestone_share_card.dart';
import '../../widgets/saanjh_dialog.dart';

class MeScreen extends StatefulWidget {
  final bool isEmbedded;
  const MeScreen({super.key, this.isEmbedded = false});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  bool _notifOn = true;
  bool _onThisDay = true;

  static const _kNotifPref    = 'pref_notif_on';
  static const _kOnThisDayPref = 'pref_on_this_day_on';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifOn  = prefs.getBool(_kNotifPref)     ?? true;
      _onThisDay = prefs.getBool(_kOnThisDayPref) ?? true;
    });
  }

  Future<void> _setNotif(bool value) async {
    setState(() => _notifOn = value);
    await NotificationService.instance.setEnabled(value);
    // Mirror to the weekly digest — disabling alerts cancels scheduled notifs.
    await WeeklyDigestService.instance.setEnabled(value);
  }

  Future<void> _setOnThisDay(bool value) async {
    setState(() => _onThisDay = value);
    await OnThisDayService.instance.setEnabled(value);
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
                gradient: RadialGradient(
                  center: const Alignment(0, -0.7),
                  radius: 0.8,
                  colors: [
                    AppColors.ember.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: _Header(isEmbedded: widget.isEmbedded),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl, AppSpacing.xs, AppSpacing.xl,
                    MediaQuery.of(context).padding.bottom + 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── Avatar hero ──────────────────────────────────────
                      _ProfileHero(
                        onEdit: () => context.push(AppRoutes.profile),
                      ),

                      const SizedBox(height: 20),

                      // ─── Live stats ───────────────────────────────────────
                      const _ProfileStats(),

                      const SizedBox(height: 16),

                      // ─── My Journal entry point ───────────────────────────
                      const _JournalCard(),

                      const SizedBox(height: 16),

                      // ─── Free forever card ────────────────────────────────
                      const _FreeCard(),

                      const SizedBox(height: 24),

                      // ─── Quick settings ───────────────────────────────────
                      const _SectionHeader('QUICK SETTINGS'),
                      const SizedBox(height: 10),
                      _Card(
                        child: Column(
                          children: [
                            _InlineToggle(
                              icon: Icons.notifications_outlined,
                              label: 'Voice note alerts',
                              value: _notifOn,
                              onChanged: (v) {
                                HapticFeedback.selectionClick();
                                _setNotif(v);
                              },
                            ),
                            const _RowDivider(),
                            _InlineToggle(
                              icon: Icons.auto_awesome_outlined,
                              label: 'On This Day',
                              sub: 'Surface memories from 1 year ago',
                              value: _onThisDay,
                              onChanged: (v) {
                                HapticFeedback.selectionClick();
                                _setOnThisDay(v);
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ─── Account ──────────────────────────────────────────
                      const _SectionHeader('ACCOUNT'),
                      const SizedBox(height: 10),
                      _Card(
                        child: Column(
                          children: [
                            ListenableBuilder(
                              listenable: DiaryStore.instance,
                              builder: (_, _) => _NavRow(
                                icon: Icons.people_outline_rounded,
                                label: 'Your connections',
                                sub: '${DiaryStore.instance.diaries.length} people',
                                onTap: () => context.push(AppRoutes.people),
                              ),
                            ),
                            const _RowDivider(),
                            _NavRow(
                              icon: Icons.language_rounded,
                              label: 'Language',
                              sub: 'English · हिंदी',
                              onTap: () => _showLanguageSheet(context),
                            ),
                            const _RowDivider(),
                            _NavRow(
                              icon: Icons.privacy_tip_outlined,
                              label: 'Privacy',
                              sub: 'End-to-end encrypted',
                              onTap: () => _showPrivacySheet(context),
                            ),
                            const _RowDivider(),
                            _NavRow(
                              icon: Icons.archive_outlined,
                              label: 'Archived chats',
                              sub: 'Diaries you\'ve put away',
                              onTap: () {},
                            ),
                            const _RowDivider(),
                            _NavRow(
                              icon: Icons.card_giftcard_rounded,
                              label: 'Invite to Saanjh',
                              sub: 'Share the app · Free for everyone',
                              onTap: () => _showGiftSheet(context),
                              accent: true,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ─── Memory Jar ───────────────────────────────────────
                      const _SectionHeader('✨ MEMORY JAR'),
                      const SizedBox(height: 10),
                      _MemoryJarSection(
                        onViewAll: () => context.push(AppRoutes.memoryJar),
                      ),

                      const SizedBox(height: 24),

                      // ─── Personal Journal ──────────────────────────────────
                      const _SectionHeader('🔒 MY JOURNAL'),
                      const SizedBox(height: 10),
                      _PersonalJournalSection(
                        onViewAll: () =>
                            context.push(AppRoutes.personalJournal),
                        onAddToday: () => context.push(
                          AppRoutes.voiceRecord,
                          extra: {'isVideo': false, 'isPrivateReflection': true},
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ─── Your moments ─────────────────────────────────────
                      const _SectionHeader('YOUR MOMENTS'),
                      const SizedBox(height: 10),
                      _Card(
                        child: _NavRow(
                          icon: Icons.menu_book_rounded,
                          label: 'Memory Book',
                          sub: 'Print your year in voices · from ₹399',
                          onTap: () => context.push(AppRoutes.memoryBook),
                          accent: true,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ─── More ─────────────────────────────────────────────
                      const _SectionHeader('MORE'),
                      const SizedBox(height: 10),
                      _Card(
                        child: Column(
                          children: [
                            _NavRow(
                              icon: Icons.info_outline_rounded,
                              label: 'About Saanjh',
                              sub: 'Version 1.0.0',
                              onTap: () => _showAboutSheet(context),
                            ),
                            const _RowDivider(),
                            _NavRow(
                              icon: Icons.description_outlined,
                              label: 'Terms & Privacy',
                              onTap: () => _showTermsSheet(context),
                            ),
                            const _RowDivider(),
                            _NavRow(
                              icon: Icons.delete_forever_rounded,
                              label: 'Delete account',
                              sub: 'Permanently remove all your data',
                              onTap: () => _confirmDeleteAccount(),
                              accent: false,
                              destructive: true,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 36),

                      // ─── Sign out ─────────────────────────────────────────
                      Center(
                        child: _SignOutButton(
                          onTap: () => _confirmSignOut(),
                        ),
                      ),

                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Saanjh · सांझ · v1.0.0',
                          style: AppTypography.label(
                              size: 11, color: AppColors.textFaint),
                        ),
                      ),
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

  // ── Dialogs & sheets ────────────────────────────────────────────────────────

  void _confirmDeleteAccount() async {
    HapticFeedback.selectionClick();
    final confirmed = await SaanjhDialog.showDestructive(
      context,
      title: 'Delete account?',
      body: 'All your diaries, voice notes and streaks will be permanently '
          'deleted. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    context.go(AppRoutes.splash);
  }

  void _confirmSignOut() async {
    HapticFeedback.selectionClick();
    final confirmed = await SaanjhDialog.showDestructive(
      context,
      title: 'Sign out?',
      body: 'You can sign back in anytime with your phone number.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    context.go(AppRoutes.splash);
  }

  void _showSheet(BuildContext ctx,
      {required String title, required Widget child}) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
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
                    onTap: () => Navigator.pop(ctx),
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
                    20, 0, 20,
                    MediaQuery.of(ctx).padding.bottom + 12),
                physics: const BouncingScrollPhysics(),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageSheet(BuildContext ctx) {
    _showSheet(
      ctx,
      title: 'Language',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR APP',
              style: AppTypography.eyebrow(
                  size: 9.5, color: AppColors.textFaint)),
          const SizedBox(height: 8),
          for (final lang in [
            'English',
            'हिंदी',
            'తెలుగు',
            'தமிழ்',
            'ਪੰਜਾਬੀ'
          ])
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                        child:
                            Text(lang, style: AppTypography.body(size: 15))),
                    if (lang == 'English')
                      const Icon(Icons.check_rounded,
                          size: 16, color: AppColors.emberWarm),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _showPrivacySheet(BuildContext ctx) {
    _showSheet(
      ctx,
      title: 'Privacy',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (icon, title, sub, color) in [
            (
              Icons.lock_rounded,
              'End-to-end encrypted',
              'Only you and your diary partner can hear voice notes.',
              AppColors.emberWarm
            ),
            (
              Icons.contacts_rounded,
              'Private contact matching',
              'Encrypted phone hashes — we never upload your address book.',
              AppColors.successGreen
            ),
            (
              Icons.location_off_rounded,
              'No location tracking',
              'Saanjh never accesses your GPS.',
              AppColors.azure
            ),
          ])
            Padding(
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
                    child: Icon(icon, size: 17, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: AppTypography.body(
                                size: 14.5, weight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(sub,
                            style: AppTypography.body(
                                size: 13.5,
                                color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _showGiftSheet(BuildContext ctx) {
    _showSheet(
      ctx,
      title: 'Invite to Saanjh',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.ember.withValues(alpha: 0.14),
                  AppColors.emberWarm.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: AppColors.emberWarm.withValues(alpha: 0.25),
                  width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saanjh is free.',
                    style: AppTypography.title(size: 20)),
                const SizedBox(height: 6),
                Text('No subscription · No ads · No catch.',
                    style: AppTypography.label(
                        size: 13, color: AppColors.emberBright)),
                const SizedBox(height: 10),
                Text(
                  'Share the app with the people you love. They sign up in under a minute and your first diary starts right away.',
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
              Navigator.pop(ctx);
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
            onPressed: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _showAboutSheet(BuildContext ctx) {
    _showSheet(
      ctx,
      title: 'About Saanjh',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  Text('Saanjh', style: AppTypography.title(size: 22)),
                  Text('v1.0.0 · build 1',
                      style: AppTypography.label(
                          size: 12.5, color: AppColors.textFaint)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Saanjh (सांझ — "dusk") is a living diary between the people who love each other most.\n\nBuilt for Indian families — and anyone who wants to stay close without the pressure of a phone call.',
            style: AppTypography.serifItalic(size: 16),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showTermsSheet(BuildContext ctx) {
    _showSheet(
      ctx,
      title: 'Terms & Privacy',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Terms of Service',
              style: AppTypography.body(size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'By using Saanjh you agree to use it to connect with family and friends — not for commercial or harmful purposes.',
            style: AppTypography.body(size: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Text('Privacy Policy',
              style: AppTypography.body(size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Your voice notes are end-to-end encrypted. We use encrypted phone hashes for contact matching and never sell your data. Delete your account anytime.',
            style: AppTypography.body(size: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isEmbedded;
  const _Header({required this.isEmbedded});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
      child: Row(
        children: [
          if (!isEmbedded) ...[
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
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 14, color: Color(0x9EF5EFE8)),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ME',
                  style: AppTypography.eyebrow(
                      size: 10, color: AppColors.emberBright)),
              const SizedBox(height: 2),
              Text('Your profile', style: AppTypography.title(size: 24)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Profile hero ─────────────────────────────────────────────────────────────

class _ProfileHero extends StatelessWidget {
  final VoidCallback onEdit;
  const _ProfileHero({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (_, w) {
        final user = UserStore.instance;
        return Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onEdit();
                },
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: user.hasName
                            ? LinearGradient(
                                colors: [
                                  user.avatarColor,
                                  user.avatarColor.withValues(alpha: 0.70),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : AppColors.emberGradient,
                        boxShadow: [
                          BoxShadow(
                            color: (user.hasName
                                    ? user.avatarColor
                                    : AppColors.ember)
                                .withValues(alpha: 0.35),
                            blurRadius: 22,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          user.initial,
                          style: AppTypography.display(size: 44).copyWith(
                              color: Colors.white,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.inkRaised,
                        border: Border.all(
                            color: AppColors.inkRaised, width: 2),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          size: 13, color: AppColors.emberWarm),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              user.hasName
                  ? Text(user.name,
                      style: AppTypography.title(size: 24))
                  : GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onEdit();
                      },
                      child: Text(
                        'Add your name',
                        style: AppTypography.title(size: 22).copyWith(
                          color: AppColors.emberBright
                              .withValues(alpha: 0.55),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
              const SizedBox(height: 4),
              if (user.hasPhone)
                Text(user.displayPhone,
                    style: AppTypography.label(
                        size: 13, color: AppColors.textMuted))
              else
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onEdit();
                  },
                  child: Text(
                    'No phone number set',
                    style: AppTypography.label(
                        size: 13, color: AppColors.textFaint),
                  ),
                ),
              const SizedBox(height: 8),
              // Status line — serifItalic if set, placeholder if not
              GestureDetector(
                onTap: () {
                  final ctrl = TextEditingController(
                      text: UserStore.instance.status);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => Padding(
                      padding: EdgeInsets.only(
                          bottom:
                              MediaQuery.of(context).viewInsets.bottom),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppColors.modalSurface,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 16, 20, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Your status',
                                    style: AppTypography.title(size: 18)),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: ctrl,
                                  autofocus: true,
                                  maxLength: 50,
                                  style: AppTypography.body(size: 15),
                                  decoration: InputDecoration(
                                    hintText: 'Something on your mind…',
                                    hintStyle: AppTypography.body(
                                        size: 15,
                                        color: AppColors.textFaint),
                                    filled: true,
                                    fillColor:
                                        Colors.white.withValues(alpha: 0.05),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onSubmitted: (v) {
                                    UserStore.instance.setStatus(v);
                                    Navigator.pop(context);
                                  },
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    UserStore.instance
                                        .setStatus(ctrl.text);
                                    Navigator.pop(context);
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.emberGradient,
                                      borderRadius:
                                          BorderRadius.circular(14),
                                    ),
                                    child: Center(
                                      child: Text('Save',
                                          style: AppTypography.button(
                                              color: Colors.white)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: Text(
                  user.status.isNotEmpty ? user.status : 'Set a status...',
                  style: AppTypography.serifItalic(
                    size: 14,
                    color: user.status.isNotEmpty
                        ? AppColors.textMuted
                        : AppColors.textFaint,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _EditProfileBtn(onTap: onEdit),
            ],
          ),
        );
      },
    );
  }
}

class _EditProfileBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _EditProfileBtn({required this.onTap});

  @override
  State<_EditProfileBtn> createState() => _EditProfileBtnState();
}

class _EditProfileBtnState extends State<_EditProfileBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withValues(alpha: _pressed ? 0.14 : 0.10),
              width: 1),
        ),
        child: Text('Edit profile',
            style: AppTypography.label(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.emberBright)),
      ),
    );
  }
}

// ─── Profile stats ────────────────────────────────────────────────────────────

class _ProfileStats extends StatefulWidget {
  const _ProfileStats();

  @override
  State<_ProfileStats> createState() => _ProfileStatsState();
}

class _ProfileStatsState extends State<_ProfileStats> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareStreak() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final ds = DiaryStore.instance;
    final diaries = ds.diaries;
    if (diaries.isEmpty) { setState(() => _sharing = false); return; }
    final best = diaries.reduce((a, b) =>
        ds.streakDays(a.id) >= ds.streakDays(b.id) ? a : b);
    await ShareCardService.instance.shareStreakCard(
      _cardKey,
      ds.streakDays(best.id),
      best.displayName,
    );
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [DiaryStore.instance, FlickerStore.instance]),
      builder: (_, w) {
        final ds = DiaryStore.instance;
        final diaryCount = ds.diaries.length;
        final bestStreak = ds.bestStreakDays;

        // Find best diary for the share card
        final diaries = ds.diaries;
        final bestDiary = diaries.isEmpty
            ? null
            : diaries.reduce((a, b) =>
                ds.streakDays(a.id) >= ds.streakDays(b.id) ? a : b);

        return Stack(
          children: [
            // Off-screen share card
            if (bestDiary != null)
              Offstage(
                child: MilestoneShareCard(
                  key: _cardKey,
                  streakDays: ds.streakDays(bestDiary.id),
                  contactName: bestDiary.displayName,
                  milestoneLabel: ds.streakLabel(bestDiary.id),
                ),
              ),

            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Row(
                    children: [
                      _Stat(value: '$diaryCount', label: 'Diaries'),
                      _StatDivider(),
                      _Stat(
                        value: bestStreak == 0 ? '—' : '${bestStreak}d',
                        label: 'Best streak',
                      ),
                      _StatDivider(),
                      _Stat(value: '0', label: 'Moments'),
                    ],
                  ),
                ),
                // Share streak button — shown when best streak > 7
                if (bestStreak > 7) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _sharing ? null : _shareStreak,
                    child: Text(
                      _sharing ? 'Sharing…' : 'Share your streak →',
                      style: AppTypography.label(
                        size: 13,
                        color: AppColors.emberWarm,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.display(size: 24).copyWith(
                color: AppColors.emberWarm, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: AppTypography.label(
                  size: 10.5, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 32,
        color: Colors.white.withValues(alpha: 0.07),
      );
}

// ─── My Journal card ─────────────────────────────────────────────────────────

class _JournalCard extends StatefulWidget {
  const _JournalCard();

  @override
  State<_JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<_JournalCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PersonalReflectionStore.instance,
      builder: (_, _) {
        final count = PersonalReflectionStore.instance.count;
        return Semantics(
          label: 'My Journal, $count private ${count == 1 ? 'entry' : 'entries'}',
          button: true,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: () {
              HapticFeedback.selectionClick();
              context.push(AppRoutes.personalJournal);
            },
            child: AnimatedContainer(
              duration: AppMotion.fast,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.violet.withValues(
                    alpha: _pressed ? 0.10 : 0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.violet.withValues(
                      alpha: _pressed ? 0.35 : 0.18),
                ),
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.violet.withValues(alpha: 0.14),
                    ),
                    child: Icon(Icons.lock_rounded,
                        size: 20, color: AppColors.violet),
                  ),
                  const SizedBox(width: 14),
                  // Labels
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Journal',
                            style: AppTypography.body(
                                size: 15, weight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          count == 0
                              ? 'Private · only visible to you'
                              : '$count private '
                                  '${count == 1 ? 'entry' : 'entries'}'
                                  ' · only you',
                          style: AppTypography.caption(
                              color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  // Count badge
                  if (count > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.violet.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: AppTypography.label(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.violet,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.textFaint),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Free forever card ────────────────────────────────────────────────────────

class _FreeCard extends StatelessWidget {
  const _FreeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.ember.withValues(alpha: 0.10),
            AppColors.emberWarm.withValues(alpha: 0.04),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppColors.emberWarm.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.ember.withValues(alpha: 0.15),
            ),
            child: const Icon(Icons.favorite_rounded,
                size: 20, color: AppColors.emberWarm),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Free for everyone.',
                    style: AppTypography.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 2),
                Text('No ads · No subscription · No catch.',
                    style: AppTypography.label(
                        size: 12, color: AppColors.emberBright.withValues(alpha: 0.70))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: AppTypography.eyebrow(
                size: 10, color: AppColors.textFaint)),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Memory Jar section ───────────────────────────────────────────────────────

// ─── Personal Journal section ─────────────────────────────────────────────────

class _PersonalJournalSection extends StatelessWidget {
  final VoidCallback onViewAll;
  final VoidCallback onAddToday;

  const _PersonalJournalSection({
    required this.onViewAll,
    required this.onAddToday,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PersonalReflectionStore.instance,
      builder: (_, _) {
        final store = PersonalReflectionStore.instance;
        final count = store.count;
        final todayMemory = store.todaysMemory();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "A year ago" golden banner
            if (todayMemory != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A1A00),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFFFFB800)
                          .withValues(alpha: 0.30)),
                ),
                child: Row(
                  children: [
                    const Text('🎙', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'A year ago today, you recorded something.',
                        style: AppTypography.serifItalic(
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ),
                    TextButton(
                      onPressed: onViewAll,
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text('Listen →',
                          style: AppTypography.label(
                              size: 12,
                              color: const Color(0xFFFFB800))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Count + actions row
            Row(
              children: [
                Text(
                  count == 0
                      ? 'No private reflections yet.'
                      : '$count private ${count == 1 ? 'reflection' : 'reflections'}',
                  style: AppTypography.label(
                      size: 13, color: AppColors.textMuted),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onAddToday,
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Text(
                    'Add today\'s →',
                    style: AppTypography.label(
                        size: 12, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                if (count > 0)
                  TextButton(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text(
                      'View all →',
                      style: AppTypography.label(
                          size: 12, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─── Memory Jar section ───────────────────────────────────────────────────────

class _MemoryJarSection extends StatelessWidget {
  final VoidCallback onViewAll;
  const _MemoryJarSection({required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DiaryStore.instance,
      builder: (_, _) {
        // Gather all jarred entries across all diaries
        final chips = <({DiaryContact diary, String entryId})>[];
        for (final diary in DiaryStore.instance.diaries) {
          for (final entryId in DiaryStore.instance.jarredFor(diary.id)) {
            chips.add((diary: diary, entryId: entryId));
          }
        }

        if (chips.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              'Long-press any voice note to save it here.',
              style: AppTypography.serifItalic(size: 15),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _JarChip(diary: chips[i].diary),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                'View all →',
                style: AppTypography.label(
                    size: 12, color: AppColors.emberWarm),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _JarChip extends StatelessWidget {
  final DiaryContact diary;
  const _JarChip({required this.diary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ember.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.emberWarm.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: diary.avatarColor.withValues(alpha: 0.25),
            ),
            child: Center(
              child: Text(
                diary.initial,
                style: AppTypography.label(
                    size: 10, color: diary.avatarColor),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            diary.displayName.split(' ').first,
            style: AppTypography.label(size: 12, color: AppColors.text),
          ),
          const SizedBox(width: 5),
          const Text('🎙', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Settings card wrapper ────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: child,
    );
  }
}

// ─── Row divider ──────────────────────────────────────────────────────────────

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 62, // 14 pad + 36 icon + 12 gap
        color: Colors.white.withValues(alpha: 0.05),
      );
}

// ─── Inline toggle row ────────────────────────────────────────────────────────

class _InlineToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _InlineToggle({
    required this.icon,
    required this.label,
    this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
            child: Icon(icon, size: 17, color: AppColors.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.body(
                        size: 15, weight: FontWeight.w500)),
                if (sub != null)
                  Text(sub!,
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

// ─── Navigation row ───────────────────────────────────────────────────────────

class _NavRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final bool accent;
  final bool destructive;

  const _NavRow({
    required this.icon,
    required this.label,
    this.sub,
    required this.onTap,
    this.accent = false,
    this.destructive = false,
  });

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.destructive
        ? AppColors.destructive
        : widget.accent
            ? AppColors.emberWarm
            : AppColors.textMuted;
    final labelColor = widget.destructive
        ? AppColors.destructive
        : widget.accent
            ? AppColors.emberWarm
            : AppColors.text;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.destructive
                    ? AppColors.destructive.withValues(alpha: 0.10)
                    : widget.accent
                        ? AppColors.ember.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.06),
              ),
              child: Icon(widget.icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: AppTypography.body(
                      size: 15,
                      weight: FontWeight.w500,
                      color: labelColor,
                    ),
                  ),
                  if (widget.sub != null) ...[
                    const SizedBox(height: 1),
                    Text(widget.sub!,
                        style: AppTypography.label(
                            size: 12, color: AppColors.textFaint)),
                  ],
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

// ─── Sign out button ──────────────────────────────────────────────────────────

class _SignOutButton extends StatefulWidget {
  final VoidCallback onTap;
  const _SignOutButton({required this.onTap});

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
        decoration: BoxDecoration(
          color: _pressed
              ? AppColors.destructive.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _pressed
                ? AppColors.destructive.withValues(alpha: 0.30)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Text(
          'Sign out',
          style: AppTypography.label(
              size: 14,
              color: AppColors.destructive,
              weight: FontWeight.w500),
        ),
      ),
    );
  }
}

