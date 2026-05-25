import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../../backend/entries_api.dart';
import '../../services/share_card_service.dart';
import '../../services/transcription_service.dart';
import '../../state/diary_store.dart';
import '../../state/personal_reflection_store.dart';
import '../../state/send_queue_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/voice_share_card.dart';

enum _Mode { voice, video }
enum _RecState { idle, recording, review }

class RecordScreen extends StatefulWidget {
  final bool isVideo;
  final bool autoStart;
  final List<String>? broadcastTo;
  final List<String>? broadcastNames;
  final String? prompt;
  // When true: recording is a private personal reflection, never shared.
  // UI styling and save behaviour fully implemented in Prompt 27.
  final bool isPrivateReflection;
  // Occasion tag applied to the sent note (e.g. "🪔 Diwali").
  final String? occasionTag;
  // Single-diary target when not in broadcast mode.
  final String? targetDiaryId;
  // When reacting to a past memory, the parent entry's id.
  final String? parentEntryId;
  // Human-readable context shown in a banner above the record button.
  final String? reactionContext;

  const RecordScreen({
    super.key,
    this.isVideo = false,
    this.autoStart = false,
    this.broadcastTo,
    this.broadcastNames,
    this.prompt,
    this.isPrivateReflection = false,
    this.occasionTag,
    this.targetDiaryId,
    this.parentEntryId,
    this.reactionContext,
  });

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with TickerProviderStateMixin {
  late _Mode _mode;
  _RecState _recState = _RecState.idle;

  // ─── Voice ──────────────────────────────────────────────────
  int _elapsed = 0;
  static const _maxSecs = 20;
  Timer? _timer;
  late final AnimationController _pulseCtrl;
  late final AnimationController _waveCtrl;

  // ─── Camera / Video ──────────────────────────────────────────
  List<CameraDescription> _cameras = [];
  CameraController? _camCtrl;
  bool _camReady = false;
  bool _camError = false;
  int _camIdx = 0;
  XFile? _recordedFile;
  VideoPlayerController? _vpCtrl;
  bool _vpReady = false;

  // ─── Audio recorder ───────────────────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _audioPath;
  bool _isSending = false;
  double? _uploadProgress; // 0.0–1.0 while uploading, null otherwise

  @override
  void initState() {
    super.initState();
    _mode = widget.isVideo ? _Mode.video : _Mode.voice;
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _waveCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

    if (_mode == _Mode.video) {
      _initCamera();
    } else if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _startVoice();
        });
      });
    }

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _camCtrl?.dispose();
    _vpCtrl?.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ─── Camera ───────────────────────────────────────────────────

  Future<void> _initCamera() async {
    setState(() { _camReady = false; _camError = false; });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _camError = true);
        return;
      }
      final camCtrl = CameraController(
        _cameras[_camIdx % _cameras.length],
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await camCtrl.initialize();
      _camCtrl?.dispose();
      _camCtrl = camCtrl;
      if (mounted) setState(() => _camReady = true);
    } catch (_) {
      if (mounted) setState(() => _camError = true);
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    HapticFeedback.selectionClick();
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _initCamera();
  }

  // ─── Mode toggle ──────────────────────────────────────────────

  void _switchMode(_Mode m) async {
    if (m == _mode) return;
    HapticFeedback.selectionClick();
    // Discard any in-progress recording.
    if (_recState == _RecState.recording) await _stopRecording();
    _resetState();
    setState(() => _mode = m);
    if (m == _Mode.video) {
      _initCamera();
    } else {
      _camCtrl?.dispose();
      _camCtrl = null;
      _camReady = false;
      setState(() {});
    }
  }

  void _resetState() {
    _timer?.cancel();
    _pulseCtrl.stop();
    _waveCtrl.stop();
    _vpCtrl?.dispose();
    _vpCtrl = null;
    _vpReady = false;
    _recordedFile = null;
    _audioPath = null;
    _elapsed = 0;
    _recState = _RecState.idle;
  }

  // ─── Voice recording ──────────────────────────────────────────

  Future<void> _startVoice() async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path,
      );
    } catch (_) {
      // Continue with UI-only if recording fails (e.g. permission denied).
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _pulseCtrl.repeat(reverse: true);
    _waveCtrl.repeat();
    _elapsed = 0;
    setState(() => _recState = _RecState.recording);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _maxSecs) _stopRecording();
    });
  }

  // ─── Video recording ──────────────────────────────────────────

  Future<void> _startVideo() async {
    if (_camCtrl == null || !_camReady) return;
    HapticFeedback.mediumImpact();
    try {
      await _camCtrl!.startVideoRecording();
      _elapsed = 0;
      setState(() => _recState = _RecState.recording);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed++);
        if (_elapsed >= _maxSecs) _stopRecording();
      });
    } catch (_) {}
  }

  // ─── Stop (both modes) ────────────────────────────────────────

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _pulseCtrl.stop();
    _waveCtrl.stop();
    HapticFeedback.lightImpact();

    if (_mode == _Mode.voice) {
      try {
        _audioPath = await _audioRecorder.stop();
      } catch (_) {}
    } else if (_camCtrl != null) {
      try {
        _recordedFile = await _camCtrl!.stopVideoRecording();
        await _initVideoPlayer();
      } catch (_) {}
    }

    if (mounted) setState(() => _recState = _RecState.review);
  }

  Future<void> _initVideoPlayer() async {
    if (_recordedFile == null) return;
    final ctrl = VideoPlayerController.file(File(_recordedFile!.path));
    await ctrl.initialize();
    await ctrl.setLooping(true);
    await ctrl.play();
    _vpCtrl = ctrl;
    if (mounted) setState(() => _vpReady = true);
  }

  void _startRecording() {
    if (_mode == _Mode.voice) {
      _startVoice();
    } else {
      _startVideo();
    }
  }

  // ─── Discard / Send ───────────────────────────────────────────

  void _discard() {
    HapticFeedback.selectionClick();
    _resetState();
    setState(() {});
  }

  Future<void> _send() async {
    HapticFeedback.mediumImpact();

    // Private reflection — goes to PersonalReflectionStore, not shared.
    if (widget.isPrivateReflection) {
      PersonalReflectionStore.instance.addReflection(PersonalReflection(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        audioPath: _audioPath ?? _recordedFile?.path ?? '',
        transcript: null,
        createdAt: DateTime.now(),
        prompt: widget.prompt,
      ));
      context.pop();
      return;
    }

    final store = DiaryStore.instance;
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    final time = '$h:$m ${now.period.name.toUpperCase()}';
    final filePath = _mode == _Mode.voice ? _audioPath : _recordedFile?.path;
    final sendTime = DateTime.now();
    final entryType  = _mode == _Mode.voice ? 'voice' : 'video';
    final fileExt    = _mode == _Mode.voice ? 'm4a' : 'mp4';
    // audio/mp4 is the correct MIME type for .m4a (AAC in MPEG-4 container).
    // audio/m4a is non-standard and Supabase may reject or misclassify it.
    final contentType = _mode == _Mode.voice ? 'audio/mp4' : 'video/mp4';

    // Determine all target diary IDs (broadcast list OR single target).
    final targets = (widget.broadcastTo?.isNotEmpty == true)
        ? widget.broadcastTo!
        : (widget.targetDiaryId != null ? [widget.targetDiaryId!] : <String>[]);

    if (filePath != null && targets.isNotEmpty) {
      // ── Upload to backend (optimistic: show pending immediately) ───────────
      setState(() => _isSending = true);

      // Unique prefix for all pending entries created in this send batch.
      final batchId = sendTime.millisecondsSinceEpoch.toString();

      // Clamp to backend's accepted range: @Min(1) @Max(20).
      final effectiveDuration = _elapsed.clamp(1, 20);

      // Add pending entries immediately so the user sees "Sending..." at once.
      for (final id in targets) {
        final localId = '${batchId}_$id';
        final pending = DiaryEntry(
          id:              localId,
          diaryId:         id,
          isMine:          true,
          type:            entryType,
          path:            filePath,
          prompt:          widget.prompt,
          occasionTag:     widget.occasionTag,
          createdAt:       sendTime,
          durationSeconds: effectiveDuration,
          parentEntryId:   widget.parentEntryId,
          isPending:       true,
        );
        if (widget.parentEntryId != null) {
          store.addReaction(widget.parentEntryId!, pending);
        } else {
          store.addEntry(pending);
        }
        store.updateSnippet(id, '⏳ Sending...', time);
        if (widget.occasionTag != null) store.setOccasionTag(id, widget.occasionTag);
      }

      var hasConnectivityFailure = false;

      try {
        final bytes = await File(filePath).readAsBytes();

        if (bytes.length < 1000) {
          for (final id in targets) {
            store.markUploadFailed('${batchId}_$id');
          }
          if (!mounted) return;
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording too short — hold longer to record.')),
          );
          return;
        }

        for (final id in targets) {
          final localId = '${batchId}_$id';
          try {
            final uploadResult = await EntriesApi.instance.getUploadUrl(
              connectionId:    id,
              entryType:       entryType,
              fileExtension:   fileExt,
              durationSeconds: effectiveDuration,
              fileSizeBytes:   bytes.length,
            );

            await EntriesApi.instance.uploadToStorage(
              uploadUrl:   uploadResult.uploadUrl,
              bytes:       bytes,
              contentType: contentType,
              onProgress: (sent, total) {
                if (mounted && total > 0) {
                  setState(() => _uploadProgress = sent / total);
                }
              },
            );

            if (mounted) setState(() => _uploadProgress = null);

            await EntriesApi.instance.createEntry(
              connectionId:    id,
              entryType:       entryType,
              mediaKey:        uploadResult.mediaKey,
              durationSeconds: effectiveDuration,
              recordedAt:      sendTime,
            );

            // Replace pending entry with real backend data.
            store.markUploadComplete(localId, uploadResult.entryId);

            TranscriptionService.instance.transcribeFile(filePath).then((t) {
              if (t != null) store.updateEntryTranscript(uploadResult.entryId, t);
            });
          } catch (e) {
            debugPrint('[upload] ${e.runtimeType}: $e');
            if (mounted) setState(() => _uploadProgress = null);
            hasConnectivityFailure = true;
            // Queue for retry regardless of error type:
            // - Connectivity errors (no internet, timeout) → auto-retried on reconnect
            // - Unknown/SSL errors → retried; permanent failures stay visible with retry btn
            // - Server errors → retried; user can also tap retry manually
            store.markUploadFailed(localId);
            await SendQueueStore.instance.enqueue(
              pendingLocalId:  localId,
              diaryId:         id,
              sourcePath:      filePath,
              entryType:       entryType,
              fileExt:         fileExt,
              contentType:     contentType,
              durationSeconds: effectiveDuration,
              recordedAt:      sendTime,
              prompt:          widget.prompt,
              occasionTag:     widget.occasionTag,
              parentEntryId:   widget.parentEntryId,
            );
          }
        }
      } catch (e) {
        // File read failed or other pre-upload error.
        if (!mounted) return;
        for (final id in targets) {
          store.markUploadFailed('${batchId}_$id');
        }
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_uploadErrorMessage(e))),
        );
        return;
      }

      if (mounted) setState(() => _isSending = false);

      if (hasConnectivityFailure && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet — will send when you\'re back online.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Local-only fallback (no file recorded or no targets).
      final snippet = _mode == _Mode.voice ? '🎙 Voice note' : '🎬 Video clip';
      for (final id in targets) {
        store.updateSnippet(id, snippet, time);
        if (widget.occasionTag != null) store.setOccasionTag(id, widget.occasionTag);
        final entry = DiaryEntry(
          id:            '${sendTime.millisecondsSinceEpoch}_$id',
          diaryId:       id,
          isMine:        true,
          type:          entryType,
          path:          filePath ?? '',
          prompt:        widget.prompt,
          occasionTag:   widget.occasionTag,
          createdAt:     sendTime,
          parentEntryId: widget.parentEntryId,
        );
        if (widget.parentEntryId != null) {
          store.addReaction(widget.parentEntryId!, entry);
        } else {
          store.addEntry(entry);
        }
      }
    }

    // ── Share moment trigger ──────────────────────────────────────────────
    // Show a share sheet on the 1st send ever and every 10th send thereafter.
    // Only for top-level shared entries (not reactions, not private).
    final isShareable = widget.parentEntryId == null && targets.isNotEmpty;
    if (isShareable) {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final count = (prefs.getInt('total_sends') ?? 0) + 1;
      await prefs.setInt('total_sends', count);

      if (!mounted) return;
      if (count == 1 || count % 10 == 0) {
        final contactName = _shareContactName(targets.first);
        final duration = _formatDuration(_elapsed);
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => _ShareMomentSheet(
            contactName: contactName,
            duration: duration,
            createdAt: sendTime,
            seed: filePath?.hashCode ?? targets.first.hashCode,
            isFirstSend: count == 1,
          ),
        );
        if (!mounted) return;
      }
    }

    if (!mounted) return;
    context.pop();
  }

  String _uploadErrorMessage(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Upload timed out. Will retry when connection improves.';
        case DioExceptionType.connectionError:
          return 'No internet connection. Will send when you\'re back online.';
        case DioExceptionType.unknown:
          if (e.error is SocketException) {
            return 'No internet connection. Will send when you\'re back online.';
          }
          return 'Connection error. Will retry automatically.';
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode;
          if (code == 401 || code == 403) {
            return 'Session expired. Please restart the app and try again.';
          }
          if (code != null && code >= 500) {
            return 'Server error ($code). Will retry automatically.';
          }
          return 'Upload failed (error $code). Will retry automatically.';
        default:
          break;
      }
    }
    return 'Send failed. Will retry when connection is available.';
  }

  // Returns the display name of the primary recipient.
  String _shareContactName(String diaryId) {
    if (widget.broadcastNames?.isNotEmpty == true) {
      return widget.broadcastNames!.length == 1
          ? widget.broadcastNames!.first
          : 'everyone';
    }
    try {
      return DiaryStore.instance.diaries
          .firstWhere((d) => d.id == diaryId)
          .displayName;
    } catch (_) {
      return 'them';
    }
  }

  String _formatDuration(int secs) {
    final mm = secs ~/ 60;
    final ss = secs % 60;
    return '$mm:${ss.toString().padLeft(2, '0')}';
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isVideo = _mode == _Mode.video;
    // Private reflections use a deep indigo background for visual distinction.
    final bgColor = widget.isPrivateReflection
        ? const Color(0xFF0A0820)
        : Colors.black;
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Background
          if (!isVideo || !_camReady)
            Positioned.fill(
              child: GlowBackground(
                glowTopFraction: _recState == _RecState.recording ? 0.28 : 0.18,
                glowSize: _recState == _RecState.recording ? 480 : 360,
              ),
            ),

          // Camera preview / video review
          if (isVideo) _buildCameraArea(),

          // Overlaid UI
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  mode: _mode,
                  onClose: () => context.pop(),
                  onFlip: isVideo && _cameras.length > 1 ? _flipCamera : null,
                  recState: _recState,
                  elapsed: _elapsed,
                  maxSecs: _maxSecs,
                ),
                if (widget.broadcastTo != null &&
                    widget.broadcastTo!.isNotEmpty)
                  _BroadcastBadge(
                      names: widget.broadcastNames ?? widget.broadcastTo!),
                if (widget.parentEntryId != null &&
                    widget.reactionContext != null)
                  _ReactionContextBanner(
                      context: widget.reactionContext!),
                if (_recState == _RecState.idle) ...[
                  const SizedBox(height: 12),
                  _ModeToggle(mode: _mode, onSwitch: _switchMode),
                ],
                const Spacer(),
                _BottomControls(
                  mode: _mode,
                  recState: _recState,
                  elapsed: _elapsed,
                  maxSecs: _maxSecs,
                  pulseCtrl: _pulseCtrl,
                  waveCtrl: _waveCtrl,
                  onStart: _startRecording,
                  onStop: _stopRecording,
                  onDiscard: _discard,
                  onSend: _send,
                  camReady: _camReady,
                  camError: _camError,
                  prompt: widget.prompt,
                  occasionTag: widget.occasionTag,
                  isPrivateReflection: widget.isPrivateReflection,
                  isSending: _isSending,
                  uploadProgress: _uploadProgress,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraArea() {
    if (_recState == _RecState.review && _vpReady && _vpCtrl != null) {
      // Video review — full screen playback.
      return Positioned.fill(
        child: AspectRatio(
          aspectRatio: _vpCtrl!.value.aspectRatio,
          child: VideoPlayer(_vpCtrl!),
        ),
      );
    }
    if (_camError || !_camReady) {
      return Positioned.fill(
        child: Container(
          color: Colors.black,
          child: Center(
            child: _camError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_rounded,
                          size: 48, color: AppColors.textFaint),
                      const SizedBox(height: 12),
                      Text('Camera not available',
                          style: AppTypography.label(
                              size: 14, color: AppColors.textMuted)),
                    ],
                  )
                : const _CamInitRing(),
          ),
        ),
      );
    }
    // Live preview.
    return Positioned.fill(
      child: CameraPreview(_camCtrl!),
    );
  }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final _Mode mode;
  final _RecState recState;
  final int elapsed;
  final int maxSecs;
  final VoidCallback onClose;
  final VoidCallback? onFlip;

  const _TopBar({
    required this.mode,
    required this.recState,
    required this.elapsed,
    required this.maxSecs,
    required this.onClose,
    required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15), width: 1),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 18, color: Colors.white),
            ),
          ),
          const Spacer(),
          if (recState == _RecState.recording) _RecTimer(elapsed: elapsed, maxSecs: maxSecs),
          if (recState == _RecState.review)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.successGreen.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.successGreen.withValues(alpha: 0.4),
                    width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: AppColors.successGreen),
                  const SizedBox(width: 6),
                  Text('Ready to send',
                      style: AppTypography.label(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: const Color(0xFF7CD992))),
                ],
              ),
            ),
          const Spacer(),
          if (onFlip != null)
            GestureDetector(
              onTap: onFlip,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.35),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15), width: 1),
                ),
                child: const Icon(Icons.flip_camera_ios_rounded,
                    size: 18, color: Colors.white),
              ),
            )
          else
            const SizedBox(width: 36),
        ],
      ),
    );
  }
}

