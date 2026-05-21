import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/diary_store.dart';
import '../../state/flicker_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/saanjh_logo.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _store = DiaryStore.instance;
  final _nameCtrl = TextEditingController();
  final _selectedIds = <String>{};
  String? _elderMemberId;
  bool _creating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      _nameCtrl.text.trim().isNotEmpty && _selectedIds.length >= 2;

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // Auto-suggest a group name from selected members.
  void _autoSuggestName() {
    if (_nameCtrl.text.trim().isNotEmpty) return;
    final selected = _store.diaries
        .where((d) => _selectedIds.contains(d.id))
        .map((d) => d.name.split(' ').first)
        .toList();
    if (selected.length >= 2) {
      final name = selected.length == 2
          ? '${selected[0]} & ${selected[1]}'
          : '${selected[0]}, ${selected[1]} & more';
      _nameCtrl.text = name;
    }
  }

  Future<void> _createGroup() async {
    if (!_canCreate || _creating) return;
    HapticFeedback.mediumImpact();
    setState(() => _creating = true);

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final selected = _store.diaries
        .where((d) => _selectedIds.contains(d.id))
        .toList();
    final groupName = _nameCtrl.text.trim();
    final initials = selected.map((d) => d.initial).take(2).join('');

    // Add the group as a diary contact with real member list.
    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    _store.add(DiaryContact(
      id: groupId,
      name: groupName,
      relation: '${selected.length} people',
      phone: '',
      initial: initials.isNotEmpty ? initials[0] : 'G',
      avatarColor: AppColors.successGreen,
      isGroup: true,
      members: selected,
      elderMemberId: _elderMemberId,
    ));

    if (!mounted) return;
    // Pop back to previous screen; the group now appears in diaries.
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final connections = _store.diaries.where((d) => !d.isGroup).toList();

    return ListenableBuilder(
      listenable: _store,
      builder: (_, w) {
        return Scaffold(
          backgroundColor: AppColors.ink,
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 18, 12),
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
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 1),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0x9EF5EFE8)),
                        ),
                      ),
                      const Spacer(),
                      Text('Create group',
                          style: AppTypography.label(
                              size: 15,
                              weight: FontWeight.w600,
                              color: AppColors.textMuted)),
                      const Spacer(),
                      const SizedBox(width: 36),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: connections.isEmpty
                    ? _NeedsConnectionsView()
                    : _CreateGroupForm(
                        connections: connections,
                        selectedIds: _selectedIds,
                        nameCtrl: _nameCtrl,
                        creating: _creating,
                        canCreate: _canCreate,
                        elderMemberId: _elderMemberId,
                        onToggle: _toggle,
                        onNameChanged: (_) => setState(() {}),
                        onAutoSuggest: _autoSuggestName,
                        onElderSelected: (id) =>
                            setState(() => _elderMemberId = id),
                        onCreate: _createGroup,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── No connections yet ───────────────────────────────────────────────────────

class _NeedsConnectionsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SaanjhLogo(size: 60),
            const SizedBox(height: 24),
            Text('Start some diaries first.',
                style: AppTypography.title(size: 24),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'You need at least 2 existing diary connections to create a group. Go to Discover to find people first.',
              style: AppTypography.serifItalic(size: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            CtaPrimary(
              label: 'Find people on Saanjh',
              onPressed: () => context.push(AppRoutes.discover),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Group creation form ──────────────────────────────────────────────────────

class _CreateGroupForm extends StatelessWidget {
  final List<DiaryContact> connections;
  final Set<String> selectedIds;
  final TextEditingController nameCtrl;
  final bool creating;
  final bool canCreate;
  final String? elderMemberId;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onAutoSuggest;
  final ValueChanged<String?> onElderSelected;
  final VoidCallback onCreate;

  const _CreateGroupForm({
    required this.connections,
    required this.selectedIds,
    required this.nameCtrl,
    required this.creating,
    required this.canCreate,
    this.elderMemberId,
    required this.onToggle,
    required this.onNameChanged,
    required this.onAutoSuggest,
    required this.onElderSelected,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final selectedCount = selectedIds.length;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, MediaQuery.of(context).padding.bottom + 32),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: AppTypography.title(size: 30, weight: FontWeight.w600)
                  .copyWith(height: 1.1),
              children: [
                const TextSpan(text: 'Create a\n'),
                TextSpan(
                  text: 'family group.',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppColors.emberBright,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select 2 or more people from your existing diaries.',
            style: AppTypography.body(size: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          _Label('SELECT MEMBERS'),
          const SizedBox(height: 10),
          for (final c in connections)
            _MemberTile(
              contact: c,
              selected: selectedIds.contains(c.id),
              onToggle: () {
                onToggle(c.id);
                onAutoSuggest();
              },
            ),
          if (selectedCount > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                '$selectedCount member${selectedCount == 1 ? '' : 's'} selected${selectedCount == 1 ? ' · add 1 more' : ''}',
                style: AppTypography.label(
                    size: 12.5,
                    color: selectedCount >= 2
                        ? AppColors.emberBright
                        : AppColors.textFaint),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _Label('GROUP NAME'),
          const SizedBox(height: 8),
          TextField(
            controller: nameCtrl,
            style: AppTypography.body(size: 15),
            onChanged: onNameChanged,
            decoration: InputDecoration(
              hintText: 'e.g. Family Circle, Kumar Family…',
              hintStyle:
                  AppTypography.body(size: 15, color: AppColors.textFaint),
              filled: true,
              fillColor: AppColors.surfaceTint,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.borderSoft, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: AppColors.emberWarm, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We auto-suggest a name from your selected members.',
            style:
                AppTypography.label(size: 12, color: AppColors.textFaint),
          ),
          // Elder designation — shown when 2+ members selected
          if (selectedIds.length >= 2) ...[
            const SizedBox(height: 24),
            _Label('DESIGNATE AN ELDER (OPTIONAL)'),
            const SizedBox(height: 8),
            Text(
              'The Elder\'s voice carries extra weight in this group.',
              style: AppTypography.body(size: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: connections
                  .where((c) => selectedIds.contains(c.id))
                  .map((c) {
                final isElder = c.id == elderMemberId;
                return GestureDetector(
                  onTap: () => onElderSelected(isElder ? null : c.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isElder
                          ? AppColors.ember.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isElder
                            ? AppColors.emberWarm.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isElder) ...[
                          const Text('👑', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          c.displayName.split(' ').first,
                          style: AppTypography.label(
                            size: 13,
                            color: isElder
                                ? AppColors.emberWarm
                                : AppColors.textMuted,
                            weight: isElder ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 32),
          CtaPrimary(
            label: canCreate
                ? 'Create group with $selectedCount  →'
                : 'Create group',
            loading: creating,
            onPressed: canCreate ? onCreate : null,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppTypography.eyebrow(size: 10, color: AppColors.textFaint));
}

class _MemberTile extends StatelessWidget {
  final DiaryContact contact;
  final bool selected;
  final VoidCallback onToggle;

  const _MemberTile({
    required this.contact,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FlickerStore.instance,
      builder: (_, w) {
        final ps = FlickerStore.instance;
        final streakDays = DiaryStore.instance.streakDays(contact.id);
        final atRisk = DiaryStore.instance.streakAtRisk(contact.id);
        final mutual = ps.isMutualToday(contact.id);

        final Color ringColor;
        final double ringAlpha;
        if (mutual) {
          ringColor = AppColors.successGreen; ringAlpha = 0.60;
        } else if (streakDays > 0) {
          ringColor = AppColors.emberWarm; ringAlpha = 0.30;
        } else {
          ringColor = Colors.transparent; ringAlpha = 0.0;
        }

        return GestureDetector(
          onTap: onToggle,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.ember.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppColors.emberWarm.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.07),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Avatar with streak ring
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        contact.avatarColor,
                        contact.avatarColor.withValues(alpha: 0.68),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: ringAlpha > 0
                        ? Border.all(
                            color: ringColor.withValues(alpha: ringAlpha),
                            width: 2)
                        : null,
                    boxShadow: ringAlpha > 0
                        ? [
                            BoxShadow(
                              color: ringColor.withValues(alpha: ringAlpha * 0.4),
                              blurRadius: 10,
                              spreadRadius: 1,
                            )
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      contact.initial,
                      style: AppTypography.title(size: 19).copyWith(
                          color: Colors.white, fontStyle: FontStyle.italic),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contact.name,
                              style: AppTypography.body(
                                  size: 15, weight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (streakDays > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (atRisk
                                        ? AppColors.destructive
                                        : AppColors.emberWarm)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(atRisk ? '⚠️' : '🔥',
                                      style: const TextStyle(
                                          fontSize: 9, height: 1.2)),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$streakDays',
                                    style: AppTypography.label(
                                      size: 10,
                                      weight: FontWeight.w700,
                                      color: atRisk
                                          ? const Color(0xFFFF8A82)
                                          : AppColors.emberBright,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        contact.relation,
                        style: AppTypography.label(
                            size: 12, color: AppColors.textFaint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.emberWarm : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? AppColors.emberWarm
                          : Colors.white.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

