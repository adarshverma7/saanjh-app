import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../backend/api_client.dart';
import '../theme/app_colors.dart';

class SaanjhContact {
  final String id;
  final String name;
  final String phone;            // E.164 normalised (+91XXXXXXXXXX)
  final String displayPhone;    // formatted for display
  final String initial;
  final Color avatarColor;
  final bool isOnSaanjh;
  final String? saanjhName;     // their Saanjh display name, if on the app
  final String? connectionId;   // backend connection UUID if already connected

  const SaanjhContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.displayPhone,
    required this.initial,
    required this.avatarColor,
    required this.isOnSaanjh,
    this.saanjhName,
    this.connectionId,
  });
}

class ContactsService {
  ContactsService._();
  static final ContactsService instance = ContactsService._();

  List<SaanjhContact>? _cache;

  static const _palette = [
    Color(0xFFE8720C),
    Color(0xFFFF6B8A),
    AppColors.successGreen,
    AppColors.azure,
    AppColors.violet,
    Color(0xFF2EC4B6),
    Color(0xFFF4C430),
    Color(0xFFFF9F0A),
  ];

  Future<PermissionStatus> status() => Permission.contacts.status;

  Future<bool> request() async {
    final result = await Permission.contacts.request();
    return result.isGranted;
  }

  /// Loads device contacts, calls the backend to check which are on Saanjh,
  /// and returns the combined list. Caches the result.
  Future<List<SaanjhContact>> loadContacts() async {
    if (_cache != null) return _cache!;

    final raw = await FlutterContacts.getContacts(withProperties: true);

    // Build normalised phone map: e164 → contact
    final entries = <({String id, String name, String e164, String display})>[];
    for (final c in raw) {
      if (c.phones.isEmpty || c.displayName.trim().isEmpty) continue;
      final e164 = _toE164(c.phones.first.number);
      if (e164 == null) continue;
      entries.add((
        id:      c.id,
        name:    c.displayName.trim(),
        e164:    e164,
        display: _formatDisplay(e164),
      ));
    }

    // Deduplicate by E.164
    final seen = <String>{};
    final unique = entries.where((e) => seen.add(e.e164)).toList();

    // Check which are on Saanjh via backend
    final onSaanjhMap = await _fetchSaanjhMembers(
      unique.map((e) => e.e164).toList(),
    );

    _cache = unique.map((e) {
      final colorIdx = e.name.codeUnits.fold(0, (a, b) => a + b) % _palette.length;
      final info = onSaanjhMap[e.e164];
      final onSaanjh = info != null;
      return SaanjhContact(
        id:           e.id,
        name:         e.name,
        phone:        e.e164,
        displayPhone: e.display,
        initial:      e.name.characters.first.toUpperCase(),
        avatarColor:  _palette[colorIdx],
        isOnSaanjh:   onSaanjh,
        saanjhName:   info?['name'] as String?,
        connectionId: info?['connection_id'] as String?,
      );
    }).toList();

    // Sort: Saanjh members first, then alphabetically
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

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Calls POST /connections/check-contacts with batches of 500.
  /// Returns a map of e164 → {name, connection_id?}.
  Future<Map<String, Map<String, dynamic>>> _fetchSaanjhMembers(
      List<String> phones) async {
    if (phones.isEmpty) return {};

    final result = <String, Map<String, dynamic>>{};

    // Process in batches of 500
    for (var i = 0; i < phones.length; i += 500) {
      final batch = phones.sublist(i, (i + 500).clamp(0, phones.length));
      try {
        final res = await ApiClient.instance.dio.post(
          '/connections/check-contacts',
          data: {'phones': batch},
        );
        final list = (res.data as List<dynamic>?) ?? [];
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          result[map['phone'] as String] = {
            'name': map['name'] as String?,
            'connection_id': map['connection_id'] as String?,
          };
        }
      } catch (_) {
        // Network failure — degrade gracefully (all contacts shown as "not on Saanjh")
      }
    }

    return result;
  }

  /// Converts any phone number format to E.164 (+91XXXXXXXXXX).
  /// Returns null if the number can't be normalised.
  static String? _toE164(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    // Indian 10-digit
    if (digits.length == 10) return '+91$digits';
    // Indian with country code
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    if (digits.length == 13 && digits.startsWith('091')) return '+${digits.substring(1)}';
    // US/Canada
    if (digits.length == 11 && digits.startsWith('1')) return '+$digits';
    if (digits.length == 10) return '+1$digits';
    // International with +
    if (raw.trimLeft().startsWith('+') && digits.length >= 8) return '+$digits';
    // Skip very short or ambiguous
    if (digits.length < 8) return null;
    return null;
  }

  static String _formatDisplay(String e164) {
    if (e164.startsWith('+91') && e164.length == 13) {
      final d = e164.substring(3);
      return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
    }
    if (e164.startsWith('+1') && e164.length == 12) {
      final d = e164.substring(2);
      return '+1 ${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
    }
    return e164;
  }
}
