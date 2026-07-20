import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../state/story_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

enum _Mode { photo, video, audio }

enum _Stage { capture, review, sharing }

/// Add Story — live capture only (no gallery), like the Flicker spec:
/// photo (camera), video (record, ≤ 30 s), audio (record, ≤ 60 s).
/// After capture: optional caption → Share.
class AddStoryScreen extends StatefulWidget {
  const AddStoryScreen({super.key});

  @override
  State<AddStoryScreen> createState() => _AddStoryScreenState();
}

class _AddStoryScreenState extends State<AddStoryScreen>
    with TickerProviderStateMixin {
  _Mode _mode = _Mode.photo;
  _Stage _stage = _Stage.capture;

  // Camera
  List<CameraDescription> _cameras = [];
  CameraController? _cam;
  bool _camReady = false;
  bool _camError = false;
  int _camIdx = 0;

  // Recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _recording = false;
  int _elapsed = 0;
  Timer? _timer;
  static const _maxVideoSecs = 30;
  static const _maxAudioSecs = 60;

  // Captured result
  String? _capturedPath;
  int _capturedDuration = 0;
  VideoPlayerController? _reviewVideo;
  ja.AudioPlayer? _reviewAudio;

  // Share
  final _captionCtrl = TextEditingController();
  double _uploadProgress = 0;
  String? _shareError;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _initCamera();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _cam?.dispose();
    _reviewVideo?.dispose();
    _reviewAudio?.dispose();
    _audioRecorder.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  // ── Camera ─────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    if (_mode == _Mode.audio) return;
    setState(() {
      _camReady = false;
      _camError = false;
    });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _camError = true);
        return;
      }
      final ctrl = CameraController(
        _cameras[_camIdx % _cameras.length],
        // Stories are ephemeral — medium keeps uploads small (edge case:
        // large media must be compressed before upload).
        _mode == _Mode.video ? ResolutionPreset.medium : ResolutionPreset.high,
        enableAudio: _mode == _Mode.video,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      _cam?.dispose();
      _cam = ctrl;
      if (mounted) setState(() => _camReady = true);
    } catch (_) {
      if (mounted) setState(() => _camError = true);
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording) return;
    HapticFeedback.selectionClick();
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _initCamera();
  }

  void _switchMode(_Mode m) {
    if (m == _mode || _recording) return;
    HapticFeedback.selectionClick();
    setState(() => _mode = m);
    if (m == _Mode.audio) {
      _cam?.dispose();
      _cam = null;
      _camReady = false;
    } else {
      _initCamera();
    }
  }

  // ── Capture ────────────────────────────────────────────────────────────────

  Future<void> _onShutter() async {
    switch (_mode) {
      case _Mode.photo:
        await _takePhoto();
      case _Mode.video:
        _recording ? await _stopVideo() : await _startVideo();
      case _Mode.audio:
        _recording ? await _stopAudio() : await _startAudio();
    }
  }

  Future<void> _takePhoto() async {
    if (_cam == null || !_camReady) return;
    HapticFeedback.mediumImpact();
    try {
      final file = await _cam!.takePicture();
      _capturedPath = file.path;
      _capturedDuration = 0;
      setState(() => _stage = _Stage.review);
    } catch (_) {}
  }

  Future<void> _startVideo() async {
    if (_cam == null || !_camReady) return;
    HapticFeedback.mediumImpact();
    try {
      await _cam!.startVideoRecording();
      _beginTimer(_maxVideoSecs, _stopVideo);
    } catch (_) {}
  }

  Future<void> _stopVideo() async {
    _endTimer();
    try {
      final file = await _cam!.stopVideoRecording();
      _capturedPath = file.path;
      _capturedDuration = _elapsed;
      final vp = VideoPlayerController.file(File(file.path));
      await vp.initialize();
      await vp.setLooping(true);
      await vp.play();
      _reviewVideo = vp;
      if (mounted) setState(() => _stage = _Stage.review);
    } catch (_) {}
  }

  Future<void> _startAudio() async {
    HapticFeedback.mediumImpact();
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/story_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path,
      );
      _capturedPath = path;
      _beginTimer(_maxAudioSecs, _stopAudio);
    } catch (_) {}
  }

  Future<void> _stopAudio() async {
    _endTimer();
    try {
      final path = await _audioRecorder.stop();
      if (path != null) _capturedPath = path;
      _capturedDuration = _elapsed;
      if (mounted) setState(() => _stage = _Stage.review);
    } catch (_) {}
  }

  void _beginTimer(int maxSecs, Future<void> Function() onMax) {
    _elapsed = 0;
    _pulse.repeat(reverse: true);
    setState(() => _recording = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= maxSecs) onMax();
    });
  }

  void _endTimer() {
    _timer?.cancel();
    _pulse.stop();
    HapticFeedback.lightImpact();
    setState(() => _recording = false);
  }

  void _discardCapture() {
    HapticFeedback.selectionClick();
    _reviewVideo?.dispose();
    _reviewVideo = null;
    _reviewAudio?.dispose();
    _reviewAudio = null;
    _capturedPath = null;
    _capturedDuration = 0;
    _captionCtrl.clear();
    _shareError = null;
    setState(() => _stage = _Stage.capture);
    if (_mode != _Mode.audio && _cam == null) _initCamera();
  }

  // ── Share ──────────────────────────────────────────────────────────────────

  Future<void> _share() async {
    final path = _capturedPath;
    if (path == null) return;
    HapticFeedback.mediumImpact();
    _reviewVideo?.pause();
    _reviewAudio?.pause();
    setState(() {
      _stage = _Stage.sharing;
      _uploadProgress = 0;
      _shareError = null;
    });

    try {
      final bytes = await File(path).readAsBytes();
      await StoryStore.instance.publish(
        mediaType: switch (_mode) {
          _Mode.photo => 'photo',
          _Mode.video => 'video',
          _Mode.audio => 'audio',
        },
        bytes: bytes,
        caption: _captionCtrl.text,
        durationSeconds: _capturedDuration > 0 ? _capturedDuration : null,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.review;
        _shareError = 'Couldn’t share your story. Check connection and retry.';
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _stage == _Stage.capture ? _buildCaptureLayer() : _buildReviewLayer(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                    onPressed: () {
                      if (_stage == _Stage.sharing) return;
                      _stage == _Stage.review
                          ? _discardCapture()
                          : Navigator.of(context).pop();
                    },
                  ),
                  const Spacer(),
                  if (_stage == _Stage.capture &&
                      _mode != _Mode.audio &&
                      _cameras.length > 1)
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios_rounded,
                          color: Colors.white, size: 24),
                      onPressed: _flipCamera,
                    ),
                ],
              ),
            ),
          ),
          if (_stage == _Stage.sharing) _buildSharingOverlay(),
        ],
      ),
    );
  }

  Widget _buildCaptureLayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview
        if (_mode == _Mode.audio)
          const _AudioCaptureBackdrop()
        else if (_camError)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_rounded,
                    color: Colors.white38, size: 40),
                const SizedBox(height: 10),
                Text('Camera unavailable',
                    style: AppTypography.body(color: Colors.white70)),
                TextButton(
                  onPressed: _initCamera,
                  child: Text('Retry',
                      style:
                          AppTypography.button(color: AppColors.emberWarm)),
                ),
              ],
            ),
          )
        else if (_cam != null && _camReady)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _cam!.value.previewSize?.height ?? 1080,
              height: _cam!.value.previewSize?.width ?? 1920,
              child: CameraPreview(_cam!),
            ),
          )
        else
          const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.emberWarm),
          ),

        // Recording timer
        if (_recording)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, _) => Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.destructive
                                .withValues(alpha: 0.5 + _pulse.value * 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '0:${_elapsed.toString().padLeft(2, '0')}',
                        style: AppTypography.label(
                            size: 13, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Bottom controls: mode rail + shutter
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_recording)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ModeChip(
                          icon: Icons.photo_camera_rounded,
                          label: 'Photo',
                          selected: _mode == _Mode.photo,
                          onTap: () => _switchMode(_Mode.photo),
                        ),
                        _ModeChip(
                          icon: Icons.videocam_rounded,
                          label: 'Video',
                          selected: _mode == _Mode.video,
                          onTap: () => _switchMode(_Mode.video),
                        ),
                        _ModeChip(
                          icon: Icons.mic_rounded,
                          label: 'Audio',
                          selected: _mode == _Mode.audio,
                          onTap: () => _switchMode(_Mode.audio),
                        ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: _onShutter,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3.5),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: _recording ? 30 : 58,
                          height: _recording ? 30 : 58,
                          decoration: BoxDecoration(
                            color: _mode == _Mode.photo
                                ? Colors.white
                                : AppColors.destructive,
                            shape: _recording
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                            borderRadius:
                                _recording ? BorderRadius.circular(8) : null,
                          ),
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
    );
  }

  Widget _buildReviewLayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview of the captured media
        if (_mode == _Mode.photo && _capturedPath != null)
          Image.file(File(_capturedPath!), fit: BoxFit.cover)
        else if (_mode == _Mode.video && _reviewVideo != null)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _reviewVideo!.value.size.width,
              height: _reviewVideo!.value.size.height,
              child: VideoPlayer(_reviewVideo!),
            ),
          )
        else
          _AudioReviewBackdrop(
            path: _capturedPath,
            duration: _capturedDuration,
            playerHolder: (p) => _reviewAudio = p,
          ),

        // Caption + share
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_shareError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _shareError!,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption(
                            color: AppColors.destructive),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _captionCtrl,
                      maxLength: 200,
                      maxLines: 1,
                      style:
                          AppTypography.body(size: 15, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Caption (optional)',
                        hintStyle: AppTypography.body(
                            size: 15, color: Colors.white54),
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.emberGradient,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextButton(
                        onPressed: _share,
                        style: TextButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('Share Story',
                            style: AppTypography.button(
                                size: 16, color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSharingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                value: _uploadProgress > 0.02 ? _uploadProgress : null,
                color: AppColors.emberWarm,
              ),
            ),
            const SizedBox(height: 16),
            Text('Sharing your story…',
                style: AppTypography.body(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ─── Audio visuals ────────────────────────────────────────────────────────────

class _AudioCaptureBackdrop extends StatelessWidget {
  const _AudioCaptureBackdrop();

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_rounded, color: Colors.white24, size: 72),
            const SizedBox(height: 14),
            Text('Tap the button to record a voice story',
                style: AppTypography.body(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

class _AudioReviewBackdrop extends StatefulWidget {
  final String? path;
  final int duration;
  final void Function(ja.AudioPlayer) playerHolder;
  const _AudioReviewBackdrop({
    required this.path,
    required this.duration,
    required this.playerHolder,
  });

  @override
  State<_AudioReviewBackdrop> createState() => _AudioReviewBackdropState();
}

class _AudioReviewBackdropState extends State<_AudioReviewBackdrop> {
  ja.AudioPlayer? _player;
  bool _playing = false;

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (widget.path == null) return;
    if (_player == null) {
      final p = ja.AudioPlayer();
      widget.playerHolder(p);
      await p.setFilePath(widget.path!);
      _player = p;
      p.playerStateStream.listen((st) {
        if (st.processingState == ja.ProcessingState.completed && mounted) {
          setState(() => _playing = false);
          p.seek(Duration.zero);
          p.pause();
        }
      });
    }
    if (_playing) {
      await _player!.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      _player!.play();
      if (mounted) setState(() => _playing = true);
    }
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
        child: GestureDetector(
          onTap: _toggle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.emberGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ember.withValues(alpha: 0.4),
                      blurRadius: 46,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 52,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '0:${widget.duration.toString().padLeft(2, '0')} voice story',
                style: AppTypography.body(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mode chip ────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.emberWarm.withValues(alpha: 0.22)
              : Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.emberWarm
                : Colors.white.withValues(alpha: 0.14),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? AppColors.emberBright : Colors.white70),
            const SizedBox(width: 6),
            Text(label,
                style: AppTypography.label(
                    size: 12.5,
                    color: selected ? AppColors.emberBright : Colors.white70)),
          ],
        ),
      ),
    );
  }
}
