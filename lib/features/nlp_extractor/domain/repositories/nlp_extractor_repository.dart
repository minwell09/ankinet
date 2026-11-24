import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failures.dart';
import '../../data/datasources/nlp_analyzer_datasource.dart';
import '../entities/extracted_token.dart';

abstract class NlpExtractorRepository {
  /// Tokenizes raw input text, transcribes phonetics (IPA/Pinyin/Furigana),
  /// translates meaning, and decomposes words into structural radicals.
  Future<Either<Failure, List<ExtractedToken>>> analyzeText(
    String rawText, {
    LearningLanguageMode mode = LearningLanguageMode.englishForVietnamese,
    bool enableOnlineLookup = true,
    String? deckId,
  });

  /// Saves user-selected tokens as Anki flashcards AND creates nodes/edges
  /// in the Radical Knowledge Graph using a single SQLite batch transaction.
  Future<Either<Failure, int>> createCardsAndGraphNodes({
    required String deckId,
    required List<ExtractedToken> selectedTokens,
  });
}
