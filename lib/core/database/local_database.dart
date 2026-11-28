import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/cloze_masker.dart';
import 'db_factory.dart';

/// Offline-first SQLite database (v3) managing:
/// 1. `decks` - Anki decks
/// 2. `cards` - Vocabulary flashcards with FSRS-4.5 scheduling state, surface-form cloze context, and leech tracking
/// 3. `radicals` - Structural radicals / morphemes / roots
/// 4. `card_radical_edges` - Many-to-many edges linking saved words to structural radicals
/// 5. `revlog` - Review history log for FSRS analytics, 17-weight optimization, retention & heatmap
/// 6. `dict_cache` - Persistent contextual cache keyed by `(word, sentence_hash)` for API/LLM lookups
/// 7. `app_settings` - Key-value store for study, backup reminder, custom FSRS weights & notification settings
class LocalDatabase {
  static const _dbName = 'vocab_anki_graph.db';
  static const _dbVersion = 6;

  final String? overridePath;
  Database? _db;

  LocalDatabase({this.overridePath});

  Future<Database> get database async {
    if (_db != null) return _db!;
    configurePlatformDatabaseFactory();

    final String path;
    if (overridePath != null) {
      path = overridePath!;
    } else if (kIsWeb) {
      path = _dbName;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, _dbName);
    }

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Decks Table
    await db.execute('''
      CREATE TABLE decks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');

    // 2. Vocabulary Flashcards Table (Anki note + FSRS-4.5 card state)
    await db.execute('''
      CREATE TABLE cards (
        id TEXT PRIMARY KEY,
        deck_id TEXT NOT NULL,
        word TEXT NOT NULL UNIQUE,
        lemma TEXT NOT NULL DEFAULT '',
        phonetic TEXT NOT NULL,
        phonetic_us TEXT NOT NULL DEFAULT '',
        phonetic_uk TEXT NOT NULL DEFAULT '',
        translation TEXT NOT NULL,
        part_of_speech TEXT NOT NULL DEFAULT 'vocab',
        context_sentence TEXT NOT NULL DEFAULT '',
        cloze_sentence TEXT NOT NULL DEFAULT '',
        audio_url TEXT NOT NULL DEFAULT '',
        state INTEGER NOT NULL DEFAULT 0,
        step_index INTEGER NOT NULL DEFAULT 0,
        stability REAL NOT NULL DEFAULT 0.0,
        difficulty REAL NOT NULL DEFAULT 5.0,
        interval_days INTEGER NOT NULL DEFAULT 0,
        repetitions INTEGER NOT NULL DEFAULT 0,
        lapses INTEGER NOT NULL DEFAULT 0,
        ease_factor REAL NOT NULL DEFAULT 2.5,
        is_leech INTEGER NOT NULL DEFAULT 0,
        is_suspended INTEGER NOT NULL DEFAULT 0,
        last_review_at INTEGER,
        next_review_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (deck_id) REFERENCES decks (id) ON DELETE CASCADE
      )
    ''');

    // 3. Structural Radicals / Morphemes Table
    await db.execute('''
      CREATE TABLE radicals (
        id TEXT PRIMARY KEY,
        symbol TEXT NOT NULL UNIQUE,
        meaning TEXT NOT NULL,
        stroke_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 4. Graph Edges: Word <-> Structural Radical
    await db.execute('''
      CREATE TABLE card_radical_edges (
        card_id TEXT NOT NULL,
        radical_id TEXT NOT NULL,
        decomposition_role TEXT NOT NULL DEFAULT 'component',
        PRIMARY KEY (card_id, radical_id),
        FOREIGN KEY (card_id) REFERENCES cards (id) ON DELETE CASCADE,
        FOREIGN KEY (radical_id) REFERENCES radicals (id) ON DELETE CASCADE
      )
    ''');

    // 5. Review History Log (for heatmap, retention, daily limit tracking, and FSRS 17-weight training)
    await db.execute('''
      CREATE TABLE revlog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id TEXT NOT NULL,
        deck_id TEXT NOT NULL,
        grade INTEGER NOT NULL,
        state_before INTEGER NOT NULL,
        state_after INTEGER NOT NULL,
        stability_after REAL NOT NULL,
        difficulty_after REAL NOT NULL,
        interval_days INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        reviewed_at INTEGER NOT NULL
      )
    ''');

    // 6. Contextual Dictionary & LLM Translation SQLite Cache keyed by (word, sentence_hash)
    await db.execute('''
      CREATE TABLE dict_cache (
        word TEXT NOT NULL,
        sentence_hash TEXT NOT NULL DEFAULT '',
        context_sentence TEXT NOT NULL DEFAULT '',
        lemma TEXT NOT NULL DEFAULT '',
        phonetic TEXT NOT NULL DEFAULT '',
        phonetic_us TEXT NOT NULL DEFAULT '',
        phonetic_uk TEXT NOT NULL DEFAULT '',
        translation TEXT NOT NULL DEFAULT '',
        part_of_speech TEXT NOT NULL DEFAULT 'vocab',
        audio_url TEXT NOT NULL DEFAULT '',
        radicals_json TEXT NOT NULL DEFAULT '[]',
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (word, sentence_hash)
      )
    ''');

    // 7. Application & Study Settings
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 8. Pronunciation Assessment History (for average score & weak phonemes HUD)
    await db.execute('''
      CREATE TABLE pronunciation_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id TEXT NOT NULL,
        word TEXT NOT NULL,
        accent TEXT NOT NULL DEFAULT 'en-US',
        mode TEXT NOT NULL DEFAULT 'word',
        overall_score REAL NOT NULL,
        rank TEXT NOT NULL,
        phonemes_json TEXT NOT NULL DEFAULT '[]',
        diagnostic_tip TEXT NOT NULL DEFAULT '',
        assessed_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pronunciation_logs_time ON pronunciation_logs(assessed_at)',
    );

    await _createIndexes(db);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('decks', {
      'id': 'default_deck',
      'name': 'Core Vocabulary (EN ➔ VI)',
      'description': 'Từ vựng Tiếng Anh trích xuất từ NLP & Gốc từ Hy Lạp/Latinh',
      'created_at': now,
    });

    await _seedStarterCards(db, now);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cards_deck_due ON cards(deck_id, is_suspended, state, next_review_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cards_word ON cards(word)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cards_lemma ON cards(lemma)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_edges_radical ON card_radical_edges(radical_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_edges_card ON card_radical_edges(card_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_revlog_reviewed_at ON revlog(reviewed_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_revlog_deck_time ON revlog(deck_id, reviewed_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dict_cache_word ON dict_cache(word)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Also ensure decks.description exists for v1 databases
      final deckCols = await db.rawQuery('PRAGMA table_info(decks)');
      final existingDeckCols = deckCols.map((c) => c['name'] as String).toSet();
      if (!existingDeckCols.contains('description')) {
        await db.execute(
          "ALTER TABLE decks ADD COLUMN description TEXT NOT NULL DEFAULT ''",
        );
      }

      final columns = await db.rawQuery('PRAGMA table_info(cards)');
      final existingCols = columns.map((c) => c['name'] as String).toSet();

      Future<void> addColIfMissing(String name, String ddl) async {
        if (!existingCols.contains(name)) {
          await db.execute('ALTER TABLE cards ADD COLUMN $name $ddl');
        }
      }

      await addColIfMissing('lemma', "TEXT NOT NULL DEFAULT ''");
      await addColIfMissing('part_of_speech', "TEXT NOT NULL DEFAULT 'vocab'");
      await addColIfMissing('cloze_sentence', "TEXT NOT NULL DEFAULT ''");
      await addColIfMissing('audio_url', "TEXT NOT NULL DEFAULT ''");
      await addColIfMissing('state', 'INTEGER NOT NULL DEFAULT 0');
      await addColIfMissing('step_index', 'INTEGER NOT NULL DEFAULT 0');
      await addColIfMissing('stability', 'REAL NOT NULL DEFAULT 0.0');
      await addColIfMissing('difficulty', 'REAL NOT NULL DEFAULT 5.0');
      await addColIfMissing('lapses', 'INTEGER NOT NULL DEFAULT 0');
      await addColIfMissing('is_leech', 'INTEGER NOT NULL DEFAULT 0');
      await addColIfMissing('is_suspended', 'INTEGER NOT NULL DEFAULT 0');
      await addColIfMissing('last_review_at', 'INTEGER');

      // Backfill FSRS stability, difficulty, state & lemma from existing v1 SM-2 cards
      await db.execute('''
        UPDATE cards
        SET lemma = CASE WHEN lemma = '' THEN word ELSE lemma END,
            state = CASE WHEN repetitions > 0 THEN 2 ELSE 0 END,
            stability = CASE WHEN interval_days > 0 THEN CAST(interval_days AS REAL) ELSE 0.0 END,
            difficulty = CASE
              WHEN ease_factor > 0 THEN MIN(10.0, MAX(1.0, 11.0 - (ease_factor * 2.4)))
              ELSE 5.0
            END
        WHERE stability = 0.0
      ''');

      // Backfill surface-form cloze_sentence for v1 cards that only had context_sentence
      final legacyCards = await db.query(
        'cards',
        columns: const ['id', 'word', 'lemma', 'context_sentence', 'cloze_sentence'],
      );
      final batch = db.batch();
      for (final row in legacyCards) {
        final existingCloze = (row['cloze_sentence'] as String?) ?? '';
        final ctx = (row['context_sentence'] as String?) ?? '';
        final word = (row['word'] as String?) ?? '';
        final lemma = (row['lemma'] as String?) ?? '';
        if (ctx.isNotEmpty &&
            (existingCloze.isEmpty ||
                ClozeMasker.containsUnmaskedSurfaceForm(
                  clozeSentence: existingCloze,
                  word: word,
                  lemma: lemma,
                ))) {
          final masked = ClozeMasker.maskSentence(
            sentence: ctx,
            word: word,
            lemma: lemma,
          );
          batch.update(
            'cards',
            {'cloze_sentence': masked},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      await batch.commit(noResult: true);

      await db.execute('''
        CREATE TABLE IF NOT EXISTS revlog (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          card_id TEXT NOT NULL,
          deck_id TEXT NOT NULL,
          grade INTEGER NOT NULL,
          state_before INTEGER NOT NULL,
          state_after INTEGER NOT NULL,
          stability_after REAL NOT NULL,
          difficulty_after REAL NOT NULL,
          interval_days INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          reviewed_at INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 3) {
      // Ensure revlog and app_settings exist even if upgrading from a partial v2
      await db.execute('''
        CREATE TABLE IF NOT EXISTS revlog (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          card_id TEXT NOT NULL,
          deck_id TEXT NOT NULL,
          grade INTEGER NOT NULL,
          state_before INTEGER NOT NULL,
          state_after INTEGER NOT NULL,
          stability_after REAL NOT NULL,
          difficulty_after REAL NOT NULL,
          interval_days INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          reviewed_at INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      // Check if dict_cache exists and whether it already has `sentence_hash`
      final dictCols = await db.rawQuery('PRAGMA table_info(dict_cache)');
      if (dictCols.isEmpty) {
        await db.execute('''
          CREATE TABLE dict_cache (
            word TEXT NOT NULL,
            sentence_hash TEXT NOT NULL DEFAULT '',
            context_sentence TEXT NOT NULL DEFAULT '',
            lemma TEXT NOT NULL DEFAULT '',
            phonetic TEXT NOT NULL DEFAULT '',
            translation TEXT NOT NULL DEFAULT '',
            part_of_speech TEXT NOT NULL DEFAULT 'vocab',
            audio_url TEXT NOT NULL DEFAULT '',
            radicals_json TEXT NOT NULL DEFAULT '[]',
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (word, sentence_hash)
          )
        ''');
      } else {
        final colNames = dictCols.map((c) => c['name'] as String).toSet();
        if (!colNames.contains('sentence_hash')) {
          await db.execute('ALTER TABLE dict_cache RENAME TO dict_cache_v2_old');
          await db.execute('''
            CREATE TABLE dict_cache (
              word TEXT NOT NULL,
              sentence_hash TEXT NOT NULL DEFAULT '',
              context_sentence TEXT NOT NULL DEFAULT '',
              lemma TEXT NOT NULL DEFAULT '',
              phonetic TEXT NOT NULL DEFAULT '',
              translation TEXT NOT NULL DEFAULT '',
              part_of_speech TEXT NOT NULL DEFAULT 'vocab',
              audio_url TEXT NOT NULL DEFAULT '',
              radicals_json TEXT NOT NULL DEFAULT '[]',
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (word, sentence_hash)
            )
          ''');
          await db.execute('''
            INSERT OR IGNORE INTO dict_cache (
              word, sentence_hash, context_sentence, lemma, phonetic,
              translation, part_of_speech, audio_url, radicals_json, updated_at
            )
            SELECT
              word, '', '', lemma, phonetic,
              translation, part_of_speech, audio_url, radicals_json, updated_at
            FROM dict_cache_v2_old
          ''');
          await db.execute('DROP TABLE dict_cache_v2_old');
        }
      }

      await _createIndexes(db);
    }

    if (oldVersion < 4) {
      final cardCols = await db.rawQuery('PRAGMA table_info(cards)');
      final existingCardCols = cardCols.map((c) => c['name'] as String).toSet();
      if (!existingCardCols.contains('phonetic_us')) {
        await db.execute(
          "ALTER TABLE cards ADD COLUMN phonetic_us TEXT NOT NULL DEFAULT ''",
        );
      }
      if (!existingCardCols.contains('phonetic_uk')) {
        await db.execute(
          "ALTER TABLE cards ADD COLUMN phonetic_uk TEXT NOT NULL DEFAULT ''",
        );
      }
      await db.execute('''
        UPDATE cards
        SET phonetic_us = phonetic
        WHERE phonetic_us = '' AND phonetic != ''
      ''');

      final dictCols = await db.rawQuery('PRAGMA table_info(dict_cache)');
      final existingDictCols = dictCols.map((c) => c['name'] as String).toSet();
      if (existingDictCols.isNotEmpty) {
        if (!existingDictCols.contains('phonetic_us')) {
          await db.execute(
            "ALTER TABLE dict_cache ADD COLUMN phonetic_us TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!existingDictCols.contains('phonetic_uk')) {
          await db.execute(
            "ALTER TABLE dict_cache ADD COLUMN phonetic_uk TEXT NOT NULL DEFAULT ''",
          );
        }
        await db.execute('''
          UPDATE dict_cache
          SET phonetic_us = phonetic
          WHERE phonetic_us = '' AND phonetic != ''
        ''');
      }
    }

    if (oldVersion < 5) {
      // Backfill authentic OpenDictData US & UK IPA for starter cards on existing installs
      const starterIpa = <String, List<String>>{
        'inspect': ['/ˌɪnˈspɛkt/', '/ɪnspˈɛkt/'],
        'perspective': ['/pɝˈspɛktɪv/', '/pəspˈɛktɪv/'],
        'transport': ['/ˈtɹænspɔɹt/', '/ˈtrænspɔːt/'],
        'portable': ['/ˈpɔɹtəbəɫ/', '/pˈɔːtəbəl/'],
        'structure': ['/ˈstɹəktʃɝ/', '/stɹˈʌktʃɐ/'],
        'predict': ['/pɹiˈdɪkt/', '/pɹɪdˈɪkt/'],
      };
      final batch = db.batch();
      starterIpa.forEach((word, ipas) {
        batch.update(
          'cards',
          {
            'phonetic': ipas[0],
            'phonetic_us': ipas[0],
            'phonetic_uk': ipas[1],
          },
          where: "word = ? AND phonetic_uk = ''",
          whereArgs: [word],
        );
      });
      await batch.commit(noResult: true);
    }

    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pronunciation_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          card_id TEXT NOT NULL,
          word TEXT NOT NULL,
          accent TEXT NOT NULL DEFAULT 'en-US',
          mode TEXT NOT NULL DEFAULT 'word',
          overall_score REAL NOT NULL,
          rank TEXT NOT NULL,
          phonemes_json TEXT NOT NULL DEFAULT '[]',
          diagnostic_tip TEXT NOT NULL DEFAULT '',
          assessed_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pronunciation_logs_time ON pronunciation_logs(assessed_at)',
      );
    }
  }

  Future<void> _seedStarterCards(Database db, int now) async {
    final starter = [
      {
        'word': 'inspect',
        'lemma': 'inspect',
        'phonetic': '/ˌɪnˈspɛkt/',
        'phonetic_us': '/ˌɪnˈspɛkt/',
        'phonetic_uk': '/ɪnspˈɛkt/',
        'translation': '(v. - động từ) kiểm tra, thanh tra, xem xét kỹ',
        'pos': 'verb',
        'context':
            'Engineers inspect the structure before approving global transport.',
        'cloze':
            'Engineers [...] the structure before approving global transport.',
        'radicals': [
          ['in-', 'tiền tố: vào trong (in/into)'],
          ['-spect-', 'gốc: nhìn, quan sát (look/see)'],
        ],
      },
      {
        'word': 'perspective',
        'lemma': 'perspective',
        'phonetic': '/pɝˈspɛktɪv/',
        'phonetic_us': '/pɝˈspɛktɪv/',
        'phonetic_uk': '/pəspˈɛktɪv/',
        'translation': '(n. - danh từ) góc nhìn, quan điểm, viễn cảnh',
        'pos': 'noun',
        'context':
            'Learning word roots gives you a new perspective on vocabulary.',
        'cloze':
            'Learning word roots gives you a new [...] on vocabulary.',
        'radicals': [
          ['-spect-', 'gốc: nhìn, quan sát (look/see)'],
          ['-ive', 'hậu tố (adj./n.): có tính chất'],
        ],
      },
      {
        'word': 'transport',
        'lemma': 'transport',
        'phonetic': '/ˈtɹænspɔɹt/',
        'phonetic_us': '/ˈtɹænspɔɹt/',
        'phonetic_uk': '/ˈtrænspɔːt/',
        'translation': '(v./n.) vận chuyển, chuyên chở, giao thông',
        'pos': 'verb',
        'context':
            'Portable containers make it easier to transport goods across oceans.',
        'cloze':
            'Portable containers make it easier to [...] goods across oceans.',
        'radicals': [
          ['trans-', 'tiền tố: vượt qua, chuyển đổi (across)'],
          ['-port-', 'gốc: mang, vận chuyển (carry)'],
        ],
      },
      {
        'word': 'portable',
        'lemma': 'portable',
        'phonetic': '/ˈpɔɹtəbəɫ/',
        'phonetic_us': '/ˈpɔɹtəbəɫ/',
        'phonetic_uk': '/pˈɔːtəbəl/',
        'translation': '(adj. - tính từ) có thể mang theo, di động, nhỏ gọn',
        'pos': 'adj',
        'context':
            'Portable devices transformed how students review flashcards daily.',
        'cloze':
            '[...] devices transformed how students review flashcards daily.',
        'radicals': [
          ['-port-', 'gốc: mang, vận chuyển (carry)'],
          ['-able', 'hậu tố (adj.): có thể'],
        ],
      },
      {
        'word': 'structure',
        'lemma': 'structure',
        'phonetic': '/ˈstɹəktʃɝ/',
        'phonetic_us': '/ˈstɹəktʃɝ/',
        'phonetic_uk': '/stɹˈʌktʃɐ/',
        'translation': '(n. - danh từ) cấu trúc, kết cấu, công trình',
        'pos': 'noun',
        'context':
            'Understanding morphological structure accelerates memory retention.',
        'cloze':
            'Understanding morphological [...] accelerates memory retention.',
        'radicals': [
          ['-struct-', 'gốc: xây dựng, kết cấu (build)'],
        ],
      },
      {
        'word': 'predict',
        'lemma': 'predict',
        'phonetic': '/pɹiˈdɪkt/',
        'phonetic_us': '/pɹiˈdɪkt/',
        'phonetic_uk': '/pɹɪdˈɪkt/',
        'translation': '(v. - động từ) dự đoán, tiên đoán',
        'pos': 'verb',
        'context':
            'FSRS models memory decay to predict the optimal review interval.',
        'cloze':
            'FSRS models memory decay to [...] the optimal review interval.',
        'radicals': [
          ['pre-', 'tiền tố: trước (before)'],
          ['-dict-', 'gốc: nói, tuyên bố (say/speak)'],
        ],
      },
    ];

    final batch = db.batch();
    for (final item in starter) {
      final word = item['word'] as String;
      final cardId = 'card_$word';
      batch.insert(
        'cards',
        {
          'id': cardId,
          'deck_id': 'default_deck',
          'word': word,
          'lemma': item['lemma'] as String,
          'phonetic': item['phonetic'] as String,
          'phonetic_us': item['phonetic_us'] as String,
          'phonetic_uk': item['phonetic_uk'] as String,
          'translation': item['translation'] as String,
          'part_of_speech': item['pos'] as String,
          'context_sentence': item['context'] as String,
          'cloze_sentence': item['cloze'] as String,
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
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final radicals = item['radicals'] as List<List<String>>;
      for (final rad in radicals) {
        final symbol = rad[0];
        final meaning = rad[1];
        final radId = 'rad_$symbol';
        batch.insert(
          'radicals',
          {
            'id': radId,
            'symbol': symbol,
            'meaning': meaning,
            'stroke_count': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        batch.insert(
          'card_radical_edges',
          {
            'card_id': cardId,
            'radical_id': radId,
            'decomposition_role': 'structural_radical',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
