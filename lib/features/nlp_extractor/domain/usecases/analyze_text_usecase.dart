import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failures.dart';
import '../../data/datasources/nlp_analyzer_datasource.dart';
import '../entities/extracted_token.dart';
import '../repositories/nlp_extractor_repository.dart';

class AnalyzeTextUseCase {
  final NlpExtractorRepository repository;

  const AnalyzeTextUseCase(this.repository);

  Future<Either<Failure, List<ExtractedToken>>> call(
    String rawText, {
    LearningLanguageMode mode = LearningLanguageMode.englishForVietnamese,
    bool enableOnlineLookup = true,
    String? deckId,
  }) {
    if (rawText.trim().isEmpty) {
      return Future.value(const Right([]));
    }
    return repository.analyzeText(
      rawText,
      mode: mode,
      enableOnlineLookup: enableOnlineLookup,
      deckId: deckId,
    );
  }
}
