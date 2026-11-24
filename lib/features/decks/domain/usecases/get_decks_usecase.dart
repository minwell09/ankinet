import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failures.dart';
import '../entities/deck.dart';
import '../repositories/deck_repository.dart';

class GetDecksUseCase {
  final DeckRepository repository;

  const GetDecksUseCase(this.repository);

  Future<Either<Failure, List<Deck>>> call() => repository.getDecks();
}
