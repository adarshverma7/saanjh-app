import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/diary_store.dart';
import '../../state/flicker_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../widgets/saanjh_empty_state.dart';

// ─── Category ─────────────────────────────────────────────────────────────────

enum _Category { family, friends, couple, others }

extension _CategoryExt on _Category {
  String get label {
    switch (this) {
      case _Category.family:  return 'Family';
      case _Category.friends: return 'Friends';
      case _Category.couple:  return 'Partner';
      case _Category.others:  return 'Others';
    }
  }

  String get emoji {
    switch (this) {
      case _Category.family:  return '🌅';
      case _Category.friends: return '🌱';
      case _Category.couple:  return '💛';
      case _Category.others:  return '✨';
    }
  }
}

/// Display-only grouping based on the user's freeform `relation` label.
/// This is purely a visual convenience — no features are gated on category.
/// If `relation` is blank or unrecognised, contact falls into _Category.others.
/// Users can set any label they want; the auto-bucketing is a best-effort helper.
_Category _categorise(DiaryContact c) {
  final r = c.relation.toLowerCase();
  if (r.contains('parent') || r.contains('mother') || r.contains('father') ||
      r.contains('mom')    || r.contains('dad')    || r.contains('dadi')   ||
      r.contains('nani')   || r.contains('grand')  || r.contains('sibling') ||
      r.contains('sister') || r.contains('brother') || r.contains('uncle') ||
      r.contains('aunt')   || r.contains('chacha') || r.contains('chachi') ||
      r.contains('mama')   || r.contains('mausi')  || r.contains('cousin')) {
    return _Category.family;
  }
  if (r.contains('friend') || r.contains('buddy') ||
      r.contains('colleague') || r.contains('classmate')) {
    return _Category.friends;
  }
  if (r.contains('partner') || r.contains('spouse') || r.contains('wife') ||
      r.contains('husband')  || r.contains('girlfriend') || r.contains('boyfriend')) {
    return _Category.couple;
  }
  return _Category.others;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class PeopleScreen extends StatefulWidget {
  final bool isEmbedded;
  const PeopleScreen({super.key, this.isEmbedded = false});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _store = DiaryStore.instance;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DiaryContact> _applyFilter(List<DiaryContact> contacts) {
    if (_query.isEmpty) return contacts;
    final q = _query.toLowerCase();
    final digits = _query.replaceAll(RegExp(r'\D'), '');
    return contacts.where((c) {
      if (c.name.toLowerCase().contains(q)) return true;
      if (digits.isNotEmpty &&
          c.phone.replaceAll(RegExp(r'\D'), '').contains(digits)) {
        return true;
      }
      return false;
    }).toList();
  }

  Map<_Category, List<DiaryContact>> _group(List<DiaryContact> contacts) {
    final map = <_Category, List<DiaryContact>>{};
    for (final d in contacts.where((d) => !d.isGroup)) {
      map.putIfAbsent(_categorise(d), () => []).add(d);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (_, w) {
        final all = _store.diaries;
        final filtered = _applyFilter(all);
        final groups = filtered.where((d) => d.isGroup).toList();
        final grouped = _group(filtered);

        return Scaffold(
          backgroundColor: AppColors.ink,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: _Header(isEmbedded: widget.isEmbedded),
                ),
              ),
              if (all.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: _SearchField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                ),
              if (all.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    onDiscover: () => context.push(AppRoutes.discover),
                  ),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoResults(query: _query),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20, 16, 20,
                    MediaQuery.of(context).padding.bottom + 48,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (_query.isEmpty) ...[
                        _QuickActions(
                          onGroup:
                              () => context.push(AppRoutes.createGroup),
                          onOccasion:
                              () => context.push(AppRoutes.occasionPlan),
                          onInvite:
                              () => context.push(AppRoutes.inviteRecipient),
                        ),
                        const SizedBox(height: 28),
                      ],

                      // ── Category sections ─────────────────────────────
                      for (final cat in _Category.values) ...[
                        if (grouped[cat]?.isNotEmpty == true) ...[
                          _SectionHeader(
                            emoji: cat.emoji,
                            label: cat.label,
                            count: grouped[cat]!.length,
                          ),
                          const SizedBox(height: 10),
                          for (final d in grouped[cat]!)
                            _PersonTile(
                              contact: d,
                              onTap: () => context.push(
                                AppRoutes.diaryThread,
                                extra: {'diaryId': d.id},
                              ),
                            ),
                          const SizedBox(height: 24),
                        ],
                      ],

                      // ── Groups section ────────────────────────────────
                      if (groups.isNotEmpty) ...[
                        _SectionHeader(
                          emoji: '👨‍👩‍👧',
                          label: 'Groups',
                          count: groups.length,
                        ),
                        const SizedBox(height: 10),
                        for (final d in groups)
                          _PersonTile(
                            contact: d,
                            onTap: () => context.push(AppRoutes.groupThread),
                          ),
                        const SizedBox(height: 24),
                      ],

                      if (_query.isEmpty)
                        _DiscoverRow(
                          onTap: () => context.push(AppRoutes.discover),
                        ),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
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
              Text('PEOPLE',
                  style: AppTypography.eyebrow(
                      size: 10, color: AppColors.emberBright)),
              const SizedBox(height: 2),
              Text('Your people', style: AppTypography.title(size: 24)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Search field ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTypography.body(size: 14),
        cursorColor: AppColors.emberWarm,
        decoration: InputDecoration(
          hintText: 'Search by name or number…',
          hintStyle:
              AppTypography.body(size: 14, color: AppColors.textFaint),
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: AppColors.textFaint),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ─── Quick actions ────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final VoidCallback onGroup;
  final VoidCallback onOccasion;
  final VoidCallback onInvite;

  const _QuickActions({
    required this.onGroup,
    required this.onOccasion,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.group_add_rounded,
            label: 'New group',
            onTap: onGroup,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.event_rounded,
            label: 'Occasion',
            onTap: onOccasion,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.person_add_rounded,
            label: 'Invite',
            onTap: onInvite,
            accent: true,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
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
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.accent
                ? AppColors.ember.withValues(alpha: _pressed ? 0.5 : 0.30)
                : Colors.white.withValues(alpha: _pressed ? 0.12 : 0.08),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              size: 18,
              color: widget.accent ? AppColors.emberWarm : AppColors.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: AppTypography.label(
                size: 11.5,
                color: widget.accent
                    ? AppColors.emberBright
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String emoji;
  final String label;
  final int count;

  const _SectionHeader({
    required this.emoji,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: AppTypography.eyebrow(size: 10, color: AppColors.textFaint),
        ),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$count',
            style: AppTypography.label(
                size: 10,
                weight: FontWeight.w600,
                color: AppColors.textFaint),
          ),
        ),
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

// ─── Person tile ──────────────────────────────────────────────────────────────

class _PersonTile extends StatefulWidget {
  final DiaryContact contact;
  final VoidCallback onTap;
  const _PersonTile({required this.contact, required this.onTap});

  @override
  State<_PersonTile> createState() => _PersonTileState();
}

class _PersonTileState extends State<_PersonTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.contact;
    return ListenableBuilder(
      listenable: FlickerStore.instance,
      builder: (_, w) {
        final ps = FlickerStore.instance;
        final received = ps.receivedToday(d.id);
        final mePulsed = ps.hasMeFlickeredToday(d.id);
        final mutual = received != null && mePulsed;
        final receivedNotSent = received != null && !mePulsed;
        final streakDays = DiaryStore.instance.streakDays(d.id);
        final atRisk = DiaryStore.instance.streakAtRisk(d.id);
        final hasSnippet = d.lastSnippet.isNotEmpty;

        // Avatar ring — same priority as home screen
        final Color ringColor;
        final double ringAlpha;
        if (mutual) {
          ringColor = AppColors.successGreen;
          ringAlpha = 0.65;
        } else if (receivedNotSent) {
          ringColor = AppColors.emberWarm;
          ringAlpha = 0.82;
        } else if (streakDays > 0) {
          ringColor = AppColors.emberWarm;
          ringAlpha = 0.28;
        } else {
          ringColor = Colors.transparent;
          ringAlpha = 0.0;
        }

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
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: receivedNotSent
                  ? AppColors.ember.withValues(alpha: 0.05)
                  : _pressed
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: receivedNotSent
                    ? AppColors.emberWarm.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: _pressed ? 0.10 : 0.06),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // ── Avatar with ring ────────────────────────────────────
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            d.avatarColor,
                            d.avatarColor.withValues(alpha: 0.65),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: ringAlpha > 0
                            ? Border.all(
                                color: ringColor.withValues(alpha: ringAlpha),
                                width: 2,
                              )
                            : null,
                        boxShadow: ringAlpha > 0
                            ? [
                                BoxShadow(
                                  color: ringColor
                                      .withValues(alpha: ringAlpha * 0.45),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          d.initial,
                          style: AppTypography.title(size: 19).copyWith(
                            color: Colors.white,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                    if (d.isGroup)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.ink,
                            border:
                                Border.all(color: AppColors.ink, width: 1.5),
                          ),
                          child: const Icon(Icons.group_rounded,
                              size: 10, color: AppColors.emberBright),
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 12),

                // ── Text content ────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: displayName + time
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.displayName,
                              style: AppTypography.body(
                                size: 15,
                                weight: receivedNotSent
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (hasSnippet) ...[
                            const SizedBox(width: 6),
                            Text(
                              d.lastTime,
                              style: AppTypography.label(
                                size: 11,
                                color: receivedNotSent
                                    ? AppColors.emberBright
                                    : AppColors.textFaint,
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Relation label — shown as optional metadata below name
                      if (d.relation.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          d.relation,
                          style: AppTypography.label(
                              size: 11, color: AppColors.textFaint),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                      const SizedBox(height: 4),
                      // Bottom row: snippet + right badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.lastSnippet,
                              style: AppTypography.label(
                                size: 12.5,
                                color: AppColors.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (mutual)
                            const _PeopleMutualBadge()
                          else if (receivedNotSent)
                            _PeopleFlickeredYouBadge(timeLabel: received.timeLabel)
                          else if (streakDays > 0)
                            _PeopleStreakBadge(
                                days: streakDays, atRisk: atRisk)
                          else if (!hasSnippet)
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: AppColors.textFaint),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── People tab badges ────────────────────────────────────────────────────────

class _PeopleStreakBadge extends StatelessWidget {
  final int days;
  final bool atRisk;
  const _PeopleStreakBadge({required this.days, required this.atRisk});

  @override
  Widget build(BuildContext context) {
    final color = atRisk ? AppColors.destructive : AppColors.emberWarm;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(atRisk ? '⚠️' : '🔥',
              style: const TextStyle(fontSize: 10, height: 1.2)),
          const SizedBox(width: 3),
          Text(
            '$days',
            style: AppTypography.label(
                size: 11, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _PeopleFlickeredYouBadge extends StatelessWidget {
  final String? timeLabel;
  const _PeopleFlickeredYouBadge({this.timeLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.emberWarm,
            boxShadow: AppShadows.dotGlow(intensity: 0.60, blur: 5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          timeLabel != null ? 'here at $timeLabel' : 'was here',
          style: AppTypography.label(
              size: 11, weight: FontWeight.w600, color: AppColors.emberBright),
        ),
      ],
    );
  }
}

class _PeopleMutualBadge extends StatelessWidget {
  const _PeopleMutualBadge();

  @override
  Widget build(BuildContext context) {
    return Text(
      '♥ both here',
      style: AppTypography.label(
          size: 11,
          weight: FontWeight.w600,
          color: const Color(0xFF7CD992)),
    );
  }
}

// ─── Discover row ─────────────────────────────────────────────────────────────

class _DiscoverRow extends StatefulWidget {
  final VoidCallback onTap;
  const _DiscoverRow({required this.onTap});

  @override
  State<_DiscoverRow> createState() => _DiscoverRowState();
}

class _DiscoverRowState extends State<_DiscoverRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _pressed
                ? AppColors.ember.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.09),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_rounded,
                size: 15, color: AppColors.emberBright),
            const SizedBox(width: 8),
            Text(
              'Find more people on Saanjh',
              style: AppTypography.label(
                  size: 13, color: AppColors.emberBright),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── No results ───────────────────────────────────────────────────────────────

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 80),
        child: Text(
          'No results for "$query"',
          style: AppTypography.serifItalic(size: 17),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onDiscover;
  const _EmptyState({required this.onDiscover});

  @override
  Widget build(BuildContext context) {
    return SaanjhEmptyState(
      visual: const _PeopleVisual(),
      title: 'Your people are one tap away.',
      body: 'Find who\'s on Saanjh or invite someone you love.',
      ctaLabel: 'Find connections →',
      onCta: onDiscover,
    );
  }
}

// ─── People visual (two silhouettes + floating ♥) ─────────────────────────────

class _PeopleVisual extends StatefulWidget {
  const _PeopleVisual();

  @override
  State<_PeopleVisual> createState() => _PeopleVisualState();
}

class _PeopleVisualState extends State<_PeopleVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => SizedBox(
        width: 140,
        height: 100,
        child: CustomPaint(
          painter: _SilhouettePainter(_ctrl.value),
        ),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  final double breathe; // 0.0 → 1.0

  const _SilhouettePainter(this.breathe);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.55;

    final silhouettePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    final leanAngle = 0.12 + breathe * 0.04;

    // Left silhouette — leans right toward centre
    canvas.save();
    canvas.translate(cx - 34, cy);
    canvas.rotate(leanAngle);
    _drawFigure(canvas, silhouettePaint);
    canvas.restore();

    // Right silhouette — leans left toward centre
    canvas.save();
    canvas.translate(cx + 34, cy);
    canvas.rotate(-leanAngle);
    _drawFigure(canvas, silhouettePaint);
    canvas.restore();

    // Floating ♥ between them
    final heartY = size.height * 0.18 - breathe * 4;
    final heartAlpha = 0.6 + breathe * 0.35;
    final heartPaint = Paint()
      ..color = AppColors.emberWarm.withValues(alpha: heartAlpha);
    _drawHeart(canvas, Offset(cx, heartY), heartPaint, 9.0);
  }

  void _drawFigure(Canvas canvas, Paint paint) {
    // Head
    canvas.drawCircle(const Offset(0, -32), 10, paint);
    // Body (rounded rect)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-9, -20, 18, 28),
        const Radius.circular(8),
      ),
      paint,
    );
  }

  void _drawHeart(Canvas canvas, Offset centre, Paint paint, double size) {
    final path = Path();
    final s = size;
    path.moveTo(centre.dx, centre.dy + s * 0.3);
    path.cubicTo(
      centre.dx - s * 1.2, centre.dy - s * 0.6,
      centre.dx - s * 1.8, centre.dy + s * 0.3,
      centre.dx, centre.dy + s * 1.2,
    );
    path.cubicTo(
      centre.dx + s * 1.8, centre.dy + s * 0.3,
      centre.dx + s * 1.2, centre.dy - s * 0.6,
      centre.dx, centre.dy + s * 0.3,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) => old.breathe != breathe;
}

