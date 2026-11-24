import 'package:fpdart/fpdart.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/local_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/cloze_masker.dart';
import '../../domain/entities/extracted_token.dart';
import '../../domain/repositories/nlp_extractor_repository.dart';
import '../datasources/nlp_analyzer_datasource.dart';

class NlpExtractorRepositoryImpl implements NlpExtractorRepository {
  final NlpAnalyzerDataSource analyzerDataSource;
  final LocalDatabase localDatabase;

  const NlpExtractorRepositoryImpl({
    required this.analyzerDataSource,
    required this.localDatabase,
  });

  @override
  Future<Either<Failure, List<ExtractedToken>>> analyzeText(
    String rawText, {
    LearningLanguageMode mode = LearningLanguageMode.englishForVietnamese,
    bool enableOnlineLookup = true,
  }) async {
    try {
      final db = await localDatabase.database;
      final models = await analyzerDataSource.tokenizeAndAnalyze(
        rawText,
        mode: mode,
        enableOnlineLookup: enableOnlineLookup,
      );

      if (models.isEmpty) return const Right([]);

      // Check only the extracted words against existing cards using indexed WHERE IN
      final words = models.map((m) => m.surfaceWord).toList();
      final placeholders = List.filled(words.length, '?').join(',');
      final existingRows = await db.query(
        'cards',
        columns: ['word'],
        where: 'word IN ($placeholders)',
        whereArgs: words,
      );
      final existingWords =
          existingRows.map((r) => r['word'] as String).toSet();

      final enriched = models
          .map(
            (m) => ExtractedToken(
              surfaceWord: m.surfaceWord,
              lemma: m.lemma,
              phonetic: m.phonetic,
              phoneticUs: m.phoneticUs,
              phoneticUk: m.phoneticUk,
              translation: m.translation,
              partOfSpeech: m.partOfSpeech,
              sourceSentence: m.sourceSentence,
              clozeSentence: m.clozeSentence,
              audioUrl: m.audioUrl,
              radicals: m.radicals,
              isAlreadySaved: existingWords.contains(m.surfaceWord),
              isFromOfflineBundle: m.isFromOfflineBundle,
            ),
          )
          .toList();

      return Right(enriched);
    } catch (e) {
      return Left(NlpAnalysisFailure('Failed to analyze text: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> createCardsAndGraphNodes({
    required String deckId,
    required List<ExtractedToken> selectedTokens,
  }) async {
    try {
      if (selectedTokens.isEmpty) return const Right(0);
      final db = await localDatabase.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Batch all inserts inside a single transaction for maximum throughput
      await db.transaction((txn) async {
        // Ensure target deck exists to prevent FOREIGN KEY constraint failed (code 787)
        String effectiveDeckId = deckId;
        final targetDeck = await txn.query(
          'decks',
          columns: const ['id'],
          where: 'id = ?',
          whereArgs: [effectiveDeckId],
          limit: 1,
        );
        if (targetDeck.isEmpty) {
          final anyDeck = await txn.query(
            'decks',
            columns: const ['id'],
            orderBy: 'created_at ASC',
            limit: 1,
          );
          if (anyDeck.isNotEmpty) {
            effectiveDeckId = anyDeck.first['id'] as String;
          } else {
            effectiveDeckId = 'default_deck';
            await txn.insert(
              'decks',
              {
                'id': effectiveDeckId,
                'name': 'Core Vocabulary (EN ➔ VI)',
                'description': 'Bộ thẻ mặc định tạo tự động từ Tách từ NLP',
                'created_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }

        final batch = txn.batch();

        for (final token in selectedTokens) {
          final cleanWord = token.surfaceWord.trim().toLowerCase();
          final cardId = 'card_$cleanWord';
          final cloze = (token.clozeSentence.isNotEmpty &&
                  !ClozeMasker.containsUnmaskedSurfaceForm(
                    clozeSentence: token.clozeSentence,
                    word: cleanWord,
                    lemma: token.lemma,
                  ))
              ? token.clozeSentence
              : ClozeMasker.maskSentence(
                  sentence: token.sourceSentence,
                  word: cleanWord,
                  lemma: token.lemma,
                );

          // Insert new card or ignore if already present (preserves FSRS progress!),
          // then update context sentence & translation if needed.
          batch.insert(
            'cards',
            {
              'id': cardId,
              'deck_id': effectiveDeckId,
              'word': cleanWord,
              'lemma': token.lemma.isNotEmpty ? token.lemma : cleanWord,
              'phonetic': token.phonetic,
              'phonetic_us': token.effectivePhoneticUs,
              'phonetic_uk': token.phoneticUk,
              'translation': token.translation,
              'part_of_speech': token.partOfSpeech,
              'context_sentence': token.sourceSentence,
              'cloze_sentence': cloze,
              'audio_url': token.audioUrl,
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
              'next_review_at': now - 1000,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          for (final radical in token.radicals) {
            final radicalId = 'rad_${radical.symbol}';
            batch.insert(
              'radicals',
              {
                'id': radicalId,
                'symbol': radical.symbol,
                'meaning': radical.meaning,
                'stroke_count': radical.strokeCount,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            batch.insert(
              'card_radical_edges',
              {
                'card_id': cardId,
                'radical_id': radicalId,
                'decomposition_role': 'structural_radical',
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }

        await batch.commit(noResult: true);
      });

      return Right(selectedTokens.length);
    } catch (e) {
      return Left(DatabaseFailure('Failed to batch-create cards & graph: $e'));
    }
  }
}
