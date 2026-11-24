import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_file_store.dart';

/// TTS & Audio Pronunciation Service with local `.wav` file caching on Android/iOS
/// and instant Web Speech API / remote audio URL playback on Web (without `dart:io`).
class TtsCacheService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final TtsFileStore _fileStore = TtsFileStore();
  bool _initialized = false;

  /// True only on Android / iOS where `FlutterTts.synthesizeToFile` is supported.
  /// On Web, pronunciation uses Web Speech API (`window.speechSynthesis`) or remote audio URLs.
  bool get isDiskCacheSupported => !kIsWeb && _fileStore.isSupported;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _fileStore.init();
    } catch (_) {}
    _initialized = true;
  }

  String _cacheFileName(String word, String accent) {
    final normalized = '${accent.toLowerCase()}:${word.trim().toLowerCase()}';
    final digest = md5.convert(utf8.encode(normalized)).toString();
    final safePrefix = word.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final safeAccent = accent.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '${safePrefix}_${safeAccent}_$digest.wav';
  }

  /// Speaks [word] in the requested [accent] (`en-US` for American English or
  /// `en-GB` for British English) using cached synthesized audio if available,
  /// or remote [audioUrl] if provided, otherwise synthesizes via TTS.
  Future<void> speak(
    String word, {
    String audioUrl = '',
    String accent = 'en-US',
  }) async {
    final clean = word.trim();
    if (clean.isEmpty) return;
    await _ensureInitialized();

    try {
      // 1. On native platforms, check local disk cache first
      if (isDiskCacheSupported) {
        final existingPath = await _fileStore
            .getExistingFilePath(_cacheFileName(clean, accent));
        if (existingPath != null) {
          await _player.stop();
          await _player.play(DeviceFileSource(existingPath));
          return;
        }
      }

      // 2. If remote dictionary audio URL is available and matches default accent, play it
      if (audioUrl.isNotEmpty && accent == 'en-US') {
        try {
          await _player.stop();
          await _player.play(UrlSource(audioUrl));
          return;
        } catch (_) {
          // Fall through to TTS
        }
      }

      // 3. Speak immediately via FlutterTts (Android TTS Engine or Web Speech API)
      await _tts.stop();
      await _tts.setLanguage(accent);
      await _tts.speak(clean);

      // 4. Asynchronously synthesize to cache file on Android/iOS for instant replay next time
      if (isDiskCacheSupported) {
        final targetPath = await _fileStore
            .getTargetFilePathIfMissing(_cacheFileName(clean, accent));
        if (targetPath != null) {
          unawaited(_synthesizeToCache(clean, targetPath, accent));
        }
      }
    } catch (_) {}
  }

  Future<void> _synthesizeToCache(
    String word,
    String filePath,
    String accent,
  ) async {
    try {
      await _tts.setLanguage(accent);
      await _tts.synthesizeToFile(word, filePath);
    } catch (_) {}
  }

  /// Pre-warms TTS cache for upcoming study session words (Android/iOS only).
  Future<void> preloadWords(
    List<String> words, {
    String accent = 'en-US',
  }) async {
    if (!isDiskCacheSupported) return;
    await _ensureInitialized();

    for (final w in words.take(5)) {
      final clean = w.trim();
      if (clean.isEmpty) continue;
      final targetPath = await _fileStore
          .getTargetFilePathIfMissing(_cacheFileName(clean, accent));
      if (targetPath != null) {
        await _synthesizeToCache(clean, targetPath, accent);
      }
    }
  }

  Future<int> getCachedFileCount() async {
    if (!isDiskCacheSupported) return 0;
    await _ensureInitialized();
    return _fileStore.getCachedFileCount();
  }

  Future<void> clearCache() async {
    if (!isDiskCacheSupported) return;
    await _ensureInitialized();
    await _fileStore.clearCache();
  }
}

void unawaited(Future<void> future) {}
