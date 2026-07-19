import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../backend/connections_api.dart';
import '../../router/app_routes.dart';
import '../../services/contacts_service.dart';
import '../../state/diary_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/saanjh_logo.dart';
import '../../widgets/motion/saanjh_reveal.dart';
import '../../widgets/saanjh_shimmer.dart';

enum _DiscoverState { checking, permissionNeeded, permissionDenied, loading, loaded }

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _svc = ContactsService.instance;
  final _store = DiaryStore.instance;

  _DiscoverState _state = _DiscoverState.checking;
  List<SaanjhContact> _onSaanjh = [];
  List<SaanjhContact> _toInvite = [];
  String? _toast;
  String _searchQuery = '';
  // Phone numbers currently being connected to the backend.
  final Set<String> _connecting = {};

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await _svc.status();
    if (!mounted) return;

    if (status.isGranted) {
      await _loadContacts();
    } else if (status.isPermanentlyDenied) {
      setState(() => _state = _DiscoverState.permissionDenied);
    } else {
      setState(() => _state = _DiscoverState.permissionNeeded);
    }
  }

  Future<void> _requestPermission() async {
    HapticFeedback.lightImpact();
    final granted = await _svc.request();
    if (!mounted) return;
    if (granted) {
      await _loadContacts();
    } else {
      final status = await _svc.status();
      if (!mounted) return;
      setState(() => _state = status.isPermanentlyDenied
          ? _DiscoverState.permissionDenied
          : _DiscoverState.permissionNeeded);
    }
  }

  Future<void> _loadContacts() async {
    setState(() => _state = _DiscoverState.loading);
    final contacts = await _svc.loadContacts();
    if (!mounted) return;
    setState(() {
      _onSaanjh = contacts.where((c) => c.isOnSaanjh).toList();
      _toInvite = contacts.where((c) => !c.isOnSaanjh).toList();
      _state = _DiscoverState.loaded;
    });
  }

  Future<void> _startDiary(SaanjhContact contact) async {
    // Already in diary (matched by phone because backend IDs ≠ device contact IDs).
    if (_store.hasPhone(contact.phone)) {
      _showToast("${contact.name} is already in your diary");
      return;
    }
    if (_connecting.contains(contact.phone)) return;

    HapticFeedback.mediumImpact();
    setState(() => _connecting.add(contact.phone));

    try {
      // If check-contacts already returned a connection_id, use it directly.
      String? connectionId = contact.connectionId?.isNotEmpty == true
          ? contact.connectionId
          : null;

      if (connectionId == null) {
        // Both users are on Saanjh — create or surface a direct connection.
        final res = await ConnectionsApi.instance.connectDirect(
          phone: contact.phone,
          connectionName: contact.name,
        );
        connectionId = res['connection_id']?.toString();
      }

      if (connectionId == null || connectionId.isEmpty) {
        throw Exception('No connection found for ${contact.phone}');
      }

      if (!_store.has(connectionId)) {
        _store.add(DiaryContact(
          id: connectionId,
          name: contact.name,
          relation: 'Contact',
          phone: contact.phone,
          initial: contact.initial,
          avatarColor: contact.avatarColor,
        ));
      }

      if (mounted) _showToast("${contact.name}'s diary is ready");
    } catch (e) {
      debugPrint('[discover] _startDiary error: $e');
      if (mounted) _showToast("Couldn't connect. Please try again.");
    } finally {
      if (mounted) setState(() => _connecting.remove(contact.phone));
    }
  }

  void _invite(SaanjhContact contact) {
    HapticFeedback.selectionClick();
    context.push(
      AppRoutes.inviteRecipient,
      extra: {'name': contact.name, 'phone': contact.phone},
    );
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: GlowBackground(glowTopFraction: 0.12)),
          _buildBody(),
          if (_toast != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 116,
              child: Center(child: _ToastBadge(message: _toast!)),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _DiscoverState.checking:
      case _DiscoverState.loading:
        return _LoadingView();
      case _DiscoverState.permissionNeeded:
        return _PermissionRequestView(onAllow: _requestPermission, onSkip: _skipToHome);
      case _DiscoverState.permissionDenied:
        return _PermissionDeniedView(onSettings: openAppSettings, onSkip: _skipToHome);
      case _DiscoverState.loaded:
        return _ContactsView(
          onSaanjh: _onSaanjh,
          toInvite: _toInvite,
          store: _store,
          onStartDiary: _startDiary,
          onInvite: _invite,
          onContinue: _skipToHome,
          searchQuery: _searchQuery,
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          connecting: _connecting,
        );
    }
  }

  void _skipToHome() => context.go(AppRoutes.home);
}

