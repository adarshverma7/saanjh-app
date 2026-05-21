import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ShareCardService {
  ShareCardService._();
  static final ShareCardService instance = ShareCardService._();

  Future<void> shareStreakCard(
    GlobalKey cardKey,
    int streakDays,
    String contactName,
  ) async {
    try {
      final bytes = await _captureCard(cardKey);
      if (bytes == null) return;
      final path = await _saveToTemp(bytes, 'saanjh_streak.png');
      final firstName = contactName.split(' ').first;
      await Share.shareXFiles(
        [XFile(path)],
        text: '$streakDays mornings with $firstName on Saanjh 🔥',
      );
    } catch (_) {}
  }

  Future<void> shareTreeCard(
    GlobalKey cardKey, {
    required String seasonLabel,
    required int totalMoments,
    required int yearsCount,
  }) async {
    try {
      final bytes = await _captureCard(cardKey);
      if (bytes == null) return;
      final path = await _saveToTemp(bytes, 'saanjh_tree.png');
      final yearStr = yearsCount == 1 ? '1 year' : '$yearsCount years';
      await Share.shareXFiles(
        [XFile(path)],
        text: '$totalMoments moments · $yearStr · '
            '$seasonLabel ${DateTime.now().year} on Saanjh 🌳',
      );
    } catch (_) {}
  }

  Future<void> shareVoiceCard(
    GlobalKey cardKey,
    String contactName,
  ) async {
    try {
      final bytes = await _captureCard(cardKey);
      if (bytes == null) return;
      final path = await _saveToTemp(bytes, 'saanjh_voice.png');
      await Share.shareXFiles(
        [XFile(path)],
        text: 'A moment from $contactName on Saanjh 🎙 · saanjh.app',
      );
    } catch (_) {}
  }

  Future<Uint8List?> _captureCard(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<String> _saveToTemp(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
