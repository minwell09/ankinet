import 'dart:math' as math;

import 'package:fpdart/fpdart.dart';

import '../../../../core/database/local_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/settings/settings_repository.dart';
import '../../../../core/settings/study_settings.dart';
import '../../../../core/srs/fsrs_scheduler.dart';
import '../../../../core/srs/sm2_scheduler.dart';
import '../../../../core/utils/cloze_masker.dart';
import '../../domain/entities/deck.dart';
import '../../domain/entities/related_word_suggestion.dart';
import '../../domain/entities/vocab_card.dart';
import '../../domain/repositories/deck_repository.dart';

class DeckRepositoryImpl implements DeckRepository {
  final LocalDatabase localDatabase;
  final FsrsScheduler fsrsScheduler;
  final SettingsRepository settingsRepository;

  const DeckRepositoryImpl({
    required this.localDatabase,
    required this.fsrsScheduler,
    required this.settingsRepository,
  });

  int _startOfTodayEpochMs() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  @override
  Future<Either<Failure, List<Deck>>> getDecks() async {
    try {
      final db = await localDatabase.database;
      final settings = await settingsRepository.loadSettings();
      final now = DateTime.now().millisecondsSinceEpoch;
      final learnHorizon =
          DateTime.now().add(const Duration(minutes: 20)).millisecondsSinceEpoch;
      final todayStart = _startOfTodayEpochMs();

      // Single aggregated SQL query across decks + cards using idx_cards_deck_due
      final rows = await db.rawQuery(
        '''
        SELECT
          d.id,
          d.name,
          d.description,
          COUNT(c.id) AS total_cards,
          SUM(CASE WHEN c.is_suspended = 0 AND c.state = 0 THEN 1 ELSE 0 END) AS new_cards,
          SUM(CASE WHEN c.is_suspended = 0 AND c.state IN (1, 3) AND c.next_review_at <= ? THEN 1 ELSE 0 END) AS learning_due,
          SUM(CASE WHEN c.is_suspended = 0 AND c.state = 2 AND c.next_review_at <= ? THEN 1 ELSE 0 END) AS review_due,
          SUM(CASE WHEN c.is_leech = 1 THEN 1 ELSE 0 END) AS leech_cards
        FROM decks d
        LEFT JOIN cards c ON c.deck_id = d.id
        GROUP BY d.id
        ORDER BY d.created_at ASC
        ''',
        [learnHorizon, now],
      );

      // Count how many new cards were already introduced today per deck
      final introducedRows = await db.rawQuery(
        '''
        SELECT deck_id, COUNT(DISTINCT card_id) AS cnt
        FROM revlog
        WHERE reviewed_at >= ? AND state_before = 0
        GROUP BY deck_id
        ''',
        [todayStart],
      );
      final introducedByDeck = <String, int>{
        for (final r in introducedRows)
          (r['deck_id'] as String): (r['cnt'] as int?) ?? 0,
      };

      final decks = <Deck>[];
      for (final row in rows) {
        final deckId = row['id'] as String;
        final total = (row['total_cards'] as int?) ?? 0;
        final rawNew = (row['new_cards'] as int?) ?? 0;
        final learningDue = (row['learning_due'] as int?) ?? 0;
        final reviewDue = (row['review_due'] as int?) ?? 0;
        final leeches = (row['leech_cards'] as int?) ?? 0;

        final introducedToday = introducedByDeck[deckId] ?? 0;
        final remainingNewQuota =
            math.max(0, settings.newCardsPerDay - introducedToday);
        final allowedNew = math.min(rawNew, remainingNewQuota);
        final allowedReview = math.min(reviewDue, settings.maxReviewsPerDay);
        final totalDue = learningDue + allowedReview + allowedNew;

        decks.add(
          Deck(
            id: deckId,
            name: row['name'] as String,
            description: row['description'] as String,
            totalCards: total,
            dueCards: totalDue,
            newCards: allowedNew,
            learningCards: learningDue,
            reviewDueCards: allowedReview,
            leechCards: leeches,
          ),
        );
      }

      return Right(decks);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch decks: $e'));
    }
  }

