import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/api_client.dart';
import '../../backend/auth_api.dart';
import '../theme/app_colors.dart';

class UserStore extends ChangeNotifier {
  UserStore._();
  static final UserStore instance = UserStore._();

  // ── Auth state ─────────────────────────────────────────────────────────────
  bool _isLoggedIn   = false;
  bool _isOnboarded  = false;
  String _userId     = '';

  bool get isLoggedIn   => _isLoggedIn;
  bool get isOnboarded  => _isOnboarded;
  String get userId     => _userId;

  // ── Profile state ──────────────────────────────────────────────────────────
  String _name        = '';
  String _phone       = '';
  String _countryCode = '+91';
  String _status      = '';
  bool   _isParentMode = false;

  static const _kParentMode = 'pref_parent_mode';

  String get name        => _name;
  String get phone       => _phone;
  String get countryCode => _countryCode;
  String get status      => _status;

  String get displayPhone =>
      _phone.isEmpty ? '' : '$_countryCode $_phone';

  String get initial =>
      _name.isEmpty ? '?' : _name.trim()[0].toUpperCase();

  bool get hasName  => _name.isNotEmpty;
  bool get hasPhone => _phone.isNotEmpty;
  bool get isParentMode => _isParentMode;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Call once at app startup to restore session.
  Future<void> init() async {
    _isLoggedIn = await ApiClient.instance.isLoggedIn;
    if (_isLoggedIn) {
      _userId = await ApiClient.instance.userId ?? '';
    }
    await loadPrefs();
    notifyListeners();
  }

  // ── Auth actions ───────────────────────────────────────────────────────────

  /// Call after successful OTP verification.
  Future<void> loginWith(AuthResult result) async {
    await ApiClient.instance.saveTokens(
      accessToken:  result.accessToken,
      refreshToken: result.refreshToken,
      userId:       result.userId,
    );
    _isLoggedIn  = true;
    _isOnboarded = result.isOnboarded;
    _userId      = result.userId;
    notifyListeners();
  }

  Future<void> logout() async {
    await AuthApi.instance.logout(_userId);
    _isLoggedIn  = false;
    _isOnboarded = false;
    _userId      = '';
    _name        = '';
    notifyListeners();
  }

  // ── Prefs ──────────────────────────────────────────────────────────────────

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_kParentMode) ?? false;
    if (v == _isParentMode) return;
    _isParentMode = v;
    notifyListeners();
  }

  Future<void> setParentMode(bool value) async {
    _isParentMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kParentMode, value);
    notifyListeners();
  }

  void setStatus(String s) {
    _status = s.trim();
    notifyListeners();
  }

  void setName(String name) {
    _name = name.trim();
    notifyListeners();
  }

  void setPhone(String digits, String countryCode) {
    _phone       = digits.trim();
    _countryCode = countryCode;
    notifyListeners();
  }

  void setOnboarded(bool value) {
    _isOnboarded = value;
    notifyListeners();
  }

  // ── Avatar color ───────────────────────────────────────────────────────────

  static const _avatarPalette = [
    AppColors.ember,
    AppColors.successGreen,
    AppColors.azure,
    AppColors.violet,
    Color(0xFF6B9E6B),
    Color(0xFFFF6B8A),
    Color(0xFFFF9F0A),
  ];

  Color get avatarColor {
    if (_name.isEmpty) return AppColors.ember;
    final hash = _name.codeUnits.fold(0, (a, c) => a + c);
    return _avatarPalette[hash % _avatarPalette.length];
  }
}
