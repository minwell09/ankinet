import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vocab_anki/core/database/local_database.dart';
import 'package:vocab_anki/core/database/offline_dictionary_database.dart';
import 'package:vocab_anki/core/settings/settings_repository.dart';
import 'package:vocab_anki/core/settings/study_settings.dart';
import 'package:vocab_anki/core/srs/fsrs_scheduler.dart';
import 'package:vocab_anki/core/srs/fsrs_weight_optimizer.dart';
import 'package:vocab_anki/core/srs/sm2_scheduler.dart';
import 'package:vocab_anki/core/utils/cloze_masker.dart';
import 'package:vocab_anki/core/utils/ipa_normalizer.dart';
import 'package:vocab_anki/features/decks/data/repositories/deck_repository_impl.dart';
import 'package:vocab_anki/features/decks/domain/entities/vocab_card.dart';
import 'package:vocab_anki/features/nlp_extractor/data/datasources/nlp_analyzer_datasource.dart';
import 'package:vocab_anki/features/nlp_extractor/data/repositories/nlp_extractor_repository_impl.dart';
import 'package:vocab_anki/features/settings/data/services/backup_service.dart';
import 'package:vocab_anki/features/stats/data/repositories/stats_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('FsrsScheduler (FSRS-4.5) & FsrsWeightOptimizer', () {
    const scheduler = FsrsScheduler();

    test('New card Good follows learning steps then graduates to review', () {
      final step1 = scheduler.schedule(
        grade: ReviewGrade.good,
        currentState: CardState.newCard,
        currentStepIndex: 0,
        currentStability: 0,
        currentDifficulty: 5.0,
        currentIntervalDays: 0,
        currentReps: 0,
        currentLapses: 0,
        learningStepsMinutes: const [1, 10],
      );

      expect(step1.state, CardState.learning);
      expect(step1.stepIndex, 1);
      expect(step1.intervalLabel, '10m');

      final graduated = scheduler.schedule(
        grade: ReviewGrade.good,
        currentState: step1.state,
        currentStepIndex: step1.stepIndex,
        currentStability: step1.stability,
        currentDifficulty: step1.difficulty,
        currentIntervalDays: step1.intervalDays,
        currentReps: step1.reps,
        currentLapses: step1.lapses,
        learningStepsMinutes: const [1, 10],
      );

      expect(graduated.state, CardState.review);
      expect(graduated.intervalDays, greaterThanOrEqualTo(3));
      expect(graduated.stability, greaterThan(3.0));
    });

    test('Review card enforces strict interval ordering Hard < Good < Easy', () {
      final previews = scheduler.previewAllGrades(
        currentState: CardState.review,
        currentStepIndex: 0,
        currentStability: 6.0,
        currentDifficulty: 5.0,
        currentIntervalDays: 6,
        currentReps: 3,
        currentLapses: 0,
      );

      final hardIvl = previews[ReviewGrade.hard]!.intervalDays;
      final goodIvl = previews[ReviewGrade.good]!.intervalDays;
      final easyIvl = previews[ReviewGrade.easy]!.intervalDays;

      expect(hardIvl, lessThan(goodIvl));
      expect(goodIvl, lessThan(easyIvl));
    });

    test('Repeated lapses trigger Leech detection and optional suspension', () {
      final out = scheduler.schedule(
        grade: ReviewGrade.again,
        currentState: CardState.review,
        currentStepIndex: 0,
        currentStability: 8.0,
        currentDifficulty: 6.5,
        currentIntervalDays: 8,
        currentReps: 5,
        currentLapses: 5,
        leechThreshold: 6,
        suspendLeeches: true,
      );

      expect(out.state, CardState.relearning);
      expect(out.lapses, 6);
      expect(out.becameLeech, isTrue);
      expect(out.suspended, isTrue);
    });

    test('FsrsWeightOptimizer optimizes 17 weights from revlog sequences', () async {
      final optimizer = FsrsWeightOptimizer();
      final revlog = <Map<String, Object?>>[];
      const baseTime = 1700000000000;

      // Generate synthetic personal review history across 250 cards (1,000+ reviews)
      for (var c = 0; c < 250; c++) {
        final cardId = 'card_$c';
        final grades = (c % 5 == 0) ? [3, 3, 1, 3, 4] : [3, 3, 3, 4];
        var t = baseTime + c * 10000;
        var intervalDays = 1;
        for (var i = 0; i < grades.length; i++) {
          revlog.add({
            'card_id': cardId,
            'grade': grades[i],
            'state_before': i == 0 ? 0 : 2,
            'reviewed_at': t,
          });
          intervalDays = grades[i] == 1 ? 1 : intervalDays * 3;
          t += intervalDays * 86400000;
        }
      }

      final result = await optimizer.optimizeFromRevlog(revlog);
      expect(result.totalReviews, greaterThanOrEqualTo(1000));
      expect(result.metRecommendedThreshold, isTrue);
      expect(result.optimizedWeights.length, 17);
      expect(result.optimizedLogLoss, lessThanOrEqualTo(result.initialLogLoss));
      // Monotonic initial stability constraint: w0 < w1 < w2 < w3
      expect(result.optimizedWeights[0], lessThan(result.optimizedWeights[1]));
      expect(result.optimizedWeights[1], lessThan(result.optimizedWeights[2]));
      expect(result.optimizedWeights[2], lessThan(result.optimizedWeights[3]));
    });
  });

  group('Surface-Form Cloze Masking (ClozeMasker & VocabCard)', () {
    test('Masks inflected surface forms (running, ran, studies, phenomena) when card stores lemma', () {
      // 1. Consonant doubling participle: card stores lemma "run", sentence has "running"
      final clozeRunning = ClozeMasker.maskSentence(
        sentence: 'She was running across the marathon track.',
        word: 'run',
        lemma: 'run',
      );
      expect(clozeRunning, 'She was [...] across the marathon track.');
      expect(clozeRunning.contains('running'), isFalse);

      // 2. Irregular past tense: card stores lemma "run", sentence has "ran"
      final clozeRan = ClozeMasker.maskSentence(
        sentence: 'He ran five miles before dawn.',
        word: 'run',
        lemma: 'run',
      );
      expect(clozeRan, 'He [...] five miles before dawn.');

      // 3. -y -> -ies inflection: card stores lemma "study", sentence has "studies"
      final clozeStudies = ClozeMasker.maskSentence(
        sentence: 'She studies cognitive psychology at university.',
        word: 'study',
        lemma: 'study',
      );
      expect(clozeStudies, 'She [...] cognitive psychology at university.');

      // 4. Classical plural: card stores lemma "phenomenon", sentence has "phenomena"
      final clozePhenomena = ClozeMasker.maskSentence(
        sentence: 'Scientists observed unpredictable phenomena.',
        word: 'phenomenon',
        lemma: 'phenomenon',
      );
      expect(clozePhenomena, 'Scientists observed unpredictable [...].');

      // 5. VocabCard.effectiveClozeSentence repairs legacy unmasked cloze_sentence
      final legacyCard = VocabCard(
        id: 'card_run',
        deckId: 'default_deck',
        word: 'run',
        lemma: 'run',
        phonetic: '/rʌn/',
        translation: '(v.) chạy',
        contextSentence: 'The athlete is running effortlessly.',
        clozeSentence: 'The athlete is running effortlessly.', // unmasked legacy value
        intervalDays: 0,
        repetitions: 0,
        easeFactor: 2.5,
        nextReviewAt: DateTime.now(),
      );
      expect(
        legacyCard.effectiveClozeSentence,
        'The athlete is [...] effortlessly.',
      );
    });
  });

  group('Offline SQLite Dictionary Asset (Open Dict Data US/UK IPA) & Contextual dict_cache', () {
    test('Queries 205k-word offline_dict.db SQLite asset with US and UK pronunciations', () async {
      final dictDb = OfflineDictionaryDatabase(
        overridePath: p.absolute('assets/nlp/offline_dict.db'),
      );
      final meta = await dictDb.getMetadata();
      expect(int.parse(meta['total_entries'] ?? '0'), greaterThan(200000));
      expect(int.parse(meta['vi_entries'] ?? '0'), greaterThan(100000));
      expect(int.parse(meta['ipa_us_entries'] ?? '0'), greaterThan(190000));
      expect(int.parse(meta['ipa_uk_entries'] ?? '0'), greaterThan(60000));
      expect(meta['ipa_source'], contains('open-dict-data/ipa-dict'));
      expect(meta['license'], contains('CC BY-SA 4.0'));

      final batch = await dictDb.lookupBatch([
        'ubiquitous',
        'ephemeral',
        'serendipity',
        'algorithm',
        'photosynthesis',
        'schedule',
        'water',
        'better',
        'car',
      ]);
      expect(batch['ubiquitous']?.vi, isNotEmpty);
      expect(batch['algorithm']?.ipaUs, isNotEmpty);
      expect(batch['photosynthesis']?.ipaUs, isNotEmpty);

      // Verify distinct American (en_US) vs British (en_UK) IPA from open-dict-data/ipa-dict
      expect(batch['schedule']?.ipaUs, isNotEmpty);
      expect(batch['schedule']?.ipaUk, isNotEmpty);
      expect(batch['schedule']?.ipaUs, isNot(equals(batch['schedule']?.ipaUk)));
      expect(batch['water']?.ipaUs, isNotEmpty);
      expect(batch['water']?.ipaUk, isNotEmpty);
      expect(batch['water']?.ipaUs, isNot(equals(batch['water']?.ipaUk)));
      expect(batch['better']?.ipaUs, isNotEmpty);
      expect(batch['better']?.ipaUk, isNotEmpty);
      expect(batch['car']?.ipaUs, isNotEmpty);
      expect(batch['car']?.ipaUk, isNotEmpty);

      await dictDb.close();
    });
  });

  group('SQLite Schema Migration (onUpgrade v1 -> v3 and v2 -> v3)', () {
    test('Upgrades v1 SM-2 database to v3 FSRS schema, backfills stability & surface cloze, and creates indexes', () async {
      final dbDir = await databaseFactory.getDatabasesPath();
      final migPath = p.join(
        dbDir,
        'test_mig_v1_to_v3_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      try {
        await databaseFactory.deleteDatabase(migPath);
      } catch (_) {}

      // 1. Create a legacy v1 database (SM-2 schema without FSRS columns, dict_cache, or revlog)
      final v1Db = await databaseFactory.openDatabase(
        migPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE decks (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE cards (
                id TEXT PRIMARY KEY,
                deck_id TEXT NOT NULL,
                word TEXT NOT NULL UNIQUE,
                phonetic TEXT NOT NULL,
                translation TEXT NOT NULL,
                context_sentence TEXT NOT NULL DEFAULT '',
                interval_days INTEGER NOT NULL DEFAULT 0,
                repetitions INTEGER NOT NULL DEFAULT 0,
                ease_factor REAL NOT NULL DEFAULT 2.5,
                next_review_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE radicals (
                id TEXT PRIMARY KEY,
                symbol TEXT NOT NULL UNIQUE,
                meaning TEXT NOT NULL,
                stroke_count INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE card_radical_edges (
                card_id TEXT NOT NULL,
                radical_id TEXT NOT NULL,
                decomposition_role TEXT NOT NULL DEFAULT 'component',
                PRIMARY KEY (card_id, radical_id)
              )
            ''');

            await db.insert('decks', {
              'id': 'default_deck',
              'name': 'Legacy v1 Deck',
              'created_at': 1700000000000,
            });
            await db.insert('cards', {
              'id': 'card_run',
              'deck_id': 'default_deck',
              'word': 'run',
              'phonetic': '/rʌn/',
              'translation': 'chạy',
              'context_sentence': 'She was running in the rain.',
              'interval_days': 12,
              'repetitions': 4,
              'ease_factor': 2.5,
              'next_review_at': 1700000000000,
              'created_at': 1700000000000,
            });
          },
        ),
      );
      await v1Db.close();

      // 2. Open with LocalDatabase (v3) to trigger _onUpgrade(v1 -> v3)
      final upgradedLocalDb = LocalDatabase(overridePath: migPath);
      final db = await upgradedLocalDb.database;

      final cards = await db.query(
        'cards',
        where: 'id = ?',
        whereArgs: const ['card_run'],
      );
      expect(cards, hasLength(1));
      final cardRow = cards.first;
      expect(cardRow['state'], 2); // Backfilled to CardState.review
      expect(cardRow['stability'], 12.0); // Backfilled from interval_days
      expect(cardRow['phonetic_us'], '/rʌn/'); // Backfilled in v4 migration
      expect(cardRow['phonetic_uk'], '');
      expect(
        cardRow['cloze_sentence'],
        'She was [...] in the rain.',
      ); // Backfilled surface-form Cloze!

      // Verify new tables and composite dict_cache (word, sentence_hash) work
      await db.insert('dict_cache', {
        'word': 'bank',
        'sentence_hash': 'hash_river',
        'context_sentence': 'He sat by the river bank.',
        'lemma': 'bank',
        'phonetic': '/bæŋk/',
        'translation': '(n.) bờ sông',
        'part_of_speech': 'noun',
        'updated_at': 1700000000000,
      });
      await db.insert('dict_cache', {
        'word': 'bank',
        'sentence_hash': 'hash_money',
        'context_sentence': 'She deposited money in the bank.',
        'lemma': 'bank',
        'phonetic': '/bæŋk/',
        'translation': '(n.) ngân hàng',
        'part_of_speech': 'noun',
        'updated_at': 1700000000000,
      });
      final bankRows = await db.query(
        'dict_cache',
        where: 'word = ?',
        whereArgs: const ['bank'],
      );
      expect(bankRows, hasLength(2));

      // Verify indexes exist in sqlite_master
      final indexRows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
      );
      final indexNames = indexRows.map((r) => r['name'] as String).toSet();
      expect(
        indexNames,
        containsAll([
          'idx_cards_deck_due',
          'idx_cards_word',
          'idx_cards_lemma',
          'idx_edges_radical',
          'idx_revlog_reviewed_at',
          'idx_dict_cache_word',
        ]),
      );

      await upgradedLocalDb.close();
      try {
        await databaseFactory.deleteDatabase(migPath);
      } catch (_) {}
    });

    test('Upgrades v2 single-key dict_cache to v3 composite (word, sentence_hash) preserving rows', () async {
      final dbDir = await databaseFactory.getDatabasesPath();
      final migPath = p.join(
        dbDir,
        'test_mig_v2_to_v3_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      try {
        await databaseFactory.deleteDatabase(migPath);
      } catch (_) {}

      final v2Db = await databaseFactory.openDatabase(
        migPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE decks (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT "", created_at INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE cards (id TEXT PRIMARY KEY, deck_id TEXT NOT NULL, word TEXT NOT NULL UNIQUE, lemma TEXT NOT NULL DEFAULT "", phonetic TEXT NOT NULL, translation TEXT NOT NULL, part_of_speech TEXT NOT NULL DEFAULT "vocab", context_sentence TEXT NOT NULL DEFAULT "", cloze_sentence TEXT NOT NULL DEFAULT "", audio_url TEXT NOT NULL DEFAULT "", state INTEGER NOT NULL DEFAULT 0, step_index INTEGER NOT NULL DEFAULT 0, stability REAL NOT NULL DEFAULT 0.0, difficulty REAL NOT NULL DEFAULT 5.0, interval_days INTEGER NOT NULL DEFAULT 0, repetitions INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0, ease_factor REAL NOT NULL DEFAULT 2.5, is_leech INTEGER NOT NULL DEFAULT 0, is_suspended INTEGER NOT NULL DEFAULT 0, last_review_at INTEGER, next_review_at INTEGER NOT NULL, created_at INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE radicals (id TEXT PRIMARY KEY, symbol TEXT NOT NULL UNIQUE, meaning TEXT NOT NULL, stroke_count INTEGER NOT NULL DEFAULT 0)',
            );
            await db.execute(
              'CREATE TABLE card_radical_edges (card_id TEXT NOT NULL, radical_id TEXT NOT NULL, decomposition_role TEXT NOT NULL DEFAULT "component", PRIMARY KEY (card_id, radical_id))',
            );
            await db.execute('''
              CREATE TABLE dict_cache (
                word TEXT PRIMARY KEY,
                lemma TEXT NOT NULL DEFAULT '',
                phonetic TEXT NOT NULL DEFAULT '',
                translation TEXT NOT NULL DEFAULT '',
                part_of_speech TEXT NOT NULL DEFAULT 'vocab',
                audio_url TEXT NOT NULL DEFAULT '',
                radicals_json TEXT NOT NULL DEFAULT '[]',
                updated_at INTEGER NOT NULL
              )
            ''');
            await db.insert('dict_cache', {
              'word': 'resilient',
              'lemma': 'resilient',
              'phonetic': '/rɪˈzɪliənt/',
              'translation': '(adj.) kiên cường, đàn hồi',
              'part_of_speech': 'adj',
              'audio_url': '',
              'radicals_json': '[]',
              'updated_at': 1700000000000,
            });
          },
        ),
      );
      await v2Db.close();

      final upgradedLocalDb = LocalDatabase(overridePath: migPath);
      final db = await upgradedLocalDb.database;

      final preserved = await db.query(
        'dict_cache',
        where: 'word = ?',
        whereArgs: const ['resilient'],
      );
      expect(preserved, hasLength(1));
      expect(preserved.first['sentence_hash'], '');
      expect(preserved.first['translation'], '(adj.) kiên cường, đàn hồi');

      await upgradedLocalDb.close();
      try {
        await databaseFactory.deleteDatabase(migPath);
      } catch (_) {}
    });
  });

  group('SQLite FSRS Queue, Graph Suggestions, Stats & Backup/CSV', () {
    late LocalDatabase localDb;
    late OfflineDictionaryDatabase offlineDictDb;
    late SettingsRepository settingsRepo;
    late DeckRepositoryImpl deckRepo;
    late NlpExtractorRepositoryImpl extractorRepo;
    late StatsRepository statsRepo;
    late BackupService backupService;

    setUp(() async {
      localDb = LocalDatabase(overridePath: inMemoryDatabasePath);
      offlineDictDb = OfflineDictionaryDatabase(
        overridePath: p.absolute('assets/nlp/offline_dict.db'),
      );
      settingsRepo = SettingsRepository(localDb);
      const fsrs = FsrsScheduler();
      deckRepo = DeckRepositoryImpl(
        localDatabase: localDb,
        fsrsScheduler: fsrs,
        settingsRepository: settingsRepo,
      );
      extractorRepo = NlpExtractorRepositoryImpl(
        analyzerDataSource: HybridNlpAnalyzerDataSourceImpl(
          localDatabase: localDb,
          offlineDictionaryDatabase: offlineDictDb,
        ),
        localDatabase: localDb,
      );
      statsRepo = StatsRepository(
        localDatabase: localDb,
        fsrsScheduler: fsrs,
      );
      backupService = BackupService(localDb);
    });

    tearDown(() async {
      await offlineDictDb.close();
      await localDb.close();
    });

    test('Daily new card limit caps due cards and graph suggests shared-root words', () async {
      await settingsRepo.saveSettings(
        const StudySettings(newCardsPerDay: 3, maxReviewsPerDay: 50),
      );

      final dueRes = await deckRepo.getDueCards('default_deck');
      final dueCards = dueRes.getOrElse((_) => const []);
      expect(dueCards.length, 3);

      // Check graph-based related word suggestions for 'inspect' (shares -spect- with 'perspective')
      final relatedRes =
          await deckRepo.getRelatedWordsByRadicals('card_inspect');
      final related = relatedRes.getOrElse((_) => const []);
      expect(related.any((r) => r.card.word == 'perspective'), isTrue);

      // Submit a review and verify stats heatmap + retention update
      final firstCard = dueCards.first;
      final reviewRes = await deckRepo.submitReview(
        card: firstCard,
        grade: ReviewGrade.good,
      );
      expect(reviewRes.isRight(), isTrue);

      final stats = await statsRepo.getStudyStats();
      expect(stats.reviewsToday, 1);
      expect(stats.currentStreakDays, 1);
      expect(stats.trueRetention30d, 1.0);
    });

    test('Batch NLP extraction uses SQLite dictionary with US/UK IPA, masks surface-form Cloze & updates backup timestamp', () async {
      final analyzedRes = await extractorRepo.analyzeText(
        'Scientists were running experiments to inspect unpredictable water schedule phenomena.',
        enableOnlineLookup: false,
      );
      final tokens = analyzedRes.getOrElse((_) => const []);
      expect(tokens, isNotEmpty);

      // Verify "running" has lemma "run", surface word "running" masked in cloze, and Vietnamese definition from offline_dict.db
      final runningToken =
          tokens.firstWhere((t) => t.surfaceWord == 'running');
      expect(runningToken.lemma, 'run');
      expect(runningToken.clozeSentence, contains('[...]'));
      expect(runningToken.clozeSentence.contains('running'), isFalse);

      // Verify dual American (US) and British (UK) IPA pronunciations retrieved from SQLite
      final scheduleToken =
          tokens.firstWhere((t) => t.surfaceWord == 'schedule');
      expect(scheduleToken.phoneticUs, isNotEmpty);
      expect(scheduleToken.phoneticUk, isNotEmpty);
      expect(scheduleToken.phoneticUs, isNot(equals(scheduleToken.phoneticUk)));

      final saveRes = await extractorRepo.createCardsAndGraphNodes(
        deckId: 'default_deck',
        selectedTokens: tokens,
      );
      expect(saveRes.getOrElse((_) => 0), tokens.length);

      // Verify persisted card in SQLite stores both phonetic_us and phonetic_uk
      final db = await localDb.database;
      final savedSchedule = await db.query(
        'cards',
        where: 'word = ?',
        whereArgs: const ['schedule'],
      );
      expect(savedSchedule, hasLength(1));
      expect(savedSchedule.first['phonetic_us'], scheduleToken.phoneticUs);
      expect(savedSchedule.first['phonetic_uk'], scheduleToken.phoneticUk);

      // Exporting JSON backup automatically records lastBackupEpochMs so Web reminder clears
      final beforeSettings = await settingsRepo.loadSettings();
      expect(beforeSettings.shouldRemindBackup(isWeb: true), isTrue);

      final jsonBytes = await backupService.exportFullBackupJsonBytes();
      expect(jsonBytes, isNotEmpty);

      final afterSettings = await settingsRepo.loadSettings();
      expect(afterSettings.lastBackupEpochMs, isNotNull);
      expect(afterSettings.shouldRemindBackup(isWeb: true), isFalse);

      final csvBytes = await backupService.exportAnkiCsvBytes();
      final importedCount = await backupService.importAnkiCsvBytes(csvBytes);
      expect(importedCount, greaterThanOrEqualTo(6));
    });

    test(
      'Morphology rejects substring false positives (fishermen vs another/weathered/dozen/green/uneven/wooden)',
      () async {
        final analyzer = HybridNlpAnalyzerDataSourceImpl(
          localDatabase: localDb,
        );
        final nlpRepo = NlpExtractorRepositoryImpl(
          analyzerDataSource: analyzer,
          localDatabase: localDb,
        );

        const sentence =
            'Another weathered wooden boat carried a dozen green fishermen across uneven water.';
        final extracted = await analyzer.tokenizeAndAnalyze(
          sentence,
          enableOnlineLookup: false,
        );
        final byWord = {for (final t in extracted) t.surfaceWord: t};

        final fishermenRadicals =
            byWord['fishermen']!.radicals.map((r) => r.symbol).toSet();
        expect(fishermenRadicals, contains('fish'));
        expect(fishermenRadicals, contains('man'));
        expect(fishermenRadicals, isNot(contains('-her-')));
        expect(fishermenRadicals, isNot(contains('-en')));

        expect(
          byWord['green']!.radicals.map((r) => r.symbol),
          isNot(contains('-en')),
        );
        expect(
          byWord['dozen']!.radicals.map((r) => r.symbol),
          isNot(contains('-en')),
        );
        expect(
          byWord['another']!.radicals.map((r) => r.symbol),
          isNot(contains('-her-')),
        );
        expect(
          byWord['weathered']!.radicals.map((r) => r.symbol),
          isNot(contains('-her-')),
        );
        expect(
          byWord['wooden']!.radicals.map((r) => r.symbol),
          contains('-en'),
        );
        expect(
          byWord['uneven']!.radicals.map((r) => r.symbol),
          contains('un-'),
        );

        final saveRes = await nlpRepo.createCardsAndGraphNodes(
          deckId: 'default_deck',
          selectedTokens: extracted,
        );
        expect(saveRes.isRight(), isTrue);

        final relatedRes =
            await deckRepo.getRelatedWordsByRadicals('card_fishermen');
        final relatedWords = relatedRes
            .getOrElse((_) => const [])
            .map((s) => s.card.word)
            .toSet();
        expect(relatedWords, isNot(contains('another')));
        expect(relatedWords, isNot(contains('weathered')));
        expect(relatedWords, isNot(contains('dozen')));
        expect(relatedWords, isNot(contains('green')));
        expect(relatedWords, isNot(contains('uneven')));
        expect(relatedWords, isNot(contains('wooden')));
      },
    );

    test(
      'IpaNormalizer, Context-Window POS, Phrasal Verbs MWE & Deck-Scoped Duplicates',
      () async {
        // 1. Broad Learner IPA Normalization
        expect(IpaNormalizer.normalize('/ˈɫɪft/'), '/lɪft/');
        expect(IpaNormalizer.normalize('/lˈɪft/'), '/lɪft/');
        expect(IpaNormalizer.normalize('/ˈtɹænspɔɹt/'), '/ˈtrænspɔrt/');

        // 2. Context-Window POS + Multi-Word Phrasal Verbs against offline_dict.db
        final dictAssetPath = p.join(
          Directory.current.path,
          'assets',
          'nlp',
          'offline_dict.db',
        );
        final offlineDict =
            OfflineDictionaryDatabase(overridePath: dictAssetPath);
        final analyzer = HybridNlpAnalyzerDataSourceImpl(
          localDatabase: localDb,
          offlineDictionaryDatabase: offlineDict,
        );
        final nlpRepo = NlpExtractorRepositoryImpl(
          analyzerDataSource: analyzer,
          localDatabase: localDb,
        );

        const sentence =
            'The fog began to lift as we look forward to the trip and never give up.';
        final extracted = await analyzer.tokenizeAndAnalyze(
          sentence,
          enableOnlineLookup: false,
        );
        final byWord = {for (final t in extracted) t.surfaceWord: t};

        // Phrasal verbs extracted as cohesive tokens with phrase Cloze masking
        expect(byWord.containsKey('look forward to'), isTrue);
        expect(byWord.containsKey('give up'), isTrue);
        expect(byWord['look forward to']!.clozeSentence, contains('[...]'));
        expect(byWord['give up']!.clozeSentence, contains('[...]'));

        // Context-window POS predicts 'lift' after "began to" as verb & normalizes IPA
        expect(byWord['lift']?.partOfSpeech, 'verb');
        expect(byWord['lift']?.phoneticUs, isNot(contains('ɫ')));

        // 3. Deck-scoped duplicate check
        final newDeckRes = await deckRepo.createDeck(
          name: 'Second Deck',
          description: 'Test deck',
        );
        final secondDeckId = newDeckRes.getOrElse((_) => throw Exception()).id;

        final inDefault = await nlpRepo.analyzeText(
          'Engineers inspect the structure.',
          enableOnlineLookup: false,
          deckId: 'default_deck',
        );
        final inSecond = await nlpRepo.analyzeText(
          'Engineers inspect the structure.',
          enableOnlineLookup: false,
          deckId: secondDeckId,
        );
        final inspectDefault = inDefault
            .getOrElse((_) => const [])
            .firstWhere((t) => t.surfaceWord == 'inspect');
        final inspectSecond = inSecond
            .getOrElse((_) => const [])
            .firstWhere((t) => t.surfaceWord == 'inspect');
        expect(inspectDefault.isAlreadySaved, isTrue);
        expect(inspectSecond.isAlreadySaved, isFalse);

        await offlineDict.close();
      },
    );
  });
}
