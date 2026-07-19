import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/api_client.dart';
import '../../backend/auth_api.dart';
import '../services/media_cache_service.dart';
import '../theme/app_colors.dart';
import 'diary_store.dart';

class UserStore extends ChangeNotifier {
  UserStore._();
  static final UserStore instance = UserStore._();

  // ── Auth state ─────────────────────────────────────────────────────────────
  bool _isLoggedIn   = false;
  bool _isOnboarded  = false;
  String _userId     = '';
  String _verificationId = ''; // Firebase phone auth verification ID

  bool get isLoggedIn       => _isLoggedIn;
  bool get isOnboarded      => _isOnboarded;
  String get userId         => _userId;
  String get verificationId => _verificationId;

  void setVerificationId(String id) {
    _verificationId = id;
  }

  // ── Profile state ──────────────────────────────────────────────────────────
  String _name        = '';
  String _phone       = '';
  String _countryCode = '+91';
  String _status      = '';
  bool   _isSimpleMode = false;

  static const _kIsLoggedIn  = 'pref_is_logged_in';
  static const _kSimpleMode  = 'pref_simple_mode';
  static const _kIsOnboarded = 'pref_is_onboarded';
  static const _kName        = 'pref_name';

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
  bool get isSimpleMode => _isSimpleMode;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Call once at app startup to restore session.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLoggedIn = prefs.getBool(_kIsLoggedIn) ?? false;
      if (_isLoggedIn) {
        _userId = await ApiClient.instance.userId ?? '';
      }
    } catch (_) {
      _isLoggedIn = false;
      _userId = '';
    }
    await loadPrefs();
    notifyListeners();
  }

  Future<void> _saveLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsLoggedIn, value);
  }

  Future<void> _saveOnboarded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsOnboarded, value);
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
    await _saveLoggedIn(true);
    await _saveOnboarded(result.isOnboarded);
    // Restore name from server for returning users
    if (result.name != null && result.name!.isNotEmpty) {
      await setName(result.name!);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await AuthApi.instance.logout(_userId);
    _isLoggedIn  = false;
    _isOnboarded = false;
    _userId      = '';
    _name        = '';
    _phone       = '';
    _countryCode = '+91';
    await _saveLoggedIn(false);
    await _saveOnboarded(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kName);
    await ApiClient.instance.clearTokens();
    // Sign-out wipes the offline cache: entries + downloaded media. It is
    // rebuilt by syncing from the backend after the next login.
    await DiaryStore.instance.clearEntryCache();
    await MediaCacheService.instance.clear();
    DiaryStore.instance.reset();
    notifyListeners();
  }

  // ── Prefs ──────────────────────────────────────────────────────────────────

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isOnboarded  = prefs.getBool(_kIsOnboarded)   ?? false;
    _isSimpleMode = prefs.getBool(_kSimpleMode)     ?? false;
    _name         = prefs.getString(_kName)         ?? '';
    notifyListeners();
  }

  Future<void> setSimpleMode(bool value) async {
    _isSimpleMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSimpleMode, value);
    notifyListeners();
  }

  void setStatus(String s) {
    _status = s.trim();
    notifyListeners();
  }

  Future<void> setName(String name) async {
    _name = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, _name);
    notifyListeners();
  }

  void setPhone(String digits, String countryCode) {
    _phone       = digits.trim();
    _countryCode = countryCode;
    notifyListeners();
  }

  Future<void> setOnboarded(bool value) async {
    _isOnboarded = value;
    await _saveOnboarded(value);
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
