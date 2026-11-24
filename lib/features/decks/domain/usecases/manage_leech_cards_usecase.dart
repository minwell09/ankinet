import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failures.dart';
import '../entities/vocab_card.dart';
import '../repositories/deck_repository.dart';

class GetLeechCardsUseCase {
  final DeckRepository repository;

  const GetLeechCardsUseCase(this.repository);

  Future<Either<Failure, List<VocabCard>>> call({String? deckId}) {
    return repository.getLeechCards(deckId: deckId);
  }
}

class ToggleSuspendCardUseCase {
  final DeckRepository repository;

  const ToggleSuspendCardUseCase(this.repository);

  Future<Either<Failure, void>> call(String cardId, {required bool suspended}) {
    return repository.toggleSuspendCard(cardId, suspended: suspended);
  }
}

class ResetLeechCardUseCase {
  final DeckRepository repository;

  const ResetLeechCardUseCase(this.repository);

  Future<Either<Failure, void>> call(String cardId) {
    return repository.resetLeechCard(cardId);
  }
}
