import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../state/story_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Instagram-style full-screen story viewer.
///
/// Horizontal PageView across user groups; inside a group, stories advance
/// automatically (photos 5 s, video/audio for their duration) with segmented
/// progress bars. Tap right → next, tap left → previous, long-press → pause,
/// swipe down or ✕ → close.
class StoryViewerScreen extends StatefulWidget {
  final int initialGroupIndex;
  const StoryViewerScreen({super.key, this.initialGroupIndex = 0});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final PageController _pageCtrl;
  late final List<StoryGroup> _groups; // frozen at open
  late int _groupIndex;

  @override
  void initState() {
    super.initState();
    _groups = StoryStore.instance.groups;
    _groupIndex = widget.initialGroupIndex.clamp(
        0, _groups.isEmpty ? 0 : _groups.length - 1);
    _pageCtrl = PageController(initialPage: _groupIndex);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _nextGroup() {
    if (_groupIndex >= _groups.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _previousGroup() {
    if (_groupIndex <= 0) return;
    _pageCtrl.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) {
      // Everything expired between strip render and open.
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No stories right now',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Swipe down to close, Instagram-style.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 350) Navigator.of(context).pop();
        },
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: _groups.length,
          onPageChanged: (i) => setState(() => _groupIndex = i),
          itemBuilder: (_, i) => _GroupView(
            key: ValueKey(_groups[i].userId),
            group: _groups[i],
            isActive: i == _groupIndex,
            onGroupDone: _nextGroup,
            onGroupBack: _previousGroup,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

// ─── One user's stories ───────────────────────────────────────────────────────

class _GroupView extends StatefulWidget {
  final StoryGroup group;
  final bool isActive;
  final VoidCallback onGroupDone;
  final VoidCallback onGroupBack;
  final VoidCallback onClose;

  const _GroupView({
    super.key,
    required this.group,
    required this.isActive,
    required this.onGroupDone,
    required this.onGroupBack,
    required this.onClose,
  });

  @override
  State<_GroupView> createState() => _GroupViewState();
}

class _GroupViewState extends State<_GroupView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  late List<StoryItem> _stories;
  int _index = 0;

  VideoPlayerController? _video;
  AudioPlayer? _audio;
  bool _mediaReady = false;
  bool _mediaFailed = false;

  static const _photoDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _stories = widget.group.live;
    // Start at the first unviewed story, like Instagram.
    final firstUnviewed = _stories.indexWhere((s) => !s.viewed);
    if (firstUnviewed > 0) _index = firstUnviewed;

    _progress = AnimationController(vsync: this, duration: _photoDuration)
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) _next(auto: true);
      });

    if (widget.isActive) _startCurrent();
  }

  @override
  void didUpdateWidget(covariant _GroupView old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _startCurrent();
    } else if (!widget.isActive && old.isActive) {
      _teardownMedia();
      _progress.stop();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _teardownMedia();
    super.dispose();
  }

  StoryItem get _current => _stories[_index];

  // ── Playback lifecycle ─────────────────────────────────────────────────────

  Future<void> _startCurrent() async {
    if (_stories.isEmpty) return;
    _teardownMedia();
    _progress.stop();
    _progress.value = 0;
    setState(() {
      _mediaReady = false;
      _mediaFailed = false;
    });

    final story = _current;
    StoryStore.instance.markViewed(story);

    switch (story.mediaType) {
      case 'video':
        try {
          final ctrl =
              VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl));
          await ctrl.initialize();
          if (!mounted || story.id != _current.id) {
            ctrl.dispose();
            return;
          }
          _video = ctrl;
          await ctrl.play();
          final d = ctrl.value.duration;
          _progress.duration =
              d > Duration.zero ? d : _fallbackDuration(story);
          setState(() => _mediaReady = true);
          _progress.forward();
        } catch (_) {
          if (mounted) setState(() => _mediaFailed = true);
        }
        break;

      case 'audio':
        try {
          final player = AudioPlayer();
          await player.setUrl(story.mediaUrl);
          if (!mounted || story.id != _current.id) {
            player.dispose();
            return;
          }
          _audio = player;
          player.play();
          final d = player.duration;
          _progress.duration =
              (d != null && d > Duration.zero) ? d : _fallbackDuration(story);
          setState(() => _mediaReady = true);
          _progress.forward();
        } catch (_) {
          if (mounted) setState(() => _mediaFailed = true);
        }
        break;

