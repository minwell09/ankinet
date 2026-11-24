import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failures.dart';
import '../entities/deck.dart';
import '../entities/vocab_card.dart';
import '../repositories/deck_repository.dart';

class GetCardsByDeckUseCase {
  final DeckRepository repository;

  const GetCardsByDeckUseCase(this.repository);

  Future<Either<Failure, List<VocabCard>>> call(String deckId) {
    return repository.getCardsByDeck(deckId);
  }
}

class UpdateCardUseCase {
  final DeckRepository repository;

  const UpdateCardUseCase(this.repository);

  Future<Either<Failure, VocabCard>> call({
    required String cardId,
    required String word,
    required String partOfSpeech,
    required String phoneticUs,
    required String phoneticUk,
    required String translation,
    required String contextSentence,
  }) {
    return repository.updateCard(
      cardId: cardId,
      word: word,
      partOfSpeech: partOfSpeech,
      phoneticUs: phoneticUs,
      phoneticUk: phoneticUk,
      translation: translation,
      contextSentence: contextSentence,
    );
  }
}

class DeleteCardUseCase {
  final DeckRepository repository;

  const DeleteCardUseCase(this.repository);

  Future<Either<Failure, void>> call(String cardId) {
    return repository.deleteCard(cardId);
  }
}

class CreateDeckUseCase {
  final DeckRepository repository;

  const CreateDeckUseCase(this.repository);

  Future<Either<Failure, Deck>> call({
    required String name,
    required String description,
  }) {
    return repository.createDeck(name: name, description: description);
  }
}

class UpdateDeckUseCase {
  final DeckRepository repository;

  const UpdateDeckUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String deckId,
    required String name,
    required String description,
  }) {
    return repository.updateDeck(
      deckId: deckId,
      name: name,
      description: description,
    );
  }
}

class DeleteDeckUseCase {
  final DeckRepository repository;

  const DeleteDeckUseCase(this.repository);

  Future<Either<Failure, void>> call(String deckId) {
    return repository.deleteDeck(deckId);
  }
}
