import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameCtrl;
  bool _saving = false;
  // Tracks the typed initial so the avatar updates live.
  String _liveInitial = '?';

  @override
  void initState() {
    super.initState();
    final stored = UserStore.instance.name;
    _nameCtrl = TextEditingController(text: stored);
    _liveInitial = _computeInitial(stored);
    _nameCtrl.addListener(() {
      final i = _computeInitial(_nameCtrl.text);
      if (i != _liveInitial) setState(() => _liveInitial = i);
    });
  }

  String _computeInitial(String text) {
    final t = text.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return; // don't save blank name
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    UserStore.instance.setName(name);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() => _saving = false);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  Text('Profile',
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => Container(
                          decoration: const BoxDecoration(
                            color: AppColors.modalSurface,
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20)),
                          ),
                          child: SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 14),
                                Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ListTile(
                                  leading: const Icon(Icons.camera_alt_rounded,
                                      color: AppColors.emberWarm),
                                  title: Text('Take photo',
                                      style: AppTypography.body(size: 15)),
                                  onTap: () => Navigator.pop(context),
                                ),
                                ListTile(
                                  leading: const Icon(
                                      Icons.photo_library_rounded,
                                      color: AppColors.emberWarm),
                                  title: Text('Choose from gallery',
                                      style: AppTypography.body(size: 15)),
                                  onTap: () => Navigator.pop(context),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline_rounded,
                                      color: AppColors.destructive),
                                  title: Text('Remove photo',
                                      style: AppTypography.body(
                                          size: 15,
                                          color: AppColors.destructive)),
                                  onTap: () => Navigator.pop(context),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.emberGradient,
                          ),
                          child: Center(
                            child: Text(_liveInitial,
                                style: AppTypography.display(size: 44)
                                    .copyWith(
                                        color: Colors.white,
                                        fontStyle: FontStyle.italic)),
                          ),
                        ),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.ink,
                            border: Border.all(
                                color: AppColors.ink.withValues(alpha: 0.8),
                                width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              size: 14, color: AppColors.emberWarm),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _FieldGroup(children: [
                    _FieldTile(
                      label: 'Display name',
                      child: TextField(
                        controller: _nameCtrl,
                        style: AppTypography.body(size: 15),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Your name',
                          hintStyle: AppTypography.body(
                              size: 15, color: AppColors.textFaint),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    _FieldTile(
                      label: 'Phone number',
                      child: Text(
                        UserStore.instance.hasPhone
                            ? UserStore.instance.displayPhone
                            : 'Not set',
                        style: AppTypography.body(
                            size: 15,
                            color: UserStore.instance.hasPhone
                                ? AppColors.textMuted
                                : AppColors.textFaint),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _FieldGroup(children: [
                    _FieldTile(
                      label: 'App language',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('English',
                              style: AppTypography.body(
                                  size: 15, color: AppColors.textMuted)),
                          Icon(Icons.chevron_right_rounded,
                              size: 16, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                    _FieldTile(
                      label: 'Parent UI language',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('हिंदी',
                              style: AppTypography.body(
                                  size: 15, color: AppColors.textMuted)),
                          Icon(Icons.chevron_right_rounded,
                              size: 16, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 32),
                  CtaPrimary(
                    label: 'Save changes',
                    loading: _saving,
                    onPressed: _save,
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

class _FieldGroup extends StatelessWidget {
  final List<Widget> children;
  const _FieldGroup({required this.children});

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
        children: children.asMap().entries.map((e) {
          return Column(
            children: [
              e.value,
              if (e.key < children.length - 1)
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.05),
                  indent: 16,
                  endIndent: 0,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldTile({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTypography.caption(size: 10.5, color: AppColors.textFaint)
                  .copyWith(letterSpacing: 0.12 * 10.5)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
