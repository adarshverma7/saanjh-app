// The page classes below set fixed transition params via an explicit super()
// call, which is incompatible with super-parameter syntax for `child`.
// ignore_for_file: use_super_parameters
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_motion.dart';

/// Page transitions with a modern "shared axis" feel: the incoming page fades
/// up with a touch of scale while the outgoing page fades and eases back, so
/// navigation reads as one continuous, buttery motion rather than a hard cut.
///
/// Drop-in replacement for MaterialPage in the GoRouter route table:
///   pageBuilder: (_, s) => const SaanjhPage(child: SomeScreen()),
class SaanjhPage<T> extends CustomTransitionPage<T> {
  const SaanjhPage({
    required Widget child,
    LocalKey? key,
    String? name,
    Object? arguments,
    String? restorationId,
  }) : super(
          child: child,
          key: key,
          name: name,
          arguments: arguments,
          restorationId: restorationId,
          transitionDuration: AppMotion.page,
          reverseTransitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: sharedAxis,
        );

  static Widget sharedAxis(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final inCurve = CurvedAnimation(parent: animation, curve: AppMotion.easeOut);
    final outCurve =
        CurvedAnimation(parent: secondaryAnimation, curve: AppMotion.easeOut);

    return AnimatedBuilder(
      animation: Listenable.merge([inCurve, outCurve]),
      builder: (context, _) {
        final enter = inCurve.value; // 0 -> 1 as this page arrives
        final leave = outCurve.value; // 0 -> 1 as this page is covered
        final scale = (0.98 + 0.02 * enter) * (1 - 0.02 * leave);
        final dy = (1 - enter) * 20.0 + leave * -8.0;
        return Opacity(
          opacity: enter * (1 - 0.35 * leave),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

/// A modal-style transition for sheets/overlays pushed as full routes: slides
/// up from the bottom with an eased settle.
class SaanjhModalPage<T> extends CustomTransitionPage<T> {
  const SaanjhModalPage({
    required Widget child,
    LocalKey? key,
    String? name,
    Object? arguments,
    String? restorationId,
  }) : super(
          child: child,
          key: key,
          name: name,
          arguments: arguments,
          restorationId: restorationId,
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: modalSlide,
        );

  static Widget modalSlide(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.easeOut);
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
          .animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}
