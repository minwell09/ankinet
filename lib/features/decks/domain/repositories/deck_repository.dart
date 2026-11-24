import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/settings/study_settings.dart';
import '../../../../core/srs/fsrs_scheduler.dart';
import '../../../../core/srs/sm2_scheduler.dart';
import '../entities/deck.dart';
import '../entities/related_word_suggestion.dart';
import '../entities/vocab_card.dart';

abstract class DeckRepository {
  Future<Either<Failure, List<Deck>>> getDecks();
  Future<Either<Failure, List<VocabCard>>> getDueCards(
    String deckId, {
    StudySettings? settings,
    bool ignoreDailyNewLimit = false,
  });
  Future<Either<Failure, FsrsScheduleOutput>> submitReview({
    required VocabCard card,
    required ReviewGrade grade,
    StudySettings? settings,
    int durationMs = 0,
  });
  Future<Either<Failure, List<RelatedWordSuggestion>>> getRelatedWordsByRadicals(
    String cardId, {
    int limit = 6,
  });
  Future<Either<Failure, List<VocabCard>>> getLeechCards({String? deckId});
  Future<Either<Failure, void>> toggleSuspendCard(
    String cardId, {
    required bool suspended,
  });
  Future<Either<Failure, void>> resetLeechCard(String cardId);

  Future<Either<Failure, List<VocabCard>>> getCardsByDeck(String deckId);
  Future<Either<Failure, VocabCard>> updateCard({
    required String cardId,
    required String word,
    required String partOfSpeech,
    required String phoneticUs,
    required String phoneticUk,
    required String translation,
    required String contextSentence,
  });
  Future<Either<Failure, void>> deleteCard(String cardId);

  Future<Either<Failure, Deck>> createDeck({
    required String name,
    required String description,
  });
  Future<Either<Failure, void>> updateDeck({
    required String deckId,
    required String name,
    required String description,
  });
  Future<Either<Failure, void>> deleteDeck(String deckId);
}