// ─── Loading ──────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Finding your people…',
                  style: AppTypography.label(
                      size: 14, color: AppColors.textMuted)),
            ),
            ...List.generate(
              5,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SaanjhShimmer(
                  isLoading: true,
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.inkRaised,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.ink),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                  height: 13,
                                  width: 110,
                                  color: AppColors.ink,
                                  margin: const EdgeInsets.only(bottom: 8)),
                              Container(height: 10, color: AppColors.ink),
                            ],
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.ink,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Permission request ───────────────────────────────────────────────────────

class _PermissionRequestView extends StatefulWidget {
  final VoidCallback onAllow;
  final VoidCallback onSkip;
  const _PermissionRequestView({required this.onAllow, required this.onSkip});

  @override
  State<_PermissionRequestView> createState() => _PermissionRequestViewState();
}

class _PermissionRequestViewState extends State<_PermissionRequestView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) {
            final t = Curves.easeOutCubic.transform(_ctrl.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                  offset: Offset(0, 20 * (1 - t)), child: child),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SaanjhLogo(size: 64),
              const SizedBox(height: 32),
              Text.rich(
                TextSpan(
                  style: AppTypography.title(size: 36, weight: FontWeight.w600)
                      .copyWith(height: 1.1),
                  children: [
                    const TextSpan(text: 'Find your\npeople on '),
                    TextSpan(
                      text: 'Saanjh.',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppColors.emberBright,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Saanjh checks your contacts against encrypted phone hashes — never uploads your address book.',
                style: AppTypography.body(size: 15, color: AppColors.textMuted),
              ),
              const SizedBox(height: 28),
              _FeatureLine(icon: Icons.people_rounded,
                  text: 'See which family & friends are already on Saanjh'),
              const SizedBox(height: 12),
              _FeatureLine(icon: Icons.send_rounded,
                  text: 'Invite others with a single tap — no typing'),
              const SizedBox(height: 12),
              _FeatureLine(icon: Icons.lock_rounded,
                  text: 'Your contacts stay on your device — always'),
              const Spacer(),
              _PrivacyChip(),
              const SizedBox(height: 20),
              CtaPrimary(
                label: 'Allow access to contacts',
                onPressed: widget.onAllow,
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: widget.onSkip,
                  child: Text("I'll find people manually",
                      style: AppTypography.label(
                          size: 13.5, color: AppColors.textMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.ember.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 17, color: AppColors.emberWarm),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(text,
                style: AppTypography.body(size: 14.5, color: AppColors.textMuted)),
          ),
        ),
      ],
    );
  }
}