      default: // photo — progress starts when the image is actually shown
        _progress.duration = _photoDuration;
        break;
    }
  }

  Duration _fallbackDuration(StoryItem s) =>
      Duration(seconds: (s.durationSeconds ?? 15).clamp(1, 120));

  void _onPhotoReady() {
    if (!_mediaReady && mounted && widget.isActive) {
      setState(() => _mediaReady = true);
      _progress.forward();
    }
  }

  void _teardownMedia() {
    _video?.dispose();
    _video = null;
    _audio?.dispose();
    _audio = null;
  }

  void _next({bool auto = false}) {
    if (!auto) HapticFeedback.selectionClick();
    if (_index >= _stories.length - 1) {
      widget.onGroupDone();
      return;
    }
    setState(() => _index++);
    _startCurrent();
  }

  void _previous() {
    HapticFeedback.selectionClick();
    // At the first story: restart it if partially played, else previous group.
    if (_index == 0) {
      if (_progress.value > 0.15) {
        _startCurrent();
      } else {
        widget.onGroupBack();
      }
      return;
    }
    setState(() => _index--);
    _startCurrent();
  }

  void _pause() {
    _progress.stop();
    _video?.pause();
    _audio?.pause();
  }

  void _resume() {
    if (_mediaReady || _current.mediaType == 'photo') {
      _progress.forward();
      _video?.play();
      _audio?.play();
    }
  }

  // ── Author actions ─────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    _pause();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.modalSurface,
        title: Text('Delete story?',
            style: AppTypography.title(size: 18)
                .copyWith(color: Colors.white)),
        content: Text(
          'It will disappear for everyone immediately.',
          style: AppTypography.body(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: AppTypography.button(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: AppTypography.button(color: AppColors.destructive)),
          ),
        ],
      ),
    );
    if (yes != true) {
      _resume();
      return;
    }
    final removed = _current;
    try {
      await StoryStore.instance.deleteStory(removed);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete. Try again.')),
        );
      }
      _resume();
      return;
    }
    if (!mounted) return;
    _stories = List.of(_stories)..removeWhere((s) => s.id == removed.id);
    if (_stories.isEmpty) {
      widget.onClose();
      return;
    }
    if (_index >= _stories.length) _index = _stories.length - 1;
    setState(() {});
    _startCurrent();
  }

  Future<void> _showViewers() async {
    _pause();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.modalSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ViewersSheet(storyId: _current.id),
    );
    _resume();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_stories.isEmpty) return const SizedBox.shrink();
    final story = _current;
    final topPad = MediaQuery.of(context).padding.top;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Media layer
        _MediaLayer(
          key: ValueKey(story.id),
          story: story,
          video: _video,
          mediaReady: _mediaReady,
          mediaFailed: _mediaFailed,
          onPhotoReady: _onPhotoReady,
          onRetry: _startCurrent,
        ),

        // Tap zones: left third = previous, rest = next. Long-press pauses.
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _previous,
                  onLongPressStart: (_) => _pause(),
                  onLongPressEnd: (_) => _resume(),
                ),
              ),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _next(),
                  onLongPressStart: (_) => _pause(),
                  onLongPressEnd: (_) => _resume(),
                ),
              ),
            ],
          ),
        ),

        // Top scrim for legibility
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topPad + 96,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Progress segments
        Positioned(
          top: topPad + 8,
          left: 8,
          right: 8,
          child: Row(
            children: [
              for (var i = 0; i < _stories.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: i == _index
                        ? AnimatedBuilder(
                            animation: _progress,
                            builder: (_, _) =>
                                _SegmentBar(value: _progress.value),
                          )
                        : _SegmentBar(value: i < _index ? 1 : 0),
                  ),
                ),
            ],
          ),
        ),

        // Header: avatar + name + time · actions
        Positioned(
          top: topPad + 22,
          left: 12,
          right: 8,
          child: Row(
            children: [
              _Avatar(group: widget.group),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.group.isSelf
                          ? 'Your Story'
                          : (widget.group.name ?? 'Story'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label(
                          size: 14, weight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    Text(
                      _relativeTime(story.createdAt),
                      style: AppTypography.caption(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              if (widget.group.isSelf) ...[
                _HeaderIconButton(
                  icon: Icons.visibility_rounded,
                  label: '${story.viewCount}',
                  onTap: _showViewers,
                ),
                _HeaderIconButton(
                  icon: Icons.delete_outline_rounded,
                  onTap: _confirmDelete,
                ),
              ],
              _HeaderIconButton(
                icon: Icons.close_rounded,
                onTap: widget.onClose,
              ),
            ],
          ),
        ),

        // Caption
        if ((story.caption ?? '').isNotEmpty)
          Positioned(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 28,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  story.caption!,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(size: 15, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ─── Media rendering ──────────────────────────────────────────────────────────

class _MediaLayer extends StatelessWidget {
  final StoryItem story;
  final VideoPlayerController? video;
  final bool mediaReady;
  final bool mediaFailed;
  final VoidCallback onPhotoReady;
  final VoidCallback onRetry;

  const _MediaLayer({
    super.key,
    required this.story,
    required this.video,
    required this.mediaReady,
    required this.mediaFailed,
    required this.onPhotoReady,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (mediaFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Colors.white38, size: 42),
            const SizedBox(height: 12),
            Text('Couldn’t load this story',
                style: AppTypography.body(color: Colors.white70)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onRetry,
              child: Text('Retry',
                  style: AppTypography.button(color: AppColors.emberWarm)),
            ),
          ],
        ),
      );
    }

    switch (story.mediaType) {
      case 'video':
        if (video == null || !mediaReady) return const _LoadingShimmer();
        return FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: video!.value.size.width,
            height: video!.value.size.height,
            child: VideoPlayer(video!),
          ),
        );

      case 'audio':
        return _AudioBackdrop(playing: mediaReady);

      default: // photo
        return Image.network(
          story.mediaUrl,
          fit: BoxFit.cover,
          frameBuilder: (_, child, frame, wasSync) {
            if (frame != null || wasSync) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => onPhotoReady());
              return child;
            }
            return const _LoadingShimmer();
          },
          errorBuilder: (_, _, _) => Center(
            child: TextButton(
              onPressed: onRetry,
              child: Text('Retry',
                  style: AppTypography.button(color: AppColors.emberWarm)),
            ),
          ),
        );
    }
  }
}

