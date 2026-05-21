import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../theme/app_colors.dart';
import 'package:permission_handler/permission_handler.dart';

class SaanjhContact {
  final String id;
  final String name;
  final String phone;
  final String initial;
  final Color avatarColor;
  final bool isOnSaanjh;

  const SaanjhContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.initial,
    required this.avatarColor,
    required this.isOnSaanjh,
  });
}

class ContactsService {
  ContactsService._();
  static final ContactsService instance = ContactsService._();

  List<SaanjhContact>? _cache;

  static const _palette = [
    Color(0xFFE8720C), // ember
    Color(0xFFFF6B8A), // rose
    AppColors.successGreen, // jade
    AppColors.azure, // sky
    AppColors.violet, // dusk
    Color(0xFF2EC4B6), // teal
    Color(0xFFF4C430), // gold
    Color(0xFFFF9F0A), // amber
  ];

  // Check current permission status without prompting.
  Future<PermissionStatus> status() => Permission.contacts.status;

  // Request permission and return whether it was granted.
  Future<bool> request() async {
    final result = await Permission.contacts.request();
    return result.isGranted;
  }

  // Load and cache contacts. Returns empty list if permission denied.
  Future<List<SaanjhContact>> loadContacts() async {
    if (_cache != null) return _cache!;

    final contacts = await FlutterContacts.getContacts(withProperties: true);

    _cache = contacts
        .where((c) => c.phones.isNotEmpty && c.displayName.trim().isNotEmpty)
        .map((c) {
          final name = c.displayName.trim();
          final phone = _formatPhone(c.phones.first.number);
          final initial = name.characters.first.toUpperCase();
          final colorIdx = name.codeUnits.fold(0, (a, b) => a + b) % _palette.length;
          final isOnSaanjh = _simulateSaanjhMembership(name, phone);
          return SaanjhContact(
            id: c.id,
            name: name,
            phone: phone,
            initial: initial,
            avatarColor: _palette[colorIdx],
            isOnSaanjh: isOnSaanjh,
          );
        })
        .toList();

    // Sort: Saanjh members first, then alphabetically within each group.
    _cache!.sort((a, b) {
      if (a.isOnSaanjh && !b.isOnSaanjh) return -1;
      if (!a.isOnSaanjh && b.isOnSaanjh) return 1;
      return a.name.compareTo(b.name);
    });

    return _cache!;
  }

  void clearCache() => _cache = null;

  List<SaanjhContact> get cachedOnSaanjh =>
      (_cache ?? []).where((c) => c.isOnSaanjh).toList();

  List<SaanjhContact> get cachedToInvite =>
      (_cache ?? []).where((c) => !c.isOnSaanjh).toList();

  // Deterministically decide if a contact is "on Saanjh".
  // NOTE: phone is stored unmasked so digit search works correctly.
  // ~1 in 3 contacts will be marked as on Saanjh.
  static bool _simulateSaanjhMembership(String name, String phone) {
    final hash = name.codeUnits.fold(0, (a, b) => a + b) +
        phone.replaceAll(RegExp(r'\D'), '').length;
    return hash % 3 == 0;
  }

  static String _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    // Indian number: 10 digits or 12 digits starting with 91
    if (digits.length == 10) {
      return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      final d = digits.substring(2);
      return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
    }
    if (digits.length == 13 && digits.startsWith('091')) {
      final d = digits.substring(3);
      return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
    }
    // US/Canada: 10 digits with country code 1
    if (digits.length == 11 && digits.startsWith('1')) {
      final d = digits.substring(1);
      return '+1 ${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
    }
    // Fallback: just return the raw number as stored in contacts
    return raw.trim();
  }
}
