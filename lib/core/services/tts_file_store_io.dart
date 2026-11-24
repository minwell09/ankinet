import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TtsFileStore {
  Directory? _cacheDir;
  bool _initialized = false;

  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(dir.path, 'tts_cache'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (_) {}
  }

  Future<String?> getExistingFilePath(String fileName) async {
    await init();
    if (_cacheDir == null) return null;
    try {
      final file = File(p.join(_cacheDir!.path, fileName));
      if (await file.exists() && await file.length() > 128) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getTargetFilePathIfMissing(String fileName) async {
    await init();
    if (_cacheDir == null || !isSupported) return null;
    try {
      final file = File(p.join(_cacheDir!.path, fileName));
      if (!await file.exists()) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  Future<int> getCachedFileCount() async {
    await init();
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    try {
      final list = await _cacheDir!.list().toList();
      return list.whereType<File>().length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearCache() async {
    await init();
    if (_cacheDir != null && await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create(recursive: true);
    }
  }
}
