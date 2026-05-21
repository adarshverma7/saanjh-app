import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';

class OccasionPlanScreen extends StatefulWidget {
  const OccasionPlanScreen({super.key});

  @override
  State<OccasionPlanScreen> createState() => _OccasionPlanScreenState();
}

class _GiftBookCard extends StatefulWidget {
  final String? occasionId;
  const _GiftBookCard({this.occasionId});

  @override
  State<_GiftBookCard> createState() => _GiftBookCardState();
}

class _GiftBookCardState extends State<_GiftBookCard> {
  bool _pressed = false;

  // Only surface the gift card for emotionally significant occasions.
  bool get _show => widget.occasionId == 'birthday' ||
      widget.occasionId == 'anniversary' ||
      widget.occasionId == 'festival' ||
      widget.occasionId == null;

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        context.push(AppRoutes.memoryBook, extra: {'isGift': true});
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _pressed
              ? AppColors.ember.withValues(alpha: 0.10)
              : AppColors.ember.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _pressed
                ? AppColors.emberWarm.withValues(alpha: 0.40)
                : AppColors.emberWarm.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Text('🎁', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gift a Memory Book',
                    style: AppTypography.body(
                        size: 14.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Printed voice memories, delivered. ₹499 with wrapping.',
                    style: AppTypography.caption(
                        size: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _Occasion {
  final String id;
  final String emoji;
  final String name;
  final String hint;
  const _Occasion(this.id, this.emoji, this.name, this.hint);
}

const _occasions = [
  _Occasion('birthday', '🎂', 'Birthday', 'Leave a voice note 1 day before'),
  _Occasion('anniversary', '💕', 'Anniversary', 'Whisper something sweet'),
  _Occasion('festival', '🪔', 'Festival', 'Diwali, Eid, Holi, Christmas…'),
  _Occasion('travel', '✈️', 'Travelling', 'Let them know you\'re safe'),
  _Occasion('milestone', '🌟', 'Milestone', 'New job, graduation, move'),
  _Occasion('other', '✨', 'Something else', 'Any moment worth marking'),
];

class _OccasionPlanScreenState extends State<OccasionPlanScreen> {
  String? _selected;
  DateTime? _date;
  bool _scheduling = false;

  Future<void> _setReminder() async {
    HapticFeedback.lightImpact();
    setState(() => _scheduling = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    context.pop();
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
                  Text('Plan an occasion',
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
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  24, 8, 24, MediaQuery.of(context).padding.bottom + 24),
              physics: const BouncingScrollPhysics(),
              children: [
                Text.rich(
                  TextSpan(
                    style: AppTypography.title(size: 32, weight: FontWeight.w600)
                        .copyWith(height: 1.1),
                    children: [
                      const TextSpan(text: 'Mark a special\n'),
                      TextSpan(
                        text: 'moment.',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: AppColors.emberBright,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "We'll remind you to record a voice note the day before — so they always feel remembered.",
                  style: AppTypography.body(size: 14.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 28),
                Text('WHAT IS THE OCCASION?',
                    style: AppTypography.eyebrow(
                        size: 10, color: AppColors.textFaint)),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.4,
                  children: _occasions.map((o) {
                    final sel = _selected == o.id;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = o.id);
                      },
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.ember.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: sel
                                ? AppColors.emberWarm.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.07),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(o.emoji,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(o.name,
                                  style: AppTypography.body(
                                    size: 13,
                                    weight: FontWeight.w500,
                                    color: sel
                                        ? AppColors.emberBright
                                        : AppColors.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                Text('WHEN IS IT?',
                    style: AppTypography.eyebrow(
                        size: 10, color: AppColors.textFaint)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      builder: (ctx, child) => Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: AppColors.emberWarm,
                            surface: AppColors.modalSurface,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (d != null && mounted) setState(() => _date = d);
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: _date != null
                          ? AppColors.ember.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _date != null
                            ? AppColors.emberWarm.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.07),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_rounded,
                            size: 18,
                            color: _date != null
                                ? AppColors.emberWarm
                                : AppColors.textFaint),
                        const SizedBox(width: 12),
                        Text(
                          _date != null
                              ? '${_date!.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][_date!.month - 1]} ${_date!.year}'
                              : 'Choose a date',
                          style: AppTypography.body(
                            size: 15,
                            color: _date != null
                                ? AppColors.text
                                : AppColors.textFaint,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: AppColors.textFaint),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                CtaPrimary(
                  label: 'Set reminder',
                  loading: _scheduling,
                  onPressed: _selected != null && _date != null
                      ? _setReminder
                      : null,
                ),
                const SizedBox(height: 16),
                _GiftBookCard(occasionId: _selected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
