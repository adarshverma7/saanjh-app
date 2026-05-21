import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/memory_book_generator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';

class MemoryBookScreen extends StatefulWidget {
  final String? diaryId;
  final bool isGift;
  const MemoryBookScreen({super.key, this.diaryId, this.isGift = false});

  @override
  State<MemoryBookScreen> createState() => _MemoryBookScreenState();
}

enum _Tab { preview, order }
enum _Cover { soft, hard }

class _MemoryBookScreenState extends State<MemoryBookScreen>
    with SingleTickerProviderStateMixin {
  _Tab _tab = _Tab.preview;
  _Cover _cover = _Cover.hard;
  final _pageCtrl = PageController();
  int _currentPage = 0;
  bool _ordering = false;

  // Order form
  final _nameCtrl = TextEditingController();
  final _line1Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.isGift) {
      // Auto-open gift sheet after first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showGiftSheet();
      });
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _line1Ctrl.dispose();
    _cityCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  int get _price => _cover == _Cover.hard ? 599 : 399;

  void _showGiftSheet() {
    final data = widget.diaryId != null
        ? MemoryBookGenerator.generateForDiary(widget.diaryId!)
        : null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GiftBookSheet(
        diaryId: widget.diaryId,
        contactName: data?.contactName,
        onConfirmed: () {
          Navigator.pop(context); // close sheet
          _showOrderConfirmed();
        },
      ),
    );
  }

  bool get _canOrder =>
      _nameCtrl.text.trim().isNotEmpty &&
      _line1Ctrl.text.trim().isNotEmpty &&
      _cityCtrl.text.trim().isNotEmpty &&
      _pincodeCtrl.text.trim().length == 6;

  Future<void> _placeOrder() async {
    if (!_canOrder || _ordering) return;
    HapticFeedback.mediumImpact();
    setState(() => _ordering = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _showOrderConfirmed();
  }

  void _showOrderConfirmed() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.modalSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            28, 28, 28, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.successGreen.withValues(alpha: 0.15),
                border: Border.all(
                    color: AppColors.successGreen.withValues(alpha: 0.4),
                    width: 1.5),
              ),
              child: const Icon(Icons.check_rounded,
                  size: 36, color: AppColors.successGreen),
            ),
            const SizedBox(height: 20),
            Text('Order placed! 📬',
                style: AppTypography.title(size: 26),
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              'Your Memory Book is being prepared and will arrive in 7–10 days. We\'ll send updates to your registered number.',
              style: AppTypography.body(size: 16, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            CtaPrimary(
              label: 'Done',
              onPressed: () {
                Navigator.pop(context);
                context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.diaryId != null
        ? MemoryBookGenerator.generateForDiary(widget.diaryId!)
        : MemoryBookGenerator.generateAnnual();

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.5),
                  radius: 0.9,
                  colors: [
                    AppColors.ember.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            children: [
              _Header(isGift: widget.isGift),
              if (data != null) ...[
                _TabBar(
                  tab: _tab,
                  onSwitch: (t) => setState(() { _tab = t; _ordering = false; }),
                ),
              ],
              Expanded(
                child: data == null
                    ? _EmptyState()
                    : (_tab == _Tab.preview
                        ? _PreviewTab(
                            pageCtrl: _pageCtrl,
                            currentPage: _currentPage,
                            onPageChanged: (i) => setState(() => _currentPage = i),
                            data: data,
                            onOrder: () => setState(() => _tab = _Tab.order),
                            onGift: _showGiftSheet,
                          )
                        : _OrderTab(
                            cover: _cover,
                            price: _price,
                            onCoverChanged: (c) => setState(() => _cover = c),
                            nameCtrl: _nameCtrl,
                            line1Ctrl: _line1Ctrl,
                            cityCtrl: _cityCtrl,
                            pincodeCtrl: _pincodeCtrl,
                            canOrder: _canOrder,
                            ordering: _ordering,
                            onChanged: () => setState(() {}),
                            onOrder: _placeOrder,
                          )),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isGift;
  const _Header({this.isGift = false});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 18, 0),
        child: Row(
          children: [
            GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); context.pop(); },
              child: Container(
                width: 36, height: 36,
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
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isGift ? 'GIFT A MEMORY BOOK' : 'MEMORY BOOK',
                      style: AppTypography.eyebrow(
                          size: 10, color: AppColors.emberBright)),
                  Text(isGift ? 'A gift they\'ll keep forever' : 'Your year in voices',
                      style: AppTypography.title(size: 22)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab bar ──────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  final _Tab tab;
  final ValueChanged<_Tab> onSwitch;

  const _TabBar({required this.tab, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.07), width: 1),
        ),
        child: Row(
          children: [
            for (final t in _Tab.values)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSwitch(t);
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: tab == t
                          ? AppColors.ember.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: tab == t
                          ? Border.all(
                              color:
                                  AppColors.emberWarm.withValues(alpha: 0.35),
                              width: 1)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        t == _Tab.preview ? '📖  Preview' : '🛒  Order',
                        style: AppTypography.label(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: tab == t
                              ? AppColors.emberBright
                              : AppColors.textFaint,
                        ),
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

// ─── Preview tab ──────────────────────────────────────────────────────────────

class _PreviewTab extends StatelessWidget {
  final PageController pageCtrl;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final MemoryBookData data;
  final VoidCallback onOrder;
  final VoidCallback onGift;

  const _PreviewTab({
    required this.pageCtrl,
    required this.currentPage,
    required this.onPageChanged,
    required this.data,
    required this.onOrder,
    required this.onGift,
  });

  static const _totalPages = 5;

  @override
  Widget build(BuildContext context) {
    final isPreview = data.peakStreak < 90;

    return Column(
      children: [
        const SizedBox(height: 18),
        // Book pages carousel
        SizedBox(
          height: 340,
          child: PageView.builder(
            controller: pageCtrl,
            onPageChanged: onPageChanged,
            itemCount: _totalPages,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _BookPage(index: i, data: data),
            ),
          ),
        ),

        // Page dots
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_totalPages, (i) {
            final active = i == currentPage;
            return AnimatedContainer(
              duration: AppMotion.fast,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: active
                    ? AppColors.emberWarm
                    : Colors.white.withValues(alpha: 0.18),
              ),
            );
          }),
        ),

        const SizedBox(height: 8),
        if (isPreview) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.ember.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.emberWarm.withValues(alpha: 0.25), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 12, color: AppColors.emberWarm),
                const SizedBox(width: 6),
                Text(
                  'Full book available after 90 days of memories',
                  style: AppTypography.label(
                      size: 11.5, color: AppColors.emberWarm),
                ),
              ],
            ),
          ),
        ] else
          Text('Swipe to preview pages',
              style: AppTypography.label(
                  size: 11.5, color: AppColors.textFaint)),

        // Stats row
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _StatsRow(data: data),
        ),

        const Spacer(),
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.of(context).padding.bottom + 16),
          child: Column(
            children: [
              CtaPrimary(
                label: 'Order for yourself  →',
                onPressed: onOrder,
              ),
              const SizedBox(height: 10),
              _GiftCta(onTap: onGift),
              const SizedBox(height: 12),
              // Digital export — stub buttons signalling product vision
              Row(
                children: [
                  Expanded(
                    child: _StubButton(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'Download PDF',
                      sub: 'coming soon',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StubButton(
                      icon: Icons.print_rounded,
                      label: 'Print a copy',
                      sub: 'coming soon',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('From ₹399 self · ₹499 gift with wrapping · 7–10 days',
                  style: AppTypography.label(
                      size: 12.5, color: AppColors.textFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Book page ────────────────────────────────────────────────────────────────

class _BookPage extends StatelessWidget {
  final int index;
  final MemoryBookData data;

  const _BookPage({required this.index, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.float,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: _pageContent(),
      ),
    );
  }

  Widget _pageContent() {
    switch (index) {
      case 0:
        return _CoverPage(
          contactName: data.contactName,
          year: data.bookYear,
          noteCount: data.totalEntries,
        );
      case 1:
        return _StatsPage(
          noteCount: data.totalEntries,
          peakStreak: data.peakStreak,
          contactName: data.contactName,
        );
      case 2:
        return _TranscriptPage(pages: data.pages.take(3).toList());
      case 3:
        return _OnThisDayPage();
      default:
        return _FinalPage();
    }
  }
}

class _CoverPage extends StatelessWidget {
  final String contactName;
  final int year;
  final int noteCount;

  const _CoverPage({
    required this.contactName,
    required this.year,
    required this.noteCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1000), Color(0xFF1A0800), Color(0xFF0A0608)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 0.85,
                  colors: [
                    AppColors.ember.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40, height: 4,
                  color: AppColors.emberWarm.withValues(alpha: 0.6),
                ),
                const Spacer(),
                Text('सांझ', style: AppTypography.devanagari(size: 18)
                    .copyWith(color: AppColors.emberWarm.withValues(alpha: 0.7))),
                const SizedBox(height: 8),
                Text('A Year in\nVoices',
                    style: AppTypography.display(size: 38).copyWith(
                        height: 1.05, color: const Color(0xFFF5EFE8))),
                const SizedBox(height: 8),
                Text('$year · $contactName · $noteCount notes',
                    style: AppTypography.label(
                        size: 13, color: AppColors.textMuted)),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity, height: 1,
                  color: AppColors.emberWarm.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.wb_twilight_rounded,
                        size: 16, color: AppColors.emberWarm),
                    const SizedBox(width: 6),
                    Text('Saanjh Memory Book',
                        style: AppTypography.label(
                            size: 12, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsPage extends StatelessWidget {
  final int noteCount;
  final int peakStreak;
  final String contactName;

  const _StatsPage({
    required this.noteCount,
    required this.peakStreak,
    required this.contactName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAF4ED),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A year in numbers',
              style: AppTypography.title(size: 20).copyWith(
                  color: const Color(0xFF2A1000))),
          const SizedBox(height: 4),
          Text('With $contactName',
              style: AppTypography.label(size: 12).copyWith(
                  color: const Color(0xFF8B5E3C))),
          const SizedBox(height: 20),
          _StatLine('$noteCount', 'voice notes recorded'),
          if (peakStreak > 0)
            _StatLine('$peakStreak', 'day best streak'),
          _StatLine('52', 'weeks of connection'),
          const Spacer(),
          Text(
            '"Every voice note is a moment that would have gone unsaid. These are yours — forever."',
            style: AppTypography.serifItalic(size: 13.5).copyWith(
                color: const Color(0xFF6B4226)),
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String number;
  final String label;
  const _StatLine(this.number, this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(number,
              style: AppTypography.display(size: 32).copyWith(
                  color: AppColors.ember, fontStyle: FontStyle.italic)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: AppTypography.body(size: 14).copyWith(
                    color: const Color(0xFF4A2800))),
          ),
        ],
      ),
    );
  }
}

class _TranscriptPage extends StatelessWidget {
  final List<MemoryBookPage> pages;
  const _TranscriptPage({required this.pages});

  static const _fallback = [
    _FallbackEntry('Papa', '16 May',
        '"Beta, aaj bahut yaad aaya tera. Khana khaya? Hum tujhe miss karte hain."'),
    _FallbackEntry('Mom', '18 May',
        '"Biryani bani hai aaj, teri yaad aa gayi. Video call karo kal."'),
  ];

  @override
  Widget build(BuildContext context) {
    // Use real transcript entries; fall back to sample copy if none.
    final realEntries =
        pages.where((p) => p.transcript != null && p.transcript!.isNotEmpty).toList();
    final useFallback = realEntries.isEmpty;

    const colors = [AppColors.ember, Color(0xFFFF6B8A), AppColors.violet];

    return Container(
      color: const Color(0xFFFBF6F0),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sample pages',
                style: AppTypography.eyebrow(size: 9).copyWith(
                    color: const Color(0xFF8B5E3C))),
            const SizedBox(height: 12),
            if (useFallback) ...[
              for (var i = 0; i < _fallback.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 16),
                  Divider(
                      color: const Color(0xFFD4A870).withValues(alpha: 0.4),
                      height: 1),
                  const SizedBox(height: 16),
                ],
                _FallbackRow(_fallback[i], colors[i % colors.length]),
              ],
            ] else ...[
              for (var i = 0; i < realEntries.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 14),
                  Divider(
                      color: const Color(0xFFD4A870).withValues(alpha: 0.4),
                      height: 1),
                  const SizedBox(height: 14),
                ],
                _RealEntryRow(realEntries[i], colors[i % colors.length]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FallbackEntry {
  final String name;
  final String date;
  final String text;
  const _FallbackEntry(this.name, this.date, this.text);
}

class _FallbackRow extends StatelessWidget {
  final _FallbackEntry e;
  final Color dot;
  const _FallbackRow(this.e, this.dot);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
          const SizedBox(width: 8),
          Text('${e.name} · ${e.date}',
              style: AppTypography.caption().copyWith(
                  color: const Color(0xFF8B5E3C))),
        ]),
        const SizedBox(height: 10),
        Text(e.text,
            style: AppTypography.serifItalic(size: 14.5).copyWith(
                color: const Color(0xFF2A1000), height: 1.7)),
      ],
    );
  }
}

class _RealEntryRow extends StatelessWidget {
  final MemoryBookPage page;
  final Color dot;
  const _RealEntryRow(this.page, this.dot);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
          const SizedBox(width: 8),
          Text('${page.contactName} · ${page.dateLabel}',
              style: AppTypography.caption().copyWith(
                  color: const Color(0xFF8B5E3C))),
          const Spacer(),
          if (page.durationLabel.isNotEmpty)
            Text(page.durationLabel,
                style: AppTypography.caption().copyWith(
                    color: const Color(0xFF8B5E3C))),
        ]),
        const SizedBox(height: 10),
        Text('"${page.transcript ?? ''}"',
            style: AppTypography.serifItalic(size: 14.5).copyWith(
                color: const Color(0xFF2A1000), height: 1.7),
            maxLines: 5,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _OnThisDayPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A0800),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ON THIS DAY',
              style: AppTypography.eyebrow(size: 9, color: AppColors.emberBright)),
          const SizedBox(height: 12),
          Text('One year ago,\nyou sent this.',
              style: AppTypography.title(size: 24).copyWith(height: 1.1)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.ember.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.emberWarm.withValues(alpha: 0.25), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic_rounded, size: 14,
                        color: AppColors.emberWarm),
                    const SizedBox(width: 6),
                    Text('16 May 2024 · 0:09',
                        style: AppTypography.caption(
                            color: AppColors.textFaint)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('"Papa, aaj mere promotion hua. Aapki yaad aayi sabse pehle."',
                    style: AppTypography.serifItalic(size: 14,
                        color: AppColors.textMuted)),
              ],
            ),
          ),
          const Spacer(),
          Text(
            'Every On This Day moment is preserved — exactly as it was spoken.',
            style: AppTypography.body(size: 13, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}

class _FinalPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAF4ED),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite_rounded, size: 40, color: AppColors.ember),
              const SizedBox(height: 20),
              Text(
                'Your memories\ncontinue here.',
                style: AppTypography.title(size: 26).copyWith(
                    color: const Color(0xFF2A1000), height: 1.15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Every voice note. Every video. Printed and bound, kept forever.',
                style: AppTypography.body(size: 14).copyWith(
                    color: const Color(0xFF6B4226)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final MemoryBookData data;
  const _StatsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Stat(data.totalEntries.toString(), 'Notes'),
          _Vr(),
          _Stat(
            data.peakStreak > 0 ? '${data.peakStreak}d' : '—',
            'Best streak',
          ),
          _Vr(),
          _Stat(data.bookYear.toString(), 'Year'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: AppTypography.display(size: 26).copyWith(
                color: AppColors.emberWarm, fontStyle: FontStyle.italic)),
        Text(label,
            style: AppTypography.caption(color: AppColors.textFaint)),
      ],
    );
  }
}

