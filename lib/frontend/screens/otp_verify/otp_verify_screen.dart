import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../backend/auth_api.dart';
import '../../router/app_routes.dart';
import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/onboarding_background.dart';
import '../../widgets/onboarding_top_bar.dart';

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

enum _VerifyState { idle, verifying, success, error }

class _OtpVerifyScreenState extends State<OtpVerifyScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  _VerifyState _state = _VerifyState.idle;
  int _resendSeconds = 30;
  Timer? _resendTimer;
  bool _resendActive = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _startResendTimer();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _resendTimer?.cancel();
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendSeconds = 30;
    _resendActive = false;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) {
          _resendActive = true;
          t.cancel();
        }
      });
    });
  }

  String get _code => _ctrls.map((c) => c.text).join();
  bool get _complete => _code.length == 6;

  void _onDigitInput(int idx, String value) {
    final digit = value.replaceAll(RegExp(r'\D'), '');
    if (digit.isEmpty) {
      if (idx > 0) {
        _nodes[idx - 1].requestFocus();
        _ctrls[idx - 1].clear();
      }
    } else {
      _ctrls[idx].text = digit.characters.last;
      if (idx < 5) {
        _nodes[idx + 1].requestFocus();
      } else {
        _nodes[idx].unfocus();
        if (_complete) _verify();
      }
    }
    setState(() {});
  }

  void _onKeyDown(int idx, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.backspace &&
        _ctrls[idx].text.isEmpty &&
        idx > 0) {
      _nodes[idx - 1].requestFocus();
      _ctrls[idx - 1].clear();
      setState(() {});
    }
  }

  Future<void> _verify() async {
    if (_state == _VerifyState.verifying) return;
    HapticFeedback.lightImpact();
    setState(() => _state = _VerifyState.verifying);

    final verificationId = UserStore.instance.verificationId;
    final result = await AuthApi.instance.verifyOtp(
      verificationId: verificationId,
      smsCode: _code,
    );

    if (!mounted) return;

    if (result == null) {
      HapticFeedback.vibrate();
      setState(() => _state = _VerifyState.error);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      for (final c in _ctrls) { c.clear(); }
      _nodes[0].requestFocus();
      setState(() => _state = _VerifyState.idle);
      return;
    }

    await UserStore.instance.loginWith(result);

    setState(() => _state = _VerifyState.success);
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    context.go(result.isOnboarded ? AppRoutes.home : AppRoutes.nameEntry);
  }

  Future<void> _resend() async {
    if (!_resendActive) return;
    HapticFeedback.selectionClick();
    _startResendTimer();
    setState(() {});
    final phone = '${UserStore.instance.countryCode}${UserStore.instance.phone}';
    await AuthApi.instance.sendOtp(
      phone: phone,
      onCodeSent: (id) => UserStore.instance.setVerificationId(id),
      onError: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: OnboardingBackground()),
          SafeArea(
            child: Column(
              children: [
                OnboardingTopBar(
                  currentStep: 3,
                  totalSteps: 4,
                  onBack: () {
                    HapticFeedback.selectionClick();
                    context.pop();
                  },
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fade(
                          delay: 0.08,
                          child: Text(
                            'STEP 3 — ENTER THE CODE',
                            style: AppTypography.eyebrow(
                              size: 11,
                              color: AppColors.emberBright,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _fade(
                          delay: 0.16,
                          child: Text.rich(
                            TextSpan(
                              style: AppTypography.title(
                                      size: 38, weight: FontWeight.w600)
                                  .copyWith(
                                      height: 1.08,
                                      letterSpacing: -0.015 * 38),
                              children: [
                                const TextSpan(
                                    text: 'Enter the code\nwe just '),
                                TextSpan(
                                  text: 'sent.',
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.emberBright,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _fade(
                          delay: 0.24,
                          child: Row(
                            children: [
                              Text(
                                'Sent to ',
                                style: AppTypography.body(
                                    size: 14.5, color: AppColors.textMuted),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.08),
                                      width: 1),
                                ),
                                child: Text(
                                  UserStore.instance.hasPhone
                                      ? UserStore.instance.displayPhone
                                      : 'your number',
                                  style: AppTypography.label(
                                    size: 14,
                                    weight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  context.pop();
                                },
                                child: Text(
                                  'Edit',
                                  style: AppTypography.label(
                                    size: 13,
                                    weight: FontWeight.w600,
                                    color: AppColors.emberBright,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        _fade(
                          delay: 0.34,
                          child: _OtpRow(
                            ctrls: _ctrls,
                            nodes: _nodes,
                            state: _state,
                            onInput: _onDigitInput,
                            onKey: _onKeyDown,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _fade(
                          delay: 0.42,
                          child: _StatusRow(state: _state),
                        ),
                        const SizedBox(height: 20),
                        _fade(
                          delay: 0.50,
                          child: Center(
                            child: RichText(
                              text: TextSpan(
                                style: AppTypography.label(
                                    size: 13.5,
                                    color: AppColors.textMuted),
                                children: [
                                  const TextSpan(text: 'Didn\'t receive it? '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => _resend(),
                                      child: Text(
                                        _resendActive
                                            ? 'Resend code'
                                            : 'Resend in 0:${_resendSeconds.toString().padLeft(2, '0')}',
                                        style: AppTypography.label(
                                          size: 13.5,
                                          weight: FontWeight.w600,
                                          color: _resendActive
                                              ? AppColors.emberBright
                                              : AppColors.textFaint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        _fade(
                          delay: 0.58,
                          child: CtaPrimary(
                            label: 'Verify  →',
                            loading: _state == _VerifyState.verifying,
                            onPressed: _complete &&
                                    _state != _VerifyState.verifying &&
                                    _state != _VerifyState.success
                                ? _verify
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fade({required double delay, required Widget child}) {
    final interval = Interval(delay, (delay + 0.5).clamp(0.0, 1.0),
        curve: AppMotion.easeOut);
    final anim = CurvedAnimation(parent: _entranceCtrl, curve: interval);
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
            offset: Offset(0, 12 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }
}

class _OtpRow extends StatelessWidget {
  final List<TextEditingController> ctrls;
  final List<FocusNode> nodes;
  final _VerifyState state;
  final void Function(int, String) onInput;
  final void Function(int, KeyEvent) onKey;

  const _OtpRow({
    required this.ctrls,
    required this.nodes,
    required this.state,
    required this.onInput,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) {
        final filled = ctrls[i].text.isNotEmpty;
        Color boxBorder;
        Color boxBg;
        if (state == _VerifyState.error) {
          boxBorder = AppColors.destructive;
          boxBg = const Color(0x10FF453A);
        } else if (state == _VerifyState.success) {
          boxBorder = AppColors.successGreen;
          boxBg = const Color(0x1430D158);
        } else if (filled) {
          boxBorder = AppColors.emberWarm.withValues(alpha: 0.45);
          boxBg = AppColors.ember.withValues(alpha: 0.06);
        } else {
          boxBorder = Colors.white.withValues(alpha: 0.10);
          boxBg = Colors.white.withValues(alpha: 0.04);
        }

        return AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          width: 46,
          height: 56,
          decoration: BoxDecoration(
            color: boxBg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: boxBorder, width: 1.5),
          ),
          child: KeyboardListener(
            focusNode: FocusNode(skipTraversal: true),
            onKeyEvent: (e) => onKey(i, e),
            child: TextField(
              controller: ctrls[i],
              focusNode: nodes[i],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 1,
              textAlign: TextAlign.center,
              style: state == _VerifyState.success
                  ? AppTypography.title(size: 26).copyWith(
                      color: const Color(0xFF7CD992),
                      fontStyle: FontStyle.italic,
                    )
                  : AppTypography.title(size: 26),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) => onInput(i, v),
            ),
          ),
        );
      }),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final _VerifyState state;
  const _StatusRow({required this.state});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    Widget? icon;

    switch (state) {
      case _VerifyState.idle:
        text = 'Auto-detecting from SMS…';
        color = AppColors.textFaint;
        icon = null;
      case _VerifyState.verifying:
        text = 'Verifying your code…';
        color = AppColors.emberBright;
        icon = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(AppColors.emberBright),
          ),
        );
      case _VerifyState.success:
        text = 'Verified! Welcome to Saanjh.';
        color = const Color(0xFF7CD992);
        icon = const Icon(Icons.check_circle_outline,
            size: 14, color: Color(0xFF7CD992));
      case _VerifyState.error:
        text = 'That code didn\'t match. Try again.';
        color = const Color(0xFFFF8A82);
        icon = const Icon(Icons.error_outline, size: 14, color: Color(0xFFFF8A82));
    }

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon, const SizedBox(width: 6)],
          Text(text, style: AppTypography.label(size: 13, color: color)),
        ],
      ),
    );
  }
}
