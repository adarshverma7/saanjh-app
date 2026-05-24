import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/entries_api.dart';
import '../../backend/flicker_api.dart';
import '../../backend/notifications_api.dart';
import 'diary_store.dart';

// ─── Pending upload ────────────────────────────────────────────────────────────

class PendingUpload {
  final String pendingLocalId; // matches DiaryEntry.id in the store
  final String diaryId;        // real backend connection UUID
  final String filePath;       // path in app documents dir (persistent)
  final String entryType;      // 'voice' | 'video'
  final String fileExt;        // 'm4a' | 'mp4'
  final String contentType;    // MIME type
  final int durationSeconds;
  final DateTime recordedAt;
  final String? prompt;
  final String? occasionTag;
  final String? parentEntryId;

  PendingUpload({
    required this.pendingLocalId,
    required this.diaryId,
    required this.filePath,
    required this.entryType,
    required this.fileExt,
    required this.contentType,
    required this.durationSeconds,
    required this.recordedAt,
    this.prompt,
    this.occasionTag,
    this.parentEntryId,
  });

  Map<String, dynamic> toJson() => {
    'pendingLocalId':  pendingLocalId,
    'diaryId':         diaryId,
    'filePath':        filePath,
    'entryType':       entryType,
    'fileExt':         fileExt,
    'contentType':     contentType,
    'durationSeconds': durationSeconds,
    'recordedAt':      recordedAt.toIso8601String(),
    if (prompt != null)        'prompt': prompt,
    if (occasionTag != null)   'occasionTag': occasionTag,
    if (parentEntryId != null) 'parentEntryId': parentEntryId,
  };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
    pendingLocalId:  j['pendingLocalId']  as String,
    diaryId:         j['diaryId']         as String,
    filePath:        j['filePath']        as String,
    entryType:       j['entryType']       as String,
    fileExt:         j['fileExt']         as String,
    contentType:     j['contentType']     as String,
    durationSeconds: j['durationSeconds'] as int,
    recordedAt:      DateTime.parse(j['recordedAt'] as String),
    prompt:          j['prompt']          as String?,
    occasionTag:     j['occasionTag']     as String?,
    parentEntryId:   j['parentEntryId']   as String?,
  );
}

// ─── Pending flicker ───────────────────────────────────────────────────────────

class PendingFlicker {
  final String diaryId;
  final DateTime sentAt; // used to detect staleness (discard if not same calendar day)

  PendingFlicker({required this.diaryId, required this.sentAt});

  bool get isStillToday {
    final now = DateTime.now();
    return sentAt.year == now.year &&
        sentAt.month == now.month &&
        sentAt.day == now.day;
  }

  Map<String, dynamic> toJson() => {
    'diaryId': diaryId,
    'sentAt':  sentAt.toIso8601String(),
  };

  factory PendingFlicker.fromJson(Map<String, dynamic> j) => PendingFlicker(
    diaryId: j['diaryId'] as String,
    sentAt:  DateTime.parse(j['sentAt'] as String),
  );
}

// ─── Pending device-token registration ────────────────────────────────────────

class PendingTokenReg {
  final String deviceId;
  final String fcmToken;
  final String? appVersion;
  final String? platform;

  PendingTokenReg({
    required this.deviceId,
    required this.fcmToken,
    this.appVersion,
    this.platform,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'fcmToken': fcmToken,
    if (appVersion != null) 'appVersion': appVersion,
    if (platform != null)   'platform':   platform,
  };

  factory PendingTokenReg.fromJson(Map<String, dynamic> j) => PendingTokenReg(
    deviceId:   j['deviceId']   as String,
    fcmToken:   j['fcmToken']   as String,
    appVersion: j['appVersion'] as String?,
    platform:   j['platform']   as String?,
  );
}

// ─── SendQueueStore ────────────────────────────────────────────────────────────

class SendQueueStore extends ChangeNotifier {
  SendQueueStore._();
  static final SendQueueStore instance = SendQueueStore._();

