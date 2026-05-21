import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class SaanjhSheet extends StatelessWidget {
  final String? title;
  final Widget child;
  final double maxHeightFraction;

  const SaanjhSheet({
    super.key,
    this.title,
    required this.child,
    this.maxHeightFraction = 0.82,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.of(context).size.height * maxHeightFraction,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.modalSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border:
              Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Optional title
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Text(title!,
                    style: AppTypography.title(size: 20)),
              ),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: child,
              ),
            ),

            // Bottom safe area padding
            SafeArea(
              top: false,
              child: const SizedBox(height: 8),
            ),
          ],
        ),
      ),
    );
  }
}
