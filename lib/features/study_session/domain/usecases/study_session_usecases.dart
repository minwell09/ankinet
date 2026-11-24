import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/settings/study_settings.dart';
import '../../../../core/srs/fsrs_scheduler.dart';
import '../../../../core/srs/sm2_scheduler.dart';
import '../../../decks/domain/entities/related_word_suggestion.dart';
import '../../../decks/domain/entities/vocab_card.dart';
import '../../../decks/domain/repositories/deck_repository.dart';

class GetDueCardsUseCase {
  final DeckRepository repository;

  const GetDueCardsUseCase(this.repository);

  Future<Either<Failure, List<VocabCard>>> call(
    String deckId, {
    StudySettings? settings,
  }) {
    return repository.getDueCards(deckId, settings: settings);
  }
}

class SubmitReviewUseCase {
  final DeckRepository repository;

  const SubmitReviewUseCase(this.repository);

  Future<Either<Failure, FsrsScheduleOutput>> call({
    required VocabCard card,
    required ReviewGrade grade,
    StudySettings? settings,
    int durationMs = 0,
  }) {
    return repository.submitReview(
      card: card,
      grade: grade,
      settings: settings,
      durationMs: durationMs,
    );
  }
}

class GetRelatedWordsUseCase {
  final DeckRepository repository;

  const GetRelatedWordsUseCase(this.repository);

  Future<Either<Failure, List<RelatedWordSuggestion>>> call(
    String cardId, {
    int limit = 6,
  }) {
    return repository.getRelatedWordsByRadicals(cardId, limit: limit);
  }
}
