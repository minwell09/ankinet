import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:web/web.dart' as web;

bool _webFactoryInitialized = false;

void configurePlatformDatabaseFactory() {
  if (_webFactoryInitialized) return;
  databaseFactory = databaseFactoryFfiWeb;
  _webFactoryInitialized = true;

  // Request persistent IndexedDB storage from the browser to reduce automatic eviction risk.
  try {
    web.window.navigator.storage.persist();
  } catch (_) {}
}
