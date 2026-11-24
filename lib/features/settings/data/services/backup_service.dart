import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/local_database.dart';
import '../../../../core/utils/cloze_masker.dart';

/// Handles:
/// 1. Full JSON Backup & Restore (decks, cards with FSRS state, radicals, edges, revlog, settings)
/// 2. Anki CSV / TSV Export & Import (compatible with Anki Desktop & AnkiDroid)
/// 3. Anki `.apkg` (ZIP containing `collection.anki2` SQLite database + `media`) Export & Import
class BackupService {
  final LocalDatabase localDatabase;

  const BackupService(this.localDatabase);

  // ===========================================================================
  // 1. FULL JSON BACKUP & RESTORE
  // ===========================================================================

  Future<Uint8List> exportFullBackupJsonBytes() async {
    final db = await localDatabase.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'app_settings',
      {'key': 'last_backup_epoch_ms', 'value': nowMs.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final payload = {
      'format': 'vocab_anki_backup_v6',
      'exported_at': DateTime.fromMillisecondsSinceEpoch(nowMs).toIso8601String(),
      'decks': await db.query('decks'),
      'cards': await db.query('cards'),
      'radicals': await db.query('radicals'),
      'card_radical_edges': await db.query('card_radical_edges'),
      'revlog': await db.query('revlog'),
      'app_settings': await db.query('app_settings'),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  Future<int> importFullBackupJsonBytes(Uint8List bytes) async {
    final raw = utf8.decode(bytes);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final db = await localDatabase.database;

    int importedCards = 0;
    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final d in (data['decks'] as List<dynamic>? ?? const [])) {
        batch.insert(
          'decks',
          Map<String, Object?>.from(d as Map),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final c in (data['cards'] as List<dynamic>? ?? const [])) {
        batch.insert(
          'cards',
          Map<String, Object?>.from(c as Map),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        importedCards++;
      }

      for (final r in (data['radicals'] as List<dynamic>? ?? const [])) {
        batch.insert(
          'radicals',
          Map<String, Object?>.from(r as Map),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final e
          in (data['card_radical_edges'] as List<dynamic>? ?? const [])) {
        batch.insert(
          'card_radical_edges',
          Map<String, Object?>.from(e as Map),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      for (final s in (data['app_settings'] as List<dynamic>? ?? const [])) {
        batch.insert(
          'app_settings',
          Map<String, Object?>.from(s as Map),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });

    return importedCards;
  }

  // ===========================================================================
  // 2. ANKI CSV / TSV EXPORT & IMPORT
  // ===========================================================================

  Future<Uint8List> exportAnkiCsvBytes({String? deckId}) async {
    final db = await localDatabase.database;
    final cards = await db.query(
      'cards',
      where: deckId != null ? 'deck_id = ?' : null,
      whereArgs: deckId != null ? [deckId] : null,
      orderBy: 'created_at ASC',
    );

    final edgeRows = await db.rawQuery('''
      SELECT e.card_id, GROUP_CONCAT(r.symbol || ' (' || r.meaning || ')', '; ') AS rads
      FROM card_radical_edges e
      INNER JOIN radicals r ON r.id = e.radical_id
      GROUP BY e.card_id
    ''');
    final radsByCard = <String, String>{
      for (final r in edgeRows)
        (r['card_id'] as String): (r['rads'] as String?) ?? '',
    };

    final buf = StringBuffer()
      ..writeln('#separator:tab')
      ..writeln('#html:false')
      ..writeln(
        '#columns:Word\tPhonetic\tTranslation\tContextSentence\tClozeSentence\tRadicals',
      );

    String cleanField(Object? val) =>
        (val?.toString() ?? '').replaceAll('\t', ' ').replaceAll('\n', ' ');

    for (final c in cards) {
      final id = c['id'] as String;
      final word = cleanField(c['word']);
      final phoneticUs = cleanField(c['phonetic_us']);
      final phoneticUk = cleanField(c['phonetic_uk']);
      final rawPhonetic = cleanField(c['phonetic']);
      final phonetic = (phoneticUs.isNotEmpty && phoneticUk.isNotEmpty)
          ? 'US $phoneticUs | UK $phoneticUk'
          : (phoneticUs.isNotEmpty ? phoneticUs : rawPhonetic);
      final translation = cleanField(c['translation']);
      final context = cleanField(c['context_sentence']);
      final cloze = cleanField(c['cloze_sentence']);
      final rads = cleanField(radsByCard[id] ?? '');
      buf.writeln('$word\t$phonetic\t$translation\t$context\t$cloze\t$rads');
    }

    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  Future<int> importAnkiCsvBytes(
    Uint8List bytes, {
    String deckId = 'default_deck',
  }) async {
    final content = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(content);
    final db = await localDatabase.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    int imported = 0;
    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;

        final parts = line.contains('\t')
            ? line.split('\t')
            : _splitCsvRow(line);
        if (parts.length < 2) continue;

        final word = _stripHtml(parts[0]).trim().toLowerCase();
        if (word.isEmpty || word == 'word') continue;

        final String phonetic;
        final String translation;
        final String context;
        final String cloze;

        if (parts.length >= 3) {
          phonetic = _stripHtml(parts[1]).trim();
          translation = _stripHtml(parts[2]).trim();
          context = parts.length >= 4 ? _stripHtml(parts[3]).trim() : '';
          final rawCloze = parts.length >= 5 ? _stripHtml(parts[4]).trim() : '';
          cloze = (rawCloze.isNotEmpty &&
                  !ClozeMasker.containsUnmaskedSurfaceForm(
                    clozeSentence: rawCloze,
                    word: word,
                  ))
              ? rawCloze
              : ClozeMasker.maskSentence(sentence: context, word: word);
        } else {
          phonetic = '/$word/';
          translation = _stripHtml(parts[1]).trim();
          context = '';
          cloze = '';
        }

        final cardId = 'card_$word';
        batch.insert(
          'cards',
          {
            'id': cardId,
            'deck_id': deckId,
            'word': word,
            'lemma': word,
            'phonetic': phonetic.isEmpty ? '/$word/' : phonetic,
            'translation': translation,
            'part_of_speech': 'vocab',
            'context_sentence': context,
            'cloze_sentence': cloze,
            'audio_url': '',
            'state': 0,
            'step_index': 0,
            'stability': 0.0,
            'difficulty': 5.0,
            'interval_days': 0,
            'repetitions': 0,
            'lapses': 0,
            'ease_factor': 2.5,
            'is_leech': 0,
            'is_suspended': 0,
            'next_review_at': now,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        imported++;
      }

      await batch.commit(noResult: true);
    });

    return imported;
  }

  // ===========================================================================
  // 3. ANKI .APKG EXPORT & IMPORT (ZIP with collection.anki2 SQLite DB + media)
  // ===========================================================================

  Future<Uint8List> exportAnkiApkgBytes({
    String deckId = 'default_deck',
  }) async {
    final db = await localDatabase.database;
    final cards = await db.query(
      'cards',
      where: 'deck_id = ?',
      whereArgs: [deckId],
      orderBy: 'created_at ASC',
    );

    final tempName =
        'anki_export_${DateTime.now().millisecondsSinceEpoch}.anki2';
    final tempPath = kIsWeb
        ? tempName
        : p.join(await getDatabasesPath(), tempName);

    final ankiDb = await databaseFactory.openDatabase(
      tempPath,
      options: OpenDatabaseOptions(version: 1),
    );

    await ankiDb.execute('''
      CREATE TABLE col (
        id integer primary key,
        crt integer not null,
        mod integer not null,
        scm integer not null,
        ver integer not null,
        dty integer not null,
        usn integer not null,
        ls integer not null,
        conf text not null,
        models text not null,
        decks text not null,
        dconf text not null,
        tags text not null
      )
    ''');
    await ankiDb.execute('''
      CREATE TABLE notes (
        id integer primary key,
        guid text not null,
        mid integer not null,
        mod integer not null,
        usn integer not null,
        tags text not null,
        flds text not null,
        sfld text not null,
        csum integer not null,
        flags integer not null,
        data text not null
      )
    ''');
    await ankiDb.execute('''
      CREATE TABLE cards (
        id integer primary key,
        nid integer not null,
        did integer not null,
        ord integer not null,
        mod integer not null,
        usn integer not null,
        type integer not null,
        queue integer not null,
        due integer not null,
        ivl integer not null,
        factor integer not null,
        reps integer not null,
        lapses integer not null,
        left integer not null,
        odue integer not null,
        odid integer not null,
        flags integer not null,
        data text not null
      )
    ''');
    await ankiDb.execute('''
      CREATE TABLE revlog (
        id integer primary key,
        cid integer not null,
        usn integer not null,
        ease integer not null,
        ivl integer not null,
        lastIvl integer not null,
        factor integer not null,
        time integer not null,
        type integer not null
      )
    ''');
    await ankiDb.execute('''
      CREATE TABLE graves (
        usn integer not null,
        oid integer not null,
        type integer not null
      )
    ''');

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const modelId = 1700000001;
    const ankiDeckId = 1700000002;

    final modelsJson = jsonEncode({
      '$modelId': {
        'id': modelId,
        'name': 'VocabAnki EN-VI FSRS',
        'type': 0,
        'mod': nowSec,
        'usn': -1,
        'sortf': 0,
        'did': ankiDeckId,
        'tmpls': [
          {
            'name': 'Card 1',
            'ord': 0,
            'qfmt': '<div class="word">{{Word}}</div><div class="cloze">{{Context}}</div>',
            'afmt': '{{FrontSide}}<hr id="answer"><div class="ipa">{{Phonetic}}</div><div class="vi">{{Meaning}}</div>',
            'did': null,
            'bqfmt': '',
            'bafmt': '',
          }
        ],
        'flds': [
          {'name': 'Word', 'ord': 0, 'sticky': false, 'rtl': false, 'font': 'Arial', 'size': 20},
          {'name': 'Phonetic', 'ord': 1, 'sticky': false, 'rtl': false, 'font': 'Arial', 'size': 16},
          {'name': 'Meaning', 'ord': 2, 'sticky': false, 'rtl': false, 'font': 'Arial', 'size': 18},
          {'name': 'Context', 'ord': 3, 'sticky': false, 'rtl': false, 'font': 'Arial', 'size': 15},
        ],
        'css': '.card { font-family: sans-serif; text-align: center; }',
        'latexPre': '',
        'latexPost': '',
        'reqs': [
          [0, 'all', [0]]
        ],
        'tags': [],
        'vers': [],
      }
    });

    final decksJson = jsonEncode({
      '1': {
        'id': 1,
        'name': 'Default',
        'mod': nowSec,
        'usn': -1,
        'desc': '',
        'dyn': 0,
        'collapsed': false,
        'conf': 1,
      },
      '$ankiDeckId': {
        'id': ankiDeckId,
        'name': 'VocabAnki EN-VI',
        'mod': nowSec,
        'usn': -1,
        'desc': 'Exported from VocabAnki v6.0 (FSRS)',
        'dyn': 0,
        'collapsed': false,
        'conf': 1,
      }
    });

    await ankiDb.insert('col', {
      'id': 1,
      'crt': nowSec,
      'mod': nowSec * 1000,
      'scm': nowSec * 1000,
      'ver': 11,
      'dty': 0,
      'usn': 0,
      'ls': 0,
      'conf': jsonEncode({'curDeck': ankiDeckId, 'curModel': '$modelId'}),
      'models': modelsJson,
      'decks': decksJson,
      'dconf': jsonEncode({'1': {'id': 1, 'name': 'Default'}}),
      'tags': '{}',
    });

    final batch = ankiDb.batch();
    var noteIdBase = DateTime.now().millisecondsSinceEpoch;

    for (final c in cards) {
      noteIdBase++;
      final word = (c['word'] as String?) ?? '';
      final pUs = (c['phonetic_us'] as String?) ?? '';
      final pUk = (c['phonetic_uk'] as String?) ?? '';
      final rawP = (c['phonetic'] as String?) ?? '';
      final phonetic = (pUs.isNotEmpty && pUk.isNotEmpty)
          ? 'US $pUs • UK $pUk'
          : (pUs.isNotEmpty ? pUs : rawP);
      final translation = (c['translation'] as String?) ?? '';
      final context = (c['context_sentence'] as String?) ?? '';
      final flds = '$word\x1f$phonetic\x1f$translation\x1f$context';
      final digest = sha1.convert(utf8.encode(word)).toString();
      final csum = int.parse(digest.substring(0, 8), radix: 16);

      batch.insert('notes', {
        'id': noteIdBase,
        'guid': digest.substring(0, 10),
        'mid': modelId,
        'mod': nowSec,
        'usn': -1,
        'tags': ' vocab_anki ',
        'flds': flds,
        'sfld': word,
        'csum': csum,
        'flags': 0,
        'data': '',
      });

      final ivl = (c['interval_days'] as int?) ?? 0;
      final reps = (c['repetitions'] as int?) ?? 0;
      final lapses = (c['lapses'] as int?) ?? 0;
      final state = (c['state'] as int?) ?? 0;

      batch.insert('cards', {
        'id': noteIdBase + 100000,
        'nid': noteIdBase,
        'did': ankiDeckId,
        'ord': 0,
        'mod': nowSec,
        'usn': -1,
        'type': state,
        'queue': state,
        'due': ivl,
        'ivl': ivl,
        'factor': 2500,
        'reps': reps,
        'lapses': lapses,
        'left': 0,
        'odue': 0,
        'odid': 0,
        'flags': 0,
        'data': jsonEncode({
          's': c['stability'] ?? 0.0,
          'd': c['difficulty'] ?? 5.0,
        }),
      });
    }

    await batch.commit(noResult: true);
    await ankiDb.close();

    final sqliteBytes = await databaseFactory.readDatabaseBytes(tempPath);
    try {
      await databaseFactory.deleteDatabase(tempPath);
    } catch (_) {}

    final archive = Archive()
      ..addFile(
        ArchiveFile('collection.anki2', sqliteBytes.length, sqliteBytes),
      )
      ..addFile(
        ArchiveFile('media', 2, utf8.encode('{}')),
      );

    final zipped = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipped ?? const []);
  }

  Future<int> importAnkiApkgBytes(
    Uint8List apkgBytes, {
    String deckId = 'default_deck',
  }) async {
    final archive = ZipDecoder().decodeBytes(apkgBytes);
    ArchiveFile? ankiFile;
    for (final f in archive.files) {
      if (f.name == 'collection.anki21' || f.name == 'collection.anki2') {
        ankiFile = f;
        if (f.name == 'collection.anki21') break;
      }
    }
    if (ankiFile == null) {
      throw const FormatException(
        'File .apkg không hợp lệ (không tìm thấy collection.anki2).',
      );
    }

    final dbBytes = Uint8List.fromList(ankiFile.content as List<int>);
    final tempName =
        'anki_import_${DateTime.now().millisecondsSinceEpoch}.anki2';
    final tempPath = kIsWeb
        ? tempName
        : p.join(await getDatabasesPath(), tempName);

    await databaseFactory.writeDatabaseBytes(tempPath, dbBytes);
    final ankiDb = await databaseFactory.openDatabase(
      tempPath,
      options: OpenDatabaseOptions(readOnly: true),
    );

    final notes = await ankiDb.query('notes', columns: ['id', 'flds']);
    await ankiDb.close();
    try {
      await databaseFactory.deleteDatabase(tempPath);
    } catch (_) {}

    final db = await localDatabase.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    int imported = 0;

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final n in notes) {
        final flds = (n['flds'] as String?) ?? '';
        final parts = flds.split('\x1f').map(_stripHtml).toList();
        if (parts.isEmpty) continue;

        final word = parts[0].trim().toLowerCase();
        if (word.isEmpty || word.contains('please update to the latest anki')) {
          continue;
        }

        String phonetic = '/$word/';
        String translation = '';
        String context = '';

        if (parts.length >= 3) {
          phonetic = parts[1].trim().isNotEmpty ? parts[1].trim() : '/$word/';
          translation = parts[2].trim();
          if (parts.length >= 4) context = parts[3].trim();
        } else if (parts.length == 2) {
          translation = parts[1].trim();
        }

        if (translation.isEmpty) translation = word;

        final cloze = context.isNotEmpty
            ? ClozeMasker.maskSentence(sentence: context, word: word)
            : '';

        batch.insert(
          'cards',
          {
            'id': 'card_$word',
            'deck_id': deckId,
            'word': word,
            'lemma': word,
            'phonetic': phonetic,
            'translation': translation,
            'part_of_speech': 'vocab',
            'context_sentence': context,
            'cloze_sentence': cloze,
            'audio_url': '',
            'state': 0,
            'step_index': 0,
            'stability': 0.0,
            'difficulty': 5.0,
            'interval_days': 0,
            'repetitions': 0,
            'lapses': 0,
            'ease_factor': 2.5,
            'is_leech': 0,
            'is_suspended': 0,
            'next_review_at': now,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        imported++;
      }

      await batch.commit(noResult: true);
    });

    return imported;
  }

  static String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .trim();
  }

  static List<String> _splitCsvRow(String row) {
    final result = <String>[];
    final current = StringBuffer();
    bool inQuotes = false;
    for (var i = 0; i < row.length; i++) {
      final ch = row[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString());
    return result;
  }
}
