import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_auth/smart_auth.dart';

import '../../../backend/auth_api.dart';
import '../../router/app_routes.dart';
import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/onboarding_background.dart';
import '../../widgets/onboarding_top_bar.dart';

class PhoneNumberScreen extends StatefulWidget {
  const PhoneNumberScreen({super.key});

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _Country {
  final String name;
  final String flag;
  final String code;
  final String iso;
  final int length;
  const _Country(this.name, this.flag, this.code, this.iso, this.length);
}

const _countries = [
  _Country('India', '🇮🇳', '+91', 'IN', 10),
  _Country('United States', '🇺🇸', '+1', 'US', 10),
  _Country('United Kingdom', '🇬🇧', '+44', 'GB', 10),
  _Country('Canada', '🇨🇦', '+1', 'CA', 10),
  _Country('Australia', '🇦🇺', '+61', 'AU', 9),
  _Country('UAE', '🇦🇪', '+971', 'AE', 9),
  _Country('Singapore', '🇸🇬', '+65', 'SG', 8),
  _Country('Germany', '🇩🇪', '+49', 'DE', 11),
  _Country('Malaysia', '🇲🇾', '+60', 'MY', 10),
  _Country('Saudi Arabia', '🇸🇦', '+966', 'SA', 9),
];

class _PhoneNumberScreenState extends State<PhoneNumberScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  final _phoneCtrl = TextEditingController();
  final _focusNode = FocusNode();
  _Country _country = _countries[0];
  bool _continuing = false;
  String? _errorMessage;

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
    // Suggest saved device number after entrance animation completes
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPhoneHint());
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _phoneCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _requestPhoneHint() async {
    final result = await SmartAuth.instance.requestPhoneNumberHint();
    if (!mounted || !result.hasData || result.data == null) return;
    _showPhoneSuggestionSheet(result.data!);
  }

  void _showPhoneSuggestionSheet(String e164) {
    // Match country code — sort descending by length to avoid partial matches
    final sorted = [..._countries]
      ..sort((a, b) => b.code.length.compareTo(a.code.length));
    _Country? matched;
    String digits = '';
    for (final c in sorted) {
      if (e164.startsWith(c.code)) {
        matched = c;
        digits = e164.substring(c.code.length);
        break;
      }
    }
    // Only show if we recognised the country and digits look valid
    if (matched == null || digits.isEmpty || digits.length < 6) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhoneSuggestionSheet(
        country: matched!,
        digits: digits,
        onUse: () {
          Navigator.pop(context);
          setState(() {
            _country = matched!;
            _phoneCtrl.text = digits;
          });
        },
        onDismiss: () => Navigator.pop(context),
      ),
    );
  }

  bool get _isValid {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    return digits.length == _country.length;
  }

  void _onPhoneChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > _country.length) {
      final trimmed = digits.substring(0, _country.length);
      _phoneCtrl.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
    }
    setState(() {});
  }

  Future<void> _continue() async {
    if (!_isValid || _continuing) return;
    HapticFeedback.lightImpact();
    setState(() { _continuing = true; _errorMessage = null; });

    final phone = '${_country.code}${_phoneCtrl.text.trim()}';
    UserStore.instance.setPhone(_phoneCtrl.text, _country.code);

    // Timeout safety — if Firebase doesn't respond in 30s, unblock the button
    bool responded = false;

    Future.delayed(const Duration(seconds: 30), () {
      if (!responded && mounted) {
        setState(() {
          _continuing = false;
          _errorMessage = 'Timed out. Check your connection and try again.';
        });
      }
    });

    await AuthApi.instance.sendOtp(
      phone: phone,
      onCodeSent: (verificationId) {
        responded = true;
        UserStore.instance.setVerificationId(verificationId);
        if (mounted) {
          context.push(AppRoutes.otpVerify);
          setState(() => _continuing = false);
        }
      },
      onError: (error) {
        responded = true;
        if (mounted) setState(() { _continuing = false; _errorMessage = error; });
      },
      onAutoVerified: (credential) async {
        responded = true;
        final result = await AuthApi.instance.verifyWithCredential(credential);
        if (result != null && mounted) {
          await UserStore.instance.loginWith(result);
          if (!mounted) return;
          context.go(result.isOnboarded ? AppRoutes.home : AppRoutes.nameEntry);
        }
      },
    );
  }

  void _showCountryPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountryPickerSheet(
        selected: _country,
        onSelect: (c) {
          setState(() => _country = c);
          Navigator.pop(context);
        },
      ),
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
                  currentStep: 2,
                  totalSteps: 4,
                  onBack: () {
                    HapticFeedback.selectionClick();
                    context.pop();
                  },
                ),
                Expanded(
                  child: _StaggerFade(
                    controller: _entranceCtrl,
                    delay: 0.05,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StaggerFade(
                            controller: _entranceCtrl,
                            delay: 0.08,
                            child: Text(
                              'STEP 2 — VERIFY IT\'S YOU',
                              style: AppTypography.eyebrow(
                                size: 11,
                                color: AppColors.emberBright,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _StaggerFade(
                            controller: _entranceCtrl,
                            delay: 0.16,
                            child: Text.rich(
                              TextSpan(
                                style: AppTypography.title(size: 38, weight: FontWeight.w600)
                                    .copyWith(height: 1.08, letterSpacing: -0.015 * 38),
                                children: [
                                  const TextSpan(text: 'What\'s your\nphone '),
                                  TextSpan(
                                    text: 'number?',
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
                          _StaggerFade(
                            controller: _entranceCtrl,
                            delay: 0.24,
                            child: Text(
                              'We\'ll text you a 6-digit code. No password — your number is the key.',
                              style: AppTypography.body(size: 15, color: AppColors.textMuted),
                            ),
                          ),
                          const SizedBox(height: 32),
                          _StaggerFade(
                            controller: _entranceCtrl,
                            delay: 0.34,
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: _showCountryPicker,
                                  child: AnimatedContainer(
                                    duration: AppMotion.fast,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceTint,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.borderSoft,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_country.flag,
                                            style: const TextStyle(fontSize: 18)),
                                        const SizedBox(width: 8),
                                        Text(
                                          _country.code,
                                          style: AppTypography.body(
                                            size: 16,
                                            weight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 16,
                                          color: AppColors.textFaint,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _phoneCtrl,
                                    focusNode: _focusNode,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    style: AppTypography.body(
                                      size: 17,
                                      weight: FontWeight.w500,
                                    ).copyWith(letterSpacing: 0.02 * 17),
                                    decoration: InputDecoration(
                                      hintText: '98765 43210',
                                      hintStyle: AppTypography.body(
                                        size: 17,
                                        color: AppColors.textFaint,
                                      ),
                                      filled: true,
                                      fillColor: AppColors.surfaceTint,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: AppColors.borderSoft,
                                          width: 1.5,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: AppColors.emberWarm,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: _onPhoneChanged,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _continue(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _StaggerFade(
                            controller: _entranceCtrl,
                            delay: 0.44,
                            child: _PrivacyNote(),
                          ),
                          const SizedBox(height: 32),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0x15FF453A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0x40FF453A)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, size: 14, color: Color(0xFFFF8A82)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: AppTypography.label(size: 12.5, color: const Color(0xFFFF8A82)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _StaggerFade(
                            controller: _entranceCtrl,
                            delay: 0.54,
                            child: CtaPrimary(
                              label: 'Send verification code  →',
                              loading: _continuing,
                              onPressed: _isValid ? _continue : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _StaggerFade(
                            controller: _entranceCtrl,
                            delay: 0.62,
                            child: Center(
                              child: Text(
                                'By continuing you agree to Saanjh\'s Terms & Privacy Policy.',
                                textAlign: TextAlign.center,
                                style: AppTypography.label(
                                  size: 11.5,
                                  color: AppColors.textFaint,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x0D30D158),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0x2930D158),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: Icon(
                Icons.shield_outlined,
                size: 15,
                color: Color(0xFF7CD992),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR NUMBER STAYS YOURS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.08 * 10.5,
                    color: const Color(0xFF7CD992),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'End-to-end encrypted. Used only to verify it\'s really you. Never sold or shared.',
                  style: AppTypography.label(size: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  final _Country selected;
  final ValueChanged<_Country> onSelect;

  const _CountryPickerSheet({
    required this.selected,
    required this.onSelect,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_Country> _filtered = _countries;

  void _onSearch(String q) {
    final lower = q.toLowerCase().trim();
    setState(() {
      _filtered = lower.isEmpty
          ? _countries
          : _countries
              .where((c) =>
                  c.name.toLowerCase().contains(lower) ||
                  c.code.contains(lower))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0x1AFFFFFF), width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose your country',
                    style: AppTypography.title(size: 22)),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchCtrl,
                  style: AppTypography.body(size: 14),
                  decoration: InputDecoration(
                    hintText: 'Search countries…',
                    hintStyle: AppTypography.body(
                        size: 14, color: AppColors.textFaint),
                    filled: true,
                    fillColor: AppColors.surfaceTint,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppColors.borderSoft, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppColors.emberWarm, width: 1),
                    ),
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: AppColors.textFaint),
                  ),
                  onChanged: _onSearch,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              physics: const BouncingScrollPhysics(),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final c = _filtered[i];
                final isSelected = c.iso == widget.selected.iso;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onSelect(c);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.ember.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text(c.flag, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            c.name,
                            style: AppTypography.body(
                                size: 14, weight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          c.code,
                          style: AppTypography.body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_rounded,
                              size: 16, color: AppColors.emberWarm),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

class _PhoneSuggestionSheet extends StatelessWidget {
  final _Country country;
  final String digits;
  final VoidCallback onUse;
  final VoidCallback onDismiss;

  const _PhoneSuggestionSheet({
    required this.country,
    required this.digits,
    required this.onUse,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text('Use this number?', style: AppTypography.title(size: 20)),
          const SizedBox(height: 6),
          Text(
            'We found a number saved on your device.',
            style: AppTypography.body(size: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onUse();
            },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.ember.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.emberWarm.withValues(alpha: 0.30),
                    width: 1.5),
              ),
              child: Row(
                children: [
                  Text(country.flag,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${country.code} $digits',
                          style: AppTypography.body(
                              size: 18, weight: FontWeight.w600),
                        ),
                        Text(
                          country.name,
                          style: AppTypography.label(
                              size: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.check_circle_outline_rounded,
                      color: AppColors.emberWarm, size: 22),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              onDismiss();
            },
            child: Text(
              'Enter number manually',
              style: AppTypography.label(
                  size: 14,
                  color: AppColors.textMuted,
                  weight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaggerFade extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Widget child;

  const _StaggerFade({
    required this.controller,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final interval =
        Interval(delay, (delay + 0.5).clamp(0.0, 1.0), curve: AppMotion.easeOut);
    final anim = CurvedAnimation(parent: controller, curve: interval);
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