  @override
  Future<Either<Failure, List<VocabCard>>> getDueCards(
    String deckId, {
    StudySettings? settings,
  }) async {
    try {
      final db = await localDatabase.database;
      final cfg = settings ?? await settingsRepository.loadSettings();
      final now = DateTime.now().millisecondsSinceEpoch;
      final learnHorizon =
          DateTime.now().add(const Duration(minutes: 20)).millisecondsSinceEpoch;
      final todayStart = _startOfTodayEpochMs();

      // 1. Learning & Relearning cards (highest priority, indexed query + LIMIT)
      final learningRows = await db.query(
        'cards',
        where:
            'deck_id = ? AND is_suspended = 0 AND state IN (1, 3) AND next_review_at <= ?',
        whereArgs: [deckId, learnHorizon],
        orderBy: 'next_review_at ASC',
        limit: 100,
      );

      // 2. Due Review cards (capped by daily review limit)
      final reviewRows = await db.query(
        'cards',
        where:
            'deck_id = ? AND is_suspended = 0 AND state = 2 AND next_review_at <= ?',
        whereArgs: [deckId, now],
        orderBy: 'next_review_at ASC',
        limit: cfg.maxReviewsPerDay,
      );

      // 3. New cards (capped by remaining daily new-card quota)
      final introRes = await db.rawQuery(
        '''
        SELECT COUNT(DISTINCT card_id) AS cnt
        FROM revlog
        WHERE deck_id = ? AND reviewed_at >= ? AND state_before = 0
        ''',
        [deckId, todayStart],
      );
      final introducedToday = (introRes.first['cnt'] as int?) ?? 0;
      final remainingNew = math.max(0, cfg.newCardsPerDay - introducedToday);

      final List<Map<String, Object?>> newRows = remainingNew > 0
          ? await db.query(
              'cards',
              where: 'deck_id = ? AND is_suspended = 0 AND state = 0',
              whereArgs: [deckId],
              orderBy: 'created_at ASC',
              limit: remainingNew,
            )
          : const [];

      final cards = <VocabCard>[
        ...learningRows.map(VocabCard.fromRow),
        ...reviewRows.map(VocabCard.fromRow),
        ...newRows.map(VocabCard.fromRow),
      ];

      return Right(cards);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch due cards: $e'));
    }
  }

