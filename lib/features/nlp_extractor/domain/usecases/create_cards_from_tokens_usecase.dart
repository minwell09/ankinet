import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failures.dart';
import '../entities/extracted_token.dart';
import '../repositories/nlp_extractor_repository.dart';

class CreateCardsFromTokensUseCase {
  final NlpExtractorRepository repository;

  const CreateCardsFromTokensUseCase(this.repository);

  Future<Either<Failure, int>> call({
    required String deckId,
    required List<ExtractedToken> selectedTokens,
  }) {
    return repository.createCardsAndGraphNodes(
      deckId: deckId,
      selectedTokens: selectedTokens,
    );
  }
}