  static const _kUploadKey  = 'send_queue_v1';
  static const _kFlickerKey = 'flicker_queue_v1';
  static const _kTokenKey   = 'token_queue_v1';

  final List<PendingUpload>   _uploads  = [];
  final List<PendingFlicker>  _flickers = [];
  final List<PendingTokenReg> _tokens   = [];

  bool _isProcessing = false;

  List<PendingUpload>   get uploads  => List.unmodifiable(_uploads);
  List<PendingFlicker>  get flickers => List.unmodifiable(_flickers);
  List<PendingTokenReg> get tokens   => List.unmodifiable(_tokens);

  bool get hasPending =>
      _uploads.isNotEmpty || _flickers.isNotEmpty || _tokens.isNotEmpty;

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Load all three queues from SharedPreferences. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;

    // Uploads
    try {
      final raw = prefs.getString(_kUploadKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final item in list) {
          final u = PendingUpload.fromJson(item);
          if (await File(u.filePath).exists()) {
            _uploads.add(u);
            changed = true;
          }
        }
      }
    } catch (_) {}

    // Flickers — skip stale ones (not same calendar day)
    try {
      final raw = prefs.getString(_kFlickerKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final item in list) {
          final f = PendingFlicker.fromJson(item);
          if (f.isStillToday) {
            _flickers.add(f);
            changed = true;
          }
        }
        // Persist pruned list (remove stale entries).
        await _persistFlickers(prefs);
      }
    } catch (_) {}

    // Token registrations
    try {
      final raw = prefs.getString(_kTokenKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final item in list) {
          _tokens.add(PendingTokenReg.fromJson(item));
          changed = true;
        }
      }
    } catch (_) {}

    if (changed) notifyListeners();
  }

  // ── Enqueue ───────────────────────────────────────────────────────────────

  /// Queue a failed media upload. Copies temp file to permanent storage.
  Future<void> enqueue({
    required String pendingLocalId,
    required String diaryId,
    required String sourcePath,
    required String entryType,
    required String fileExt,
    required String contentType,
    required int durationSeconds,
    required DateTime recordedAt,
    String? prompt,
    String? occasionTag,
    String? parentEntryId,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final destPath = '${dir.path}/pending_$pendingLocalId.$fileExt';
      if (!await File(destPath).exists()) {
        await File(sourcePath).copy(destPath);
      }
      _uploads.add(PendingUpload(
        pendingLocalId:  pendingLocalId,
        diaryId:         diaryId,
        filePath:        destPath,
        entryType:       entryType,
        fileExt:         fileExt,
        contentType:     contentType,
        durationSeconds: durationSeconds,
        recordedAt:      recordedAt,
        prompt:          prompt,
        occasionTag:     occasionTag,
        parentEntryId:   parentEntryId,
      ));
      final prefs = await SharedPreferences.getInstance();
      await _persistUploads(prefs);
      notifyListeners();
    } catch (_) {}
  }

  /// Queue a flicker that failed to reach the backend.
  /// Only today's flickers are ever retried.
  Future<void> enqueueFlicker(String diaryId) async {
    // Deduplicate: only one pending flicker per connection per day.
    if (_flickers.any((f) => f.diaryId == diaryId && f.isStillToday)) return;
    _flickers.add(PendingFlicker(diaryId: diaryId, sentAt: DateTime.now()));
    final prefs = await SharedPreferences.getInstance();
    await _persistFlickers(prefs);
    notifyListeners();
  }

  /// Queue a device-token registration that failed offline.
  Future<void> enqueueTokenReg({
    required String deviceId,
    required String fcmToken,
    String? appVersion,
    String? platform,
  }) async {
    // Replace any existing queued reg for the same device (token may have rotated).
    _tokens.removeWhere((t) => t.deviceId == deviceId);
    _tokens.add(PendingTokenReg(
      deviceId:   deviceId,
      fcmToken:   fcmToken,
      appVersion: appVersion,
      platform:   platform,
    ));
    final prefs = await SharedPreferences.getInstance();
    await _persistTokens(prefs);
    notifyListeners();
  }

  // ── Process ───────────────────────────────────────────────────────────────

  /// Retry all pending items. Safe to call multiple times (guarded by flag).
  Future<void> processQueue() async {
    if (_isProcessing) return;
    if (!hasPending) return;
    _isProcessing = true;

    final prefs = await SharedPreferences.getInstance();
    await _processUploads(prefs);
    await _processFlickers(prefs);
    await _processTokenRegs(prefs);

    _isProcessing = false;
  }

  Future<void> _processUploads(SharedPreferences prefs) async {
    final toProcess = List<PendingUpload>.from(_uploads);
    for (final upload in toProcess) {
      try {
        final file = File(upload.filePath);
        if (!await file.exists()) {
          _uploads.remove(upload);
          await _persistUploads(prefs);
          continue;
        }

        final bytes = await file.readAsBytes();

        final result = await EntriesApi.instance.getUploadUrl(
          connectionId:    upload.diaryId,
          entryType:       upload.entryType,
          fileExtension:   upload.fileExt,
          durationSeconds: upload.durationSeconds,
          fileSizeBytes:   bytes.length,
        );

        await EntriesApi.instance.uploadToStorage(
          uploadUrl:   result.uploadUrl,
          bytes:       bytes,
          contentType: upload.contentType,
        );

        await EntriesApi.instance.createEntry(
          connectionId:    upload.diaryId,
          entryType:       upload.entryType,
          mediaKey:        result.mediaKey,
          durationSeconds: upload.durationSeconds,
          recordedAt:      upload.recordedAt,
        );

        DiaryStore.instance.markUploadComplete(upload.pendingLocalId, result.entryId);

        _uploads.remove(upload);
        await _persistUploads(prefs);
        notifyListeners();

        try { await file.delete(); } catch (_) {}
      } catch (_) {
        // Still offline — leave in queue.
      }
    }
  }

  Future<void> _processFlickers(SharedPreferences prefs) async {
    final toProcess = List<PendingFlicker>.from(_flickers);
    for (final flicker in toProcess) {
      // Discard stale flickers (sent on a previous calendar day).
      if (!flicker.isStillToday) {
        _flickers.remove(flicker);
        await _persistFlickers(prefs);
        continue;
      }
      try {
        await FlickerApi.instance.sendFlicker(flicker.diaryId);
        _flickers.remove(flicker);
        await _persistFlickers(prefs);
        notifyListeners();
      } catch (_) {
        // Still offline — leave in queue.
      }
    }
  }

  Future<void> _processTokenRegs(SharedPreferences prefs) async {
    final toProcess = List<PendingTokenReg>.from(_tokens);
    for (final reg in toProcess) {
      try {
        await NotificationsApi.instance.registerDeviceToken(
          deviceId:   reg.deviceId,
          fcmToken:   reg.fcmToken,
          appVersion: reg.appVersion,
          platform:   reg.platform,
        );
        _tokens.remove(reg);
        await _persistTokens(prefs);
        notifyListeners();
      } catch (_) {
        // Still offline — leave in queue.
      }
    }
  }

  // ── Persist ───────────────────────────────────────────────────────────────

  Future<void> _persistUploads(SharedPreferences prefs) async {
    try {
      await prefs.setString(
        _kUploadKey, jsonEncode(_uploads.map((u) => u.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _persistFlickers(SharedPreferences prefs) async {
    try {
      await prefs.setString(
        _kFlickerKey, jsonEncode(_flickers.map((f) => f.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _persistTokens(SharedPreferences prefs) async {
    try {
      await prefs.setString(
        _kTokenKey, jsonEncode(_tokens.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }
}