  @override
  Future<Either<Failure, FsrsScheduleOutput>> submitReview({
    required VocabCard card,
    required ReviewGrade grade,
    StudySettings? settings,
    int durationMs = 0,
  }) async {
    try {
      final db = await localDatabase.database;
      final cfg = settings ?? await settingsRepository.loadSettings();
      final now = DateTime.now();
      final activeFsrs = cfg.hasCustomFsrsWeights
          ? FsrsScheduler(w: cfg.effectiveFsrsWeights)
          : fsrsScheduler;

      final scheduleOut = activeFsrs.schedule(
        grade: grade,
        currentState: card.state,
        currentStepIndex: card.stepIndex,
        currentStability: card.stability,
        currentDifficulty: card.difficulty,
        currentIntervalDays: card.intervalDays,
        currentReps: card.repetitions,
        currentLapses: card.lapses,
        lastReviewAt: card.lastReviewAt,
        now: now,
        desiredRetention: cfg.desiredRetention,
        learningStepsMinutes: cfg.learningStepsMinutes,
        relearningStepsMinutes: cfg.relearningStepsMinutes,
        leechThreshold: cfg.leechThreshold,
        suspendLeeches: cfg.suspendLeeches,
      );

      final isLeechNow = card.isLeech || scheduleOut.becameLeech;
      final isSuspendedNow = card.isSuspended || scheduleOut.suspended;

      await db.transaction((txn) async {
        await txn.update(
          'cards',
          {
            'state': scheduleOut.state.code,
            'step_index': scheduleOut.stepIndex,
            'stability': scheduleOut.stability,
            'difficulty': scheduleOut.difficulty,
            'interval_days': scheduleOut.intervalDays,
            'repetitions': scheduleOut.reps,
            'lapses': scheduleOut.lapses,
            'is_leech': isLeechNow ? 1 : 0,
            'is_suspended': isSuspendedNow ? 1 : 0,
            'last_review_at': now.millisecondsSinceEpoch,
            'next_review_at': scheduleOut.nextReviewAt.millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [card.id],
        );

        await txn.insert('revlog', {
          'card_id': card.id,
          'deck_id': card.deckId,
          'grade': grade.index + 1,
          'state_before': card.state.code,
          'state_after': scheduleOut.state.code,
          'stability_after': scheduleOut.stability,
          'difficulty_after': scheduleOut.difficulty,
          'interval_days': scheduleOut.intervalDays,
          'duration_ms': durationMs,
          'reviewed_at': now.millisecondsSinceEpoch,
        });
      });

      return Right(scheduleOut);
    } catch (e) {
      return Left(DatabaseFailure('Failed to submit FSRS card review: $e'));
    }
  }

  @override
  Future<Either<Failure, List<RelatedWordSuggestion>>> getRelatedWordsByRadicals(
    String cardId, {
    int limit = 6,
  }) async {
    try {
      final db = await localDatabase.database;
      final rows = await db.rawQuery(
        '''
        SELECT
          c.*,
          GROUP_CONCAT(r.symbol, ', ') AS shared_symbols,
          COUNT(r.id) AS shared_count
        FROM card_radical_edges e1
        INNER JOIN card_radical_edges e2
          ON e1.radical_id = e2.radical_id AND e2.card_id != e1.card_id
        INNER JOIN cards c
          ON c.id = e2.card_id
        INNER JOIN radicals r
          ON r.id = e1.radical_id
        WHERE e1.card_id = ?
        GROUP BY c.id
        ORDER BY shared_count DESC, c.next_review_at ASC
        LIMIT ?
        ''',
        [cardId, limit],
      );

      final suggestions = rows.map((row) {
        final symbolsStr = (row['shared_symbols'] as String?) ?? '';
        final symbols = symbolsStr
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        return RelatedWordSuggestion(
          card: VocabCard.fromRow(row),
          sharedRadicals: symbols,
        );
      }).toList();

      return Right(suggestions);
    } catch (e) {
      return Left(DatabaseFailure('Failed to query related graph words: $e'));
    }
  }

  @override
  Future<Either<Failure, List<VocabCard>>> getLeechCards({String? deckId}) async {
    try {
      final db = await localDatabase.database;
      final rows = await db.query(
        'cards',
        where: deckId != null ? 'deck_id = ? AND is_leech = 1' : 'is_leech = 1',
        whereArgs: deckId != null ? [deckId] : null,
        orderBy: 'lapses DESC',
      );
      return Right(rows.map(VocabCard.fromRow).toList());
    } catch (e) {
      return Left(DatabaseFailure('Failed to load leech cards: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> toggleSuspendCard(
    String cardId, {
    required bool suspended,
  }) async {
    try {
      final db = await localDatabase.database;
      await db.update(
        'cards',
        {'is_suspended': suspended ? 1 : 0},
        where: 'id = ?',
        whereArgs: [cardId],
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update card suspension: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> resetLeechCard(String cardId) async {
    try {
      final db = await localDatabase.database;
      await db.update(
        'cards',
        {
          'is_leech': 0,
          'is_suspended': 0,
          'lapses': 0,
          'state': 0,
          'step_index': 0,
          'next_review_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [cardId],
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to reset leech card: $e'));
    }
  }

  @override
  Future<Either<Failure, List<VocabCard>>> getCardsByDeck(String deckId) async {
    try {
      final db = await localDatabase.database;
      final rows = await db.query(
        'cards',
        where: 'deck_id = ?',
        whereArgs: [deckId],
        orderBy: 'created_at DESC, word ASC',
      );
      return Right(rows.map(VocabCard.fromRow).toList());
    } catch (e) {
      return Left(DatabaseFailure('Failed to load cards: $e'));
    }
  }

  @override
  Future<Either<Failure, VocabCard>> updateCard({
    required String cardId,
    required String word,
    required String partOfSpeech,
    required String phoneticUs,
    required String phoneticUk,
    required String translation,
    required String contextSentence,
  }) async {
    try {
      final db = await localDatabase.database;
      final cleanWord = word.trim();
      final cleanPos =
          partOfSpeech.trim().isEmpty ? 'vocab' : partOfSpeech.trim();
      final cleanUs = phoneticUs.trim();
      final cleanUk = phoneticUk.trim();
      final cleanPhonetic = cleanUs.isNotEmpty ? cleanUs : cleanUk;
      final cleanSentence = contextSentence.trim();
      final cloze = cleanSentence.isEmpty
          ? ''
          : ClozeMasker.maskSentence(
              sentence: cleanSentence,
              word: cleanWord,
              lemma: cleanWord,
            );

      await db.update(
        'cards',
        {
          'word': cleanWord,
          'part_of_speech': cleanPos,
          'phonetic': cleanPhonetic,
          'phonetic_us': cleanUs,
          'phonetic_uk': cleanUk,
          'translation': translation.trim(),
          'context_sentence': cleanSentence,
          'cloze_sentence': cloze,
        },
        where: 'id = ?',
        whereArgs: [cardId],
      );

      final rows = await db.query(
        'cards',
        where: 'id = ?',
        whereArgs: [cardId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return const Left(DatabaseFailure('Card not found after update'));
      }
      return Right(VocabCard.fromRow(rows.first));
    } catch (e) {
      return Left(DatabaseFailure('Failed to update card: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteCard(String cardId) async {
    try {
      final db = await localDatabase.database;
      await db.transaction((txn) async {
        await txn.delete('revlog', where: 'card_id = ?', whereArgs: [cardId]);
        await txn.delete('cards', where: 'id = ?', whereArgs: [cardId]);
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to delete card: $e'));
    }
  }

  @override
  Future<Either<Failure, Deck>> createDeck({
    required String name,
    required String description,
  }) async {
    try {
      final db = await localDatabase.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = 'deck_$now';
      await db.insert('decks', {
        'id': id,
        'name': name.trim(),
        'description': description.trim(),
        'created_at': now,
      });
      return Right(
        Deck(
          id: id,
          name: name.trim(),
          description: description.trim(),
          totalCards: 0,
          dueCards: 0,
        ),
      );
    } catch (e) {
      return Left(DatabaseFailure('Failed to create deck: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updateDeck({
    required String deckId,
    required String name,
    required String description,
  }) async {
    try {
      final db = await localDatabase.database;
      await db.update(
        'decks',
        {
          'name': name.trim(),
          'description': description.trim(),
        },
        where: 'id = ?',
        whereArgs: [deckId],
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update deck: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteDeck(String deckId) async {
    try {
      final db = await localDatabase.database;
      await db.transaction((txn) async {
        await txn.delete('revlog', where: 'deck_id = ?', whereArgs: [deckId]);
        await txn.delete('decks', where: 'id = ?', whereArgs: [deckId]);
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to delete deck: $e'));
    }
  }
}