class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF15090F),
      child: const Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.emberWarm,
          ),
        ),
      ),
    );
  }
}

/// Warm animated gradient shown while an audio story plays.
class _AudioBackdrop extends StatefulWidget {
  final bool playing;
  const _AudioBackdrop({required this.playing});

  @override
  State<_AudioBackdrop> createState() => _AudioBackdropState();
}

class _AudioBackdropState extends State<_AudioBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A0E06), Color(0xFF0A0608), Color(0xFF1A0A12)],
        ),
      ),
      child: Center(
        child: widget.playing
            ? AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) => Container(
                  width: 120 + _pulse.value * 26,
                  height: 120 + _pulse.value * 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.emberGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ember
                            .withValues(alpha: 0.35 + _pulse.value * 0.25),
                        blurRadius: 60,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.graphic_eq_rounded,
                      color: Colors.white, size: 52),
                ),
              )
            : const _LoadingShimmer(),
      ),
    );
  }
}

// ─── Small pieces ─────────────────────────────────────────────────────────────

class _SegmentBar extends StatelessWidget {
  final double value;
  const _SegmentBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 2.6,
        backgroundColor: Colors.white.withValues(alpha: 0.28),
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final StoryGroup group;
  const _Avatar({required this.group});

  @override
  Widget build(BuildContext context) {
    final initial =
        (group.name?.isNotEmpty ?? false) ? group.name![0].toUpperCase() : '·';
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: group.avatarUrl == null ? AppColors.emberGradient : null,
        image: group.avatarUrl != null
            ? DecorationImage(
                image: NetworkImage(group.avatarUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: group.avatarUrl == null
          ? Center(
              child: Text(initial,
                  style: AppTypography.title(size: 15)
                      .copyWith(color: Colors.white)),
            )
          : null,
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!,
                  style: AppTypography.label(size: 13, color: Colors.white)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Viewers sheet (author only) ─────────────────────────────────────────────

class _ViewersSheet extends StatefulWidget {
  final String storyId;
  const _ViewersSheet({required this.storyId});

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  List<Map<String, dynamic>>? _viewers;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await StoryStore.instance.viewersOf(widget.storyId);
      if (mounted) setState(() => _viewers = v);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(minHeight: 180, maxHeight: 420),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_rounded,
                    size: 16, color: AppColors.emberWarm),
                const SizedBox(width: 8),
                Text('Viewed by',
                    style: AppTypography.label(
                        size: 14, weight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
            const SizedBox(height: 14),
            if (_failed)
              Text('Couldn’t load viewers.',
                  style: AppTypography.body(color: Colors.white54))
            else if (_viewers == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.emberWarm),
                ),
              )
            else if (_viewers!.isEmpty)
              Text('No flickers yet — check back soon.',
                  style: AppTypography.body(color: Colors.white54))
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _viewers!.length,
                  itemBuilder: (_, i) {
                    final v = _viewers![i];
                    final name = (v['name'] as String?) ?? 'Someone';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: v['avatar_url'] == null
                                  ? AppColors.emberGradient
                                  : null,
                              image: v['avatar_url'] != null
                                  ? DecorationImage(
                                      image: NetworkImage(
                                          v['avatar_url'] as String),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: v['avatar_url'] == null
                                ? Center(
                                    child: Text(
                                      name[0].toUpperCase(),
                                      style: AppTypography.title(size: 14)
                                          .copyWith(color: Colors.white),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(name,
                                style: AppTypography.body(
                                    size: 15, color: Colors.white)),
                          ),
                          const Icon(Icons.favorite_rounded,
                              size: 14, color: AppColors.emberWarm),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