class _RecTimer extends StatelessWidget {
  final int elapsed;
  final int maxSecs;
  const _RecTimer({required this.elapsed, required this.maxSecs});

  @override
  Widget build(BuildContext context) {
    final remaining = maxSecs - elapsed;
    final isUrgent = remaining <= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isUrgent
            ? AppColors.destructive.withValues(alpha: 0.2)
            : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUrgent
              ? AppColors.destructive.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isUrgent ? AppColors.destructive : AppColors.destructive,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '0:${elapsed.toString().padLeft(2, '0')} / 0:$maxSecs',
            style: AppTypography.timestamp(
              color: isUrgent ? const Color(0xFFFF8A82) : Colors.white,
            ).copyWith(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ─── Mode toggle ──────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onSwitch;

  const _ModeToggle({required this.mode, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 80),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.10), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(child: _ModeTab(
            label: '🎙 Voice',
            selected: mode == _Mode.voice,
            onTap: () => onSwitch(_Mode.voice),
          )),
          Expanded(child: _ModeTab(
            label: '🎥 Video',
            selected: mode == _Mode.video,
            onTap: () => onSwitch(_Mode.video),
          )),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.emberWarm : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? AppShadows.emberGlow(
                  intensity: 0.45, blur: 14, offset: const Offset(0, 3))
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.label(
              size: 13,
              weight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom controls ──────────────────────────────────────────────────────────

class _BottomControls extends StatelessWidget {
  final _Mode mode;
  final _RecState recState;
  final int elapsed;
  final int maxSecs;
  final AnimationController pulseCtrl;
  final AnimationController waveCtrl;
  final VoidCallback onStart;
  final Future<void> Function() onStop;
  final VoidCallback onDiscard;
  final VoidCallback onSend;
  final bool camReady;
  final bool camError;
  final String? prompt;
  final String? occasionTag;
  final bool isPrivateReflection;
  final bool isSending;
  final double? uploadProgress;

  const _BottomControls({
    required this.mode,
    required this.recState,
    required this.elapsed,
    required this.maxSecs,
    required this.pulseCtrl,
    required this.waveCtrl,
    required this.onStart,
    required this.onStop,
    required this.onDiscard,
    required this.onSend,
    required this.camReady,
    required this.camError,
    this.prompt,
    this.occasionTag,
    this.isPrivateReflection = false,
    this.isSending = false,
    this.uploadProgress,
  });

  @override
  Widget build(BuildContext context) {
    if (recState == _RecState.review) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CtaPrimary(
              label: isPrivateReflection
                  ? '🔒  Save to my journal  →'
                  : mode == _Mode.video
                      ? '🎥  Send this video  →'
                      : '🎙  Send this note  →',
              onPressed: isSending ? null : onSend,
              loading: isSending,
            ),
            if (isSending && uploadProgress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: uploadProgress,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.emberWarm),
                  minHeight: 3,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: onDiscard,
              child: Text(
                'Discard and re-record',
                style: AppTypography.label(
                    size: 13, color: AppColors.textMuted),
              ),
            ),
            if (isPrivateReflection) ...[
              const SizedBox(height: 8),
              Text(
                'This is just for you. No one else can hear this. 🔒',
                style: AppTypography.label(
                    size: 12, color: AppColors.textFaint),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Occasion chip — shown above record button when occasion recording
        if (occasionTag != null && recState == _RecState.idle) ...[
          _OccasionChip(tag: occasionTag!),
          const SizedBox(height: 12),
        ],
        if (mode == _Mode.voice) ...[
          if (recState == _RecState.recording)
            _Waveform(ctrl: waveCtrl)
          else if (prompt != null && recState == _RecState.idle)
            _PromptChip(text: prompt!)
          else
            Text(
              'A quiet moment, sent with love.',
              style: AppTypography.serifItalic(size: 18),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 24),
          if (recState == _RecState.recording)
            _VoiceProgressRing(elapsed: elapsed, maxSecs: maxSecs),
          if (recState == _RecState.idle)
            Text('Up to 20 seconds.',
                style:
                    AppTypography.label(size: 13, color: AppColors.textFaint)),
          const SizedBox(height: 28),
        ] else ...[
          // Video idle: progress bar on bottom
          if (recState == _RecState.recording) ...[
            _VideoProgressBar(elapsed: elapsed, maxSecs: maxSecs),
            const SizedBox(height: 24),
          ],
          if (recState == _RecState.idle && !camReady && !camError)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text('Initialising camera…',
                  style: AppTypography.label(
                      size: 13, color: AppColors.textFaint)),
            ),
        ],
        _RecordButton(
          mode: mode,
          recState: recState,
          pulseCtrl: pulseCtrl,
          onStart: onStart,
          onStop: onStop,
          camReady: camReady,
          camError: camError,
        ),
        const SizedBox(height: 12),
        Text(
          recState == _RecState.idle
              ? 'Tap to ${mode == _Mode.voice ? 'record' : 'record video'}'
              : 'Tap to finish',
          style: AppTypography.label(size: 13, color: AppColors.textFaint),
        ),
      ],
    );
  }
}

// ─── Voice progress ring ──────────────────────────────────────────────────────

class _VoiceProgressRing extends StatelessWidget {
  final int elapsed;
  final int maxSecs;
  const _VoiceProgressRing({required this.elapsed, required this.maxSecs});

  @override
  Widget build(BuildContext context) {
    final progress = elapsed / maxSecs;
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: _RingPainter(progress: progress),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '0:${elapsed.toString().padLeft(2, '0')}',
                style: AppTypography.display(size: 28),
              ),
              Text('of 0:$maxSecs',
                  style: AppTypography.label(
                      size: 11, color: AppColors.textFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - 8) / 2;
    canvas.drawCircle(
      c, r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..shader = const LinearGradient(
                colors: [AppColors.emberWarm, AppColors.ember])
            .createShader(Rect.fromCircle(center: c, radius: r))
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.progress != progress;
}

// ─── Video progress bar ───────────────────────────────────────────────────────

class _VideoProgressBar extends StatelessWidget {
  final int elapsed;
  final int maxSecs;
  const _VideoProgressBar({required this.elapsed, required this.maxSecs});

  @override
  Widget build(BuildContext context) {
    final progress = elapsed / maxSecs;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0:${elapsed.toString().padLeft(2, '0')}',
                  style: AppTypography.label(
                      size: 12, color: AppColors.emberBright)),
              Text('0:$maxSecs',
                  style: AppTypography.label(
                      size: 12, color: AppColors.textFaint)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.emberWarm),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Waveform ─────────────────────────────────────────────────────────────────

class _Waveform extends StatelessWidget {
  final AnimationController ctrl;
  const _Waveform({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, w) => SizedBox(
        width: 220,
        height: 36,
        child: CustomPaint(painter: _WavePainter(t: ctrl.value)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double t;
  _WavePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint()
      ..color = AppColors.emberWarm.withValues(alpha: 0.75)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const n = 26;
    final step = size.width / n;
    for (int i = 0; i < n; i++) {
      final phase = (t * 2 * math.pi + i * 0.4) % (2 * math.pi);
      final base = 0.25 + 0.35 * rng.nextDouble();
      final h = size.height * (base + 0.38 * math.sin(phase).abs());
      final x = i * step + step / 2;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.t != t;
}

// ─── Record button ────────────────────────────────────────────────────────────

class _RecordButton extends StatefulWidget {
  final _Mode mode;
  final _RecState recState;
  final AnimationController pulseCtrl;
  final VoidCallback onStart;
  final Future<void> Function() onStop;
  final bool camReady;
  final bool camError;

  const _RecordButton({
    required this.mode,
    required this.recState,
    required this.pulseCtrl,
    required this.onStart,
    required this.onStop,
    required this.camReady,
    required this.camError,
  });

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton> {
  bool _pressed = false;

  bool get _enabled {
    if (widget.mode == _Mode.video &&
        !widget.camReady &&
        widget.recState == _RecState.idle) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.recState == _RecState.recording;

    return Semantics(
      label: isRecording ? 'Stop recording' : 'Record a voice or video note',
      button: true,
      child: GestureDetector(
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
      onTap: _enabled
          ? () async {
              if (isRecording) {
                await widget.onStop();
              } else {
                widget.onStart();
              }
            }
          : null,
      child: AnimatedBuilder(
        animation: widget.pulseCtrl,
        builder: (_, child) {
          final glowScale = isRecording
              ? 1.0 + 0.08 * widget.pulseCtrl.value
              : 1.0;
          return AnimatedScale(
            scale: _pressed ? 0.93 : 1.0,
            duration: AppMotion.fast,
            child: Transform.scale(scale: glowScale, child: child),
          );
        },
        child: _ButtonBody(
          mode: widget.mode,
          isRecording: isRecording,
          enabled: _enabled,
        ),
      ),
      ), // close Semantics
    );
  }
}

// ─── Prompt chip (shown when recording was triggered from a prompt) ───────────

class _PromptChip extends StatelessWidget {
  final String text;
  const _PromptChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.ember.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.emberWarm.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_quote_rounded,
                size: 14, color: AppColors.emberWarm),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: AppTypography.serifItalic(size: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Occasion chip (shown when recording is tagged for a festival/occasion) ───

class _OccasionChip extends StatelessWidget {
  final String tag; // e.g. "🪔 Diwali"
  const _OccasionChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.emberWarm.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.emberWarm.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tag.split(' ').first, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              tag.split(' ').skip(1).join(' '),
              style: AppTypography.label(
                size: 13,
                color: AppColors.emberWarm,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Camera init ring (pulsing amber ring while camera starts) ────────────────

class _CamInitRing extends StatefulWidget {
  const _CamInitRing();

  @override
  State<_CamInitRing> createState() => _CamInitRingState();
}

class _CamInitRingState extends State<_CamInitRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final alpha = 0.15 + _ctrl.value * 0.15; // 0.15→0.30
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.emberWarm.withValues(alpha: alpha),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ember.withValues(alpha: alpha * 0.6),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.videocam_rounded,
              size: 20,
              color: AppColors.emberWarm.withValues(alpha: alpha * 2),
            ),
          ),
        );
      },
    );
  }
}

// ─── Reaction context banner ──────────────────────────────────────────────────

class _ReactionContextBanner extends StatelessWidget {
  final String context;
  const _ReactionContextBanner({required this.context});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.ember.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.emberWarm.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            const Text('🎙', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                this.context,
                style: AppTypography.serifItalic(
                    size: 13, color: AppColors.emberBright),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Broadcast badge ──────────────────────────────────────────────────────────

class _BroadcastBadge extends StatelessWidget {
  final List<String> names;
  const _BroadcastBadge({required this.names});

  @override
  Widget build(BuildContext context) {
    final label = names.length == 1
        ? 'Sending to ${names.first}'
        : 'Sending to ${names.take(2).join(', ')}'
            '${names.length > 2 ? ' +${names.length - 2} more' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.ember.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.emberWarm.withValues(alpha: 0.30), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_rounded,
                size: 14, color: AppColors.emberBright),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: AppTypography.label(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.emberBright),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Button body ──────────────────────────────────────────────────────────────

class _ButtonBody extends StatelessWidget {
  final _Mode mode;
  final bool isRecording;
  final bool enabled;

  const _ButtonBody({
    required this.mode,
    required this.isRecording,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    if (isRecording) {
      // Stop button — red square inside circle.
      return Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.destructive.withValues(alpha: 0.18),
          border: Border.all(
              color: AppColors.destructive.withValues(alpha: 0.55),
              width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.destructive.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: AppColors.destructive,
            ),
          ),
        ),
      );
    }

    final icon = mode == _Mode.voice ? Icons.mic_rounded : Icons.videocam_rounded;
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: enabled ? AppColors.emberGradient : null,
        color: enabled ? null : Colors.white.withValues(alpha: 0.08),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.ember.withValues(alpha: 0.5),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Icon(icon,
          size: 36, color: enabled ? Colors.white : AppColors.textFaint),
    );
  }
}

// ─── Share moment sheet ───────────────────────────────────────────────────────

class _ShareMomentSheet extends StatefulWidget {
  final String contactName;
  final String duration;
  final DateTime createdAt;
  final int seed;
  final bool isFirstSend;

  const _ShareMomentSheet({
    required this.contactName,
    required this.duration,
    required this.createdAt,
    required this.seed,
    required this.isFirstSend,
  });

  @override
  State<_ShareMomentSheet> createState() => _ShareMomentSheetState();
}

class _ShareMomentSheetState extends State<_ShareMomentSheet> {
  // Key on the off-screen card used for image capture.
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await ShareCardService.instance.shareVoiceCard(
          _cardKey, widget.contactName);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isFirstSend
        ? 'Your first voice on Saanjh ✨'
        : 'Share this moment 🎙';
    final sub = widget.isFirstSend
        ? 'Let someone know you\'re here.'
        : '${widget.contactName}\'s voice. Worth sharing.';

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, MediaQuery.of(context).padding.bottom + 24),
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title & subtitle
          Text(title,
              style: AppTypography.title(size: 20),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(sub,
              style: AppTypography.serifItalic(size: 15),
              textAlign: TextAlign.center),

          const SizedBox(height: 20),

          // Preview card (scaled down from 400×400)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 260,
              height: 260,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 400,
                  height: 400,
                  child: VoiceShareCard(
                    contactName: widget.contactName,
                    duration: widget.duration,
                    createdAt: widget.createdAt,
                    seed: widget.seed,
                  ),
                ),
              ),
            ),
          ),

          // Off-screen card for actual capture (GlobalKey attached here).
          Offstage(
            child: VoiceShareCard(
              key: _cardKey,
              contactName: widget.contactName,
              duration: widget.duration,
              createdAt: widget.createdAt,
              seed: widget.seed,
            ),
          ),

          const SizedBox(height: 24),

          // Share CTA
          GestureDetector(
            onTap: _sharing ? null : _share,
            child: AnimatedOpacity(
              opacity: _sharing ? 0.55 : 1.0,
              duration: AppMotion.fast,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.emberGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _sharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text('Share this moment',
                          style: AppTypography.button(color: Colors.white)),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Dismiss
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Maybe later',
                style: AppTypography.label(
                    size: 14, color: AppColors.textFaint)),
          ),
        ],
      ),
    );
  }
}

