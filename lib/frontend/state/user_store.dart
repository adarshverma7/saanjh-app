import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';

class UserStore extends ChangeNotifier {
  UserStore._();
  static final UserStore instance = UserStore._();

  String _name = '';
  String _phone = '';
  String _countryCode = '+91';
  String _status = '';
  bool _isParentMode = false;

  static const _kParentMode = 'pref_parent_mode';

  String get name => _name;
  String get phone => _phone;
  String get countryCode => _countryCode;
  String get status => _status;

  /// Full formatted phone for display, e.g. "+91 98765 43210".
  String get displayPhone =>
      _phone.isEmpty ? '' : '$_countryCode $_phone';

  /// First letter of name, uppercase; '?' when no name is set yet.
  String get initial =>
      _name.isEmpty ? '?' : _name.trim()[0].toUpperCase();

  bool get hasName => _name.isNotEmpty;
  bool get hasPhone => _phone.isNotEmpty;
  bool get isParentMode => _isParentMode;

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

  // Consistent color derived from name so the avatar never randomly shifts.
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

  void setStatus(String s) {
    _status = s.trim();
    notifyListeners();
  }

  void setName(String name) {
    _name = name.trim();
    notifyListeners();
  }

  void setPhone(String digits, String countryCode) {
    _phone = digits.trim();
    _countryCode = countryCode;
    notifyListeners();
  }
}