class _PrivacyChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0x0D30D158),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x2530D158), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF7CD992)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Private · Encrypted · Never shared with anyone',
              style: AppTypography.label(size: 12, color: const Color(0xFF7CD992)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Permission denied ────────────────────────────────────────────────────────

class _PermissionDeniedView extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onSkip;
  const _PermissionDeniedView({required this.onSettings, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10), width: 1),
                ),
                child: Icon(Icons.contacts_outlined,
                    size: 32, color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              Text('Contacts access\ndenied',
                  style: AppTypography.title(size: 26),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                "You can enable it in Settings → Saanjh → Contacts, or invite people manually.",
                style: AppTypography.serifItalic(size: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              CtaPrimary(
                  label: 'Open Settings', onPressed: onSettings),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onSkip,
                child: Text('Continue without contacts',
                    style: AppTypography.label(
                        size: 13, color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Contacts list ────────────────────────────────────────────────────────────

class _ContactsView extends StatelessWidget {
  final List<SaanjhContact> onSaanjh;
  final List<SaanjhContact> toInvite;
  final DiaryStore store;
  final Future<void> Function(SaanjhContact) onStartDiary;
  final ValueChanged<SaanjhContact> onInvite;
  final VoidCallback onContinue;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Set<String> connecting;

  const _ContactsView({
    required this.onSaanjh,
    required this.toInvite,
    required this.store,
    required this.onStartDiary,
    required this.onInvite,
    required this.onContinue,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.connecting,
  });

  List<SaanjhContact> _filter(List<SaanjhContact> list) {
    if (searchQuery.isEmpty) return list;
    final q = searchQuery.toLowerCase().trim();
    // Strip non-digits from the query so "9876" matches "+91 98••• ••76x" digits.
    final digits = searchQuery.replaceAll(RegExp(r'\D'), '');
    return list.where((c) {
      if (c.name.toLowerCase().contains(q)) return true;
      if (digits.isNotEmpty &&
          c.phone.replaceAll(RegExp(r'\D'), '').contains(digits)) {
        return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (_, w) {
        // Primary check: connection_id returned by checkContacts — reliable even
        // when loadConnections() hasn't run yet.  Secondary: phone match for
        // contacts added via _startDiary() in the current session before the
        // API returns (DiaryContact.phone is empty for server-loaded contacts
        // because the backend only stores phone hashes, not plaintext).
        final available = onSaanjh.where((c) {
          final cid = c.connectionId;
          if (cid != null && cid.isNotEmpty && store.has(cid)) return false;
          return !store.hasPhone(c.phone);
        }).toList();
        final filteredSaanjh = _filter(available);
        final filteredInvite = _filter(toInvite);
        final allAdded = available.isEmpty && onSaanjh.isNotEmpty;
        final noResults = searchQuery.isNotEmpty &&
            filteredSaanjh.isEmpty &&
            filteredInvite.isEmpty;

        return Column(
          children: [
            SaanjhReveal(child: _ContactsHeader()),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.of(context).padding.bottom + 110),
                physics: const BouncingScrollPhysics(),
                children: [
                  SaanjhReveal(
                    delay: const Duration(milliseconds: 60),
                    child: _SearchBar(
                      query: searchQuery,
                      onChanged: onSearchChanged,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SaanjhReveal(
                    delay: const Duration(milliseconds: 100),
                    child: _PrivacyNote(),
                  ),
                  const SizedBox(height: 18),
                  if (noResults) ...[
                    const SizedBox(height: 24),
                    _EmptySection(
                        text: 'No contacts match "$searchQuery".'),
                  ] else ...[
                    if (onSaanjh.isNotEmpty) ...[
                      _SectionLabel('ON SAANJH ALREADY',
                          count: filteredSaanjh.length),
                      const SizedBox(height: 10),
                      if (allAdded && searchQuery.isEmpty)
                        _EmptySection(
                            text: 'Everyone here is already in your diaries.')
                      else
                        for (final (i, c) in filteredSaanjh.indexed)
                          SaanjhReveal.staggered(
                            index: i + 3,
                            child: _PersonTile(
                              contact: c,
                              inDiary: false,
                              onSaanjh: true,
                              isConnecting: connecting.contains(c.phone),
                              onTap: () => onStartDiary(c),
                            ),
                          ),
                    ],
                    if (onSaanjh.isEmpty && searchQuery.isEmpty)
                      _EmptySection(text: 'None of your contacts are on Saanjh yet.'),
                    const SizedBox(height: 24),
                    if (filteredInvite.isNotEmpty) ...[
                      _SectionLabel('INVITE TO SAANJH',
                          count: filteredInvite.length),
                      const SizedBox(height: 10),
                      for (final (i, c) in filteredInvite.indexed)
                        SaanjhReveal.staggered(
                          index: i + 4,
                          child: _PersonTile(
                            contact: c,
                            inDiary: false,
                            onSaanjh: false,
                            onTap: () => onInvite(c),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
            _BottomBar(onContinue: onContinue, onLater: onContinue),
          ],
        );
      },
    );
  }
}

class _ContactsHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                context.pop();
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 1),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 14, color: Color(0x9EF5EFE8)),
              ),
            ),
            const SizedBox(height: 14),
            Text('DISCOVER',
                style: AppTypography.eyebrow(
                    size: 10, color: AppColors.emberBright)),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                style: AppTypography.title(size: 28, weight: FontWeight.w600)
                    .copyWith(height: 1.08),
                children: [
                  const TextSpan(text: 'People you know\non '),
                  TextSpan(
                    text: 'Saanjh.',
                    style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppColors.emberBright),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a forever diary with one tap — no invite link needed.',
              style: AppTypography.body(size: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0x0A30D158),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x2530D158), width: 1),
      ),
      child: Row(
        children: [
          const Text('🔒', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Private matching · Encrypted phone hashes · You choose who becomes a diary.',
              style: AppTypography.label(size: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  final String query;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.query, required this.onChanged});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.query);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: widget.onChanged,
      style: AppTypography.body(size: 14),
      decoration: InputDecoration(
        hintText: 'Search by name or number…',
        hintStyle: AppTypography.body(size: 14, color: AppColors.textFaint),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        prefixIcon: Icon(Icons.search_rounded,
            size: 18, color: AppColors.textFaint),
        suffixIcon: widget.query.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  _ctrl.clear();
                  widget.onChanged('');
                },
                child: Icon(Icons.close_rounded,
                    size: 16, color: AppColors.textFaint),
              )
            : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: AppColors.emberWarm, width: 1.5),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final int count;
  const _SectionLabel(this.label, {required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style:
                AppTypography.eyebrow(size: 10, color: AppColors.textFaint)),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: AppTypography.label(
                  size: 10,
                  weight: FontWeight.w600,
                  color: AppColors.textFaint),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String text;
  const _EmptySection({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(text,
            style: AppTypography.serifItalic(size: 15),
            textAlign: TextAlign.center),
      ),
    );
  }
}

class _PersonTile extends StatefulWidget {
  final SaanjhContact contact;
  final bool inDiary;
  final bool onSaanjh;
  final bool isConnecting;
  final VoidCallback onTap;

  const _PersonTile({
    required this.contact,
    required this.inDiary,
    required this.onSaanjh,
    required this.onTap,
    this.isConnecting = false,
  });

  @override
  State<_PersonTile> createState() => _PersonTileState();
}

class _PersonTileState extends State<_PersonTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.contact;
    final onSaanjh = widget.onSaanjh;

    return GestureDetector(
      onTapDown: widget.isConnecting ? null : (_) => setState(() => _pressed = true),
      onTapUp:   widget.isConnecting ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.isConnecting ? null : () => setState(() => _pressed = false),
      onTap: widget.isConnecting ? null : widget.onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: onSaanjh
                ? AppColors.emberWarm
                    .withValues(alpha: _pressed ? 0.30 : 0.14)
                : Colors.white.withValues(alpha: _pressed ? 0.10 : 0.06),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    c.avatarColor,
                    c.avatarColor.withValues(alpha: 0.65),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                // Subtle amber ring for on-Saanjh contacts
                border: onSaanjh
                    ? Border.all(
                        color: AppColors.emberWarm.withValues(alpha: 0.35),
                        width: 1.5,
                      )
                    : null,
                boxShadow: onSaanjh
                    ? [
                        BoxShadow(
                          color: AppColors.emberWarm.withValues(alpha: 0.18),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  c.initial,
                  style: AppTypography.title(size: 19).copyWith(
                      color: Colors.white, fontStyle: FontStyle.italic),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + phone
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: AppTypography.body(
                        size: 15, weight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (onSaanjh) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.emberWarm,
                            boxShadow: AppShadows.dotGlow(intensity: 0.5, blur: 5),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'on Saanjh',
                          style: AppTypography.label(
                              size: 11.5,
                              weight: FontWeight.w600,
                              color: AppColors.emberBright),
                        ),
                        const SizedBox(width: 6),
                        Text('·',
                            style: AppTypography.label(
                                size: 11, color: AppColors.textFaint)),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Builder(builder: (_) {
                          // If contact is in DiaryStore with a custom label, show that
                          DiaryContact? dc;
                          try {
                            dc = DiaryStore.instance.diaries.firstWhere(
                                (d) => d.phone == c.phone);
                          } catch (_) {}
                          final sub = (dc != null &&
                                  dc.customLabel.isNotEmpty)
                              ? dc.customLabel
                              : c.phone;
                          return Text(
                            sub,
                            style: AppTypography.label(
                                size: 12, color: AppColors.textFaint),
                            overflow: TextOverflow.ellipsis,
                          );
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            widget.isConnecting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.emberWarm),
                  )
                : _ActionPill(
                    label: onSaanjh ? 'Start diary' : 'Invite',
                    isInvite: !onSaanjh,
                  ),
          ],
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String label;
  final bool isInvite;
  const _ActionPill({required this.label, required this.isInvite});

  @override
  Widget build(BuildContext context) {
    if (isInvite) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x0D30D158),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x2530D158), width: 1),
        ),
        child: Text(
          'Invite',
          style: AppTypography.label(
              size: 12,
              weight: FontWeight.w600,
              color: const Color(0xFF7CD992)),
        ),
      );
    }
    // "Start diary" — amber gradient pill
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        gradient: AppColors.emberGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.ember.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        'Start diary',
        style: AppTypography.label(
            size: 12, weight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onLater;

  const _BottomBar({required this.onContinue, required this.onLater});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.ink.withValues(alpha: 0),
            AppColors.ink.withValues(alpha: 0.97),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CtaPrimary(label: 'Go to my diaries', onPressed: onContinue),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onLater,
            child: Text('Add people later',
                style: AppTypography.label(
                    size: 13, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _ToastBadge extends StatelessWidget {
  final String message;
  const _ToastBadge({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xF5140E12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.10), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 14, color: Color(0xFF7CD992)),
          const SizedBox(width: 8),
          Text(message,
              style: AppTypography.label(size: 13, color: AppColors.text)),
        ],
      ),
    );
  }
}
