import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

class SaanjhDialog {
  SaanjhDialog._();

  /// Shows a destructive confirmation dialog (Cancel / [confirmLabel]).
  ///
  /// Returns `true` when the user confirms, `false` when they cancel or
  /// dismiss by tapping the barrier. Always check `mounted` after awaiting.
  static Future<bool> showDestructive(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
  }) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: cancelLabel,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: AppMotion.fast,
      transitionBuilder: (_, anim, secondAnim, child) {
        final scale = Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: AppMotion.easeSpring),
        );
        final fade = CurvedAnimation(parent: anim, curve: AppMotion.easeOut);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      pageBuilder: (ctx, _, secondAnim) => _SaanjhDialogWidget(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
    );
    return result ?? false;
  }
}

// ─── Dialog widget ────────────────────────────────────────────────────────────

class _SaanjhDialogWidget extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;

  const _SaanjhDialogWidget({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: AppColors.modalSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.09),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
              child: Text(title, style: AppTypography.title(size: 21)),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text(
                body,
                style: AppTypography.body(
                    size: 14.5, color: AppColors.textMuted),
              ),
            ),
            // Divider
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
            // Action row
            IntrinsicHeight(
              child: Row(
                children: [
                  // Cancel
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                          ),
                        ),
                      ),
                      child: Text(
                        cancelLabel,
                        style: AppTypography.label(
                            size: 15, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  // Vertical divider
                  Container(
                    width: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  // Confirm (destructive)
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            bottomRight: Radius.circular(24),
                          ),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: AppTypography.label(
                          size: 15,
                          weight: FontWeight.w600,
                          color: AppColors.destructive,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
