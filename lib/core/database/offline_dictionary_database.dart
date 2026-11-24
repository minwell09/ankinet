import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db_factory.dart';

class OfflineDictEntry {
  final String word;
  final String ipa;
  final String ipaUs;
  final String ipaUk;
  final String pos;
  final String vi;

  const OfflineDictEntry({
    required this.word,
    required this.ipa,
    this.ipaUs = '',
    this.ipaUk = '',
    required this.pos,
    required this.vi,
  });
}

/// Dedicated read-only SQLite Dictionary Asset (`assets/nlp/offline_dict.db`)
/// containing 205,000+ English headwords, 104,700+ EN-VI definitions (CC BY-SA 4.0),
/// American (`ipa_us`) & British (`ipa_uk`) IPA pronunciations from Open Dict Data
/// (`open-dict-data/ipa-dict`), and 5,500+ WordNet irregular lemmas.
///
/// Avoids parsing 100k+ entries from JSON into memory: instead materializes the bundled
/// SQLite asset once on first launch and executes indexed `WHERE word IN (...)`
/// queries in < 1ms.
class OfflineDictionaryDatabase {
  static const String _assetPath = 'assets/nlp/offline_dict.db';
  static const String _dbFileName = 'offline_dict_v2.db';

  final String? overridePath;
  Database? _db;
  bool _loadAttempted = false;
  Future<Database?>? _openingFuture;

  OfflineDictionaryDatabase({this.overridePath});

  Future<Database?> get database {
    if (_db != null) return Future.value(_db);
    if (_openingFuture != null) return _openingFuture!;
    if (_loadAttempted) return Future.value(null);
    _loadAttempted = true;
    _openingFuture = _openInternal().whenComplete(() {
      _openingFuture = null;
    });
    return _openingFuture!;
  }

  Future<Database?> _openInternal() async {
    configurePlatformDatabaseFactory();

    try {
      final String targetPath;
      if (overridePath != null) {
        targetPath = overridePath!;
      } else if (kIsWeb) {
        targetPath = _dbFileName;
      } else {
        final dbDir = await getDatabasesPath();
        targetPath = p.join(dbDir, _dbFileName);
      }

      const openTimeout = kIsWeb
          ? Duration(seconds: 12)
          : Duration(seconds: 8);

      final exists = await databaseFactory
          .databaseExists(targetPath)
          .timeout(const Duration(seconds: 4));
      if (!exists) {
        final byteData =
            await rootBundle.load(_assetPath).timeout(openTimeout);
        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        await databaseFactory
            .writeDatabaseBytes(targetPath, bytes)
            .timeout(openTimeout);
      }

      _db = await openDatabase(targetPath, readOnly: true)
          .timeout(const Duration(seconds: 5));
      return _db;
    } catch (_) {
      return null;
    }
  }

  /// Queries a batch of [words] (surface words and lemmas) from `offline_dict.db`
  /// using the primary key index in a single round-trip.
  Future<Map<String, OfflineDictEntry>> lookupBatch(
    Iterable<String> words,
  ) async {
    final cleaned = words
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) return const {};

    final db = await database;
    if (db == null) return const {};

    try {
      final result = <String, OfflineDictEntry>{};
      // Chunk into batches of 200 to stay well below SQLite variable limit
      for (var i = 0; i < cleaned.length; i += 200) {
        final chunk = cleaned.sublist(
          i,
          (i + 200) > cleaned.length ? cleaned.length : (i + 200),
        );
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await db
            .query(
              'dictionary',
              columns: const ['word', 'ipa', 'ipa_us', 'ipa_uk', 'pos', 'vi'],
              where: 'word IN ($placeholders)',
              whereArgs: chunk,
            )
            .timeout(const Duration(seconds: 4));
        for (final row in rows) {
          final w = (row['word'] as String?) ?? '';
          if (w.isEmpty) continue;
          final ipa = (row['ipa'] as String?) ?? '';
          final ipaUs = (row['ipa_us'] as String?) ?? '';
          final ipaUk = (row['ipa_uk'] as String?) ?? '';
          result[w] = OfflineDictEntry(
            word: w,
            ipa: ipa.isNotEmpty ? ipa : (ipaUs.isNotEmpty ? ipaUs : ipaUk),
            ipaUs: ipaUs,
            ipaUk: ipaUk,
            pos: (row['pos'] as String?) ?? 'vocab',
            vi: (row['vi'] as String?) ?? '',
          );
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Looks up irregular surface forms in `irregular_lemmas` table.
  Future<Map<String, String>> lookupIrregularLemmas(
    Iterable<String> surfaceWords,
  ) async {
    final cleaned = surfaceWords
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) return const {};

    final db = await database;
    if (db == null) return const {};

    try {
      final placeholders = List.filled(cleaned.length, '?').join(',');
      final rows = await db.query(
        'irregular_lemmas',
        columns: const ['surface', 'lemma'],
        where: 'surface IN ($placeholders)',
        whereArgs: cleaned,
      );
      return {
        for (final r in rows)
          (r['surface'] as String): (r['lemma'] as String),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Returns dictionary metadata (entry counts, CC BY-SA 4.0 license info).
  Future<Map<String, String>> getMetadata() async {
    final db = await database;
    if (db == null) return const {};
    try {
      final rows = await db.query('meta_info');
      return {
        for (final r in rows)
          (r['key'] as String): (r['value'] as String),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _loadAttempted = false;
  }
}
