import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// The user's avatar as a circle: shows the network photo when [avatarUrl] is
/// set, otherwise the [initial] on a gradient/solid fill. Falls back to the
/// initial if the image fails to load (e.g. an expired signed URL).
///
/// Badges (edit pencil, camera) are intentionally left to the caller's Stack so
/// each screen can position its own.
class ProfileAvatar extends StatelessWidget {
  final double size;
  final String? avatarUrl;
  final String initial;

  /// Fill used when there is no photo. Provide [gradient] or [solidColor].
  final Gradient? gradient;
  final Color? solidColor;
  final double? initialFontSize;
  final List<BoxShadow>? shadow;

  const ProfileAvatar({
    super.key,
    required this.size,
    required this.avatarUrl,
    required this.initial,
    this.gradient,
    this.solidColor,
    this.initialFontSize,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (avatarUrl ?? '').isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : (gradient ?? AppColors.emberGradient),
        color: hasPhoto ? null : solidColor,
        boxShadow: shadow,
      ),
      child: hasPhoto
          ? ClipOval(
              child: Image.network(
                avatarUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initial(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _initial();
                },
              ),
            )
          : _initial(),
    );
  }

  Widget _initial() {
    return Center(
      child: Text(
        initial,
        style: AppTypography.display(size: initialFontSize ?? size * 0.48)
            .copyWith(color: Colors.white, fontStyle: FontStyle.italic),
      ),
    );
  }
}