class _Vr extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1, height: 36,
      color: Colors.white.withValues(alpha: 0.08));
}

// ─── Gift CTA button ─────────────────────────────────────────────────────────

class _GiftCta extends StatefulWidget {
  final VoidCallback onTap;
  const _GiftCta({required this.onTap});

  @override
  State<_GiftCta> createState() => _GiftCtaState();
}

class _GiftCtaState extends State<_GiftCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: _pressed
              ? AppColors.ember.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _pressed
                ? AppColors.emberWarm.withValues(alpha: 0.45)
                : AppColors.emberWarm.withValues(alpha: 0.28),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎁', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              'Gift this book  ₹499  →',
              style: AppTypography.label(
                size: 14.5,
                weight: FontWeight.w600,
                color: AppColors.emberWarm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Gift book sheet ─────────────────────────────────────────────────────────

class _GiftBookSheet extends StatefulWidget {
  final String? diaryId;
  final String? contactName;
  final VoidCallback onConfirmed;
  const _GiftBookSheet({this.diaryId, this.contactName, required this.onConfirmed});

  @override
  State<_GiftBookSheet> createState() => _GiftBookSheetState();
}

class _GiftBookSheetState extends State<_GiftBookSheet> {
  final _msgCtrl    = TextEditingController();
  final _nameCtrl   = TextEditingController();
  final _line1Ctrl  = TextEditingController();
  final _cityCtrl   = TextEditingController();
  final _pinCtrl    = TextEditingController();
  bool _placing = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _nameCtrl.dispose();
    _line1Ctrl.dispose();
    _cityCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  bool get _canPlace =>
      _nameCtrl.text.trim().isNotEmpty &&
      _line1Ctrl.text.trim().isNotEmpty &&
      _cityCtrl.text.trim().isNotEmpty &&
      _pinCtrl.text.replaceAll(RegExp(r'\D'), '').length == 6;

  Future<void> _placeOrder() async {
    if (!_canPlace || _placing) return;
    HapticFeedback.mediumImpact();
    setState(() => _placing = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final recipientName =
        widget.contactName?.split(' ').first ?? 'them';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF130A10),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.08), width: 1),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(children: [
              const Text('🎁', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gift a Memory Book',
                        style: AppTypography.title(
                            size: 22, weight: FontWeight.w600)),
                    Text('Printed · delivered · ₹499 with gift wrapping',
                        style: AppTypography.caption(
                            size: 12.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 22),

            // Gift message
            Text('YOUR GIFT MESSAGE',
                style: AppTypography.eyebrow(
                    size: 10, color: AppColors.textFaint)),
            const SizedBox(height: 8),
            TextField(
              controller: _msgCtrl,
              maxLines: 3,
              maxLength: 200,
              style: AppTypography.body(size: 14),
              cursorColor: AppColors.emberWarm,
              decoration: InputDecoration(
                hintText:
                    'Write something for $recipientName… (optional)',
                hintStyle:
                    AppTypography.body(size: 14, color: AppColors.textFaint),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                counterStyle:
                    AppTypography.caption(size: 11, color: AppColors.textFaint),
                contentPadding: const EdgeInsets.all(14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: AppColors.emberWarm, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // Recipient address
            Text('DELIVER TO',
                style: AppTypography.eyebrow(
                    size: 10, color: AppColors.textFaint)),
            const SizedBox(height: 8),
            _GiftField(
              ctrl: _nameCtrl,
              hint: 'Recipient\'s full name',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 10),
            _GiftField(
              ctrl: _line1Ctrl,
              hint: 'House / flat, street, area',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _GiftField(
                  ctrl: _cityCtrl,
                  hint: 'City',
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: _GiftField(
                  ctrl: _pinCtrl,
                  hint: 'Pincode',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: () => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: 22),

            // Price breakdown
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07), width: 1),
              ),
              child: Column(children: [
                _GiftSummaryRow('Memory Book (Softcover)', '₹399'),
                const SizedBox(height: 6),
                _GiftSummaryRow('Gift wrapping & message card', '₹100'),
                const SizedBox(height: 6),
                _GiftSummaryRow('Shipping', 'Free'),
                Divider(
                    color: Colors.white.withValues(alpha: 0.07),
                    height: 16),
                _GiftSummaryRow('Total', '₹499', bold: true),
              ]),
            ),
            const SizedBox(height: 20),

            // CTA
            GestureDetector(
              onTap: _placeOrder,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                height: 56,
                decoration: BoxDecoration(
                  gradient: _canPlace
                      ? AppColors.emberGradient
                      : null,
                  color: _canPlace ? null : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: _placing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Place gift order  →',
                          style: AppTypography.label(
                            size: 15,
                            weight: FontWeight.w600,
                            color: _canPlace
                                ? Colors.white
                                : AppColors.textFaint,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Delivered in 7–10 days. Your voice note transcripts will be printed in the book.',
              style: AppTypography.caption(
                  size: 11.5, color: AppColors.textFaint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final TextInputType keyboardType;
  final int? maxLength;
  final VoidCallback onChanged;

  const _GiftField({
    required this.ctrl,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: AppTypography.body(size: 14),
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle:
            AppTypography.body(size: 14, color: AppColors.textFaint),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.emberWarm, width: 1.5),
        ),
      ),
    );
  }
}

class _GiftSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _GiftSummaryRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Text(label,
            style: bold
                ? AppTypography.body(size: 14, weight: FontWeight.w600)
                : AppTypography.body(size: 13, color: AppColors.textMuted)),
      ),
      Text(value,
          style: bold
              ? AppTypography.body(
                  size: 14,
                  weight: FontWeight.w700,
                  color: AppColors.emberWarm)
              : AppTypography.body(size: 13, color: AppColors.textMuted)),
    ]);
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📖', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 20),
          Text(
            'Your Memory Book will be ready after your first voice note.',
            style: AppTypography.body(size: 18, color: AppColors.textMuted)
                .copyWith(height: 1.55),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Send a note to start building your story.',
            style: AppTypography.label(size: 13, color: AppColors.textFaint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Stub button ─────────────────────────────────────────────────────────────

class _StubButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;

  const _StubButton({
    required this.icon,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.label(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: AppColors.textFaint)),
                Text(sub,
                    style: AppTypography.label(
                        size: 10.5, color: AppColors.textFaint
                            .withValues(alpha: 0.5))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Order tab ────────────────────────────────────────────────────────────────

class _OrderTab extends StatelessWidget {
  final _Cover cover;
  final int price;
  final ValueChanged<_Cover> onCoverChanged;
  final TextEditingController nameCtrl;
  final TextEditingController line1Ctrl;
  final TextEditingController cityCtrl;
  final TextEditingController pincodeCtrl;
  final bool canOrder;
  final bool ordering;
  final VoidCallback onChanged;
  final VoidCallback onOrder;

  const _OrderTab({
    required this.cover,
    required this.price,
    required this.onCoverChanged,
    required this.nameCtrl,
    required this.line1Ctrl,
    required this.cityCtrl,
    required this.pincodeCtrl,
    required this.canOrder,
    required this.ordering,
    required this.onChanged,
    required this.onOrder,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover type
          _FormLabel('BINDING TYPE'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _CoverOption(
                label: 'Softcover',
                price: '₹399',
                selected: cover == _Cover.soft,
                onTap: () => onCoverChanged(_Cover.soft),
              )),
              const SizedBox(width: 10),
              Expanded(child: _CoverOption(
                label: 'Hardcover',
                price: '₹599',
                selected: cover == _Cover.hard,
                badge: 'Popular',
                onTap: () => onCoverChanged(_Cover.hard),
              )),
            ],
          ),

          const SizedBox(height: 24),

          // What's included
          _FormLabel('WHAT\'S INCLUDED'),
          const SizedBox(height: 10),
          _IncludeRow(icon: Icons.mic_rounded, text: 'All voice note transcripts'),
          _IncludeRow(icon: Icons.videocam_rounded, text: 'Video clip timestamps & captions'),
          _IncludeRow(icon: Icons.auto_awesome_rounded, text: '"On This Day" memories'),
          _IncludeRow(icon: Icons.local_shipping_rounded, text: 'Free shipping across India'),

          const SizedBox(height: 24),

          // Delivery address
          _FormLabel('DELIVERY ADDRESS'),
          const SizedBox(height: 10),
          _Field(
            ctrl: nameCtrl,
            hint: 'Full name',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 10),
          _Field(
            ctrl: line1Ctrl,
            hint: 'House / flat number, street, area',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Field(
                ctrl: cityCtrl,
                hint: 'City',
                onChanged: (_) => onChanged(),
              )),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: _Field(
                  ctrl: pincodeCtrl,
                  hint: 'Pincode',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Order summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07), width: 1),
            ),
            child: Column(
              children: [
                _SummaryRow('Memory Book (${cover == _Cover.hard ? 'Hardcover' : 'Softcover'})',
                    '₹$price'),
                _SummaryRow('Shipping', 'Free'),
                Divider(color: Colors.white.withValues(alpha: 0.06), height: 20),
                _SummaryRow('Total', '₹$price', bold: true),
              ],
            ),
          ),

          const SizedBox(height: 20),

          CtaPrimary(
            label: ordering ? 'Placing order…' : 'Place order  →',
            loading: ordering,
            onPressed: canOrder ? onOrder : null,
          ),
          const SizedBox(height: 10),
          Text(
            'By ordering you agree that your voice note transcripts will be printed. Saanjh does not share your data with any third party.',
            style: AppTypography.caption(size: 11.5, color: AppColors.textFaint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppTypography.eyebrow(size: 10, color: AppColors.textFaint));
}

class _CoverOption extends StatelessWidget {
  final String label;
  final String price;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  const _CoverOption({
    required this.label,
    required this.price,
    required this.selected,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ember.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.emberWarm.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.emberWarm : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? AppColors.emberWarm
                          : Colors.white.withValues(alpha: 0.22),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 11, color: Colors.white)
                      : null,
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.ember.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(badge!,
                        style: AppTypography.label(
                            size: 9.5,
                            weight: FontWeight.w700,
                            color: AppColors.emberBright)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(label,
                style: AppTypography.body(size: 14, weight: FontWeight.w600)),
            Text(price,
                style: AppTypography.label(
                    size: 13,
                    weight: FontWeight.w600,
                    color: selected
                        ? AppColors.emberWarm
                        : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _IncludeRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IncludeRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.emberWarm),
          const SizedBox(width: 10),
          Text(text,
              style: AppTypography.body(size: 14, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final TextInputType keyboardType;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.ctrl,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: AppTypography.body(size: 14),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: AppTypography.body(size: 14, color: AppColors.textFaint),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppColors.emberWarm, width: 1.5),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _SummaryRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: bold
                  ? AppTypography.body(size: 15, weight: FontWeight.w600)
                  : AppTypography.body(size: 14, color: AppColors.textMuted)),
        ),
        Text(value,
            style: bold
                ? AppTypography.body(
                    size: 15,
                    weight: FontWeight.w700,
                    color: AppColors.emberWarm)
                : AppTypography.body(size: 14, color: AppColors.textMuted)),
      ],
    );
  }
}
