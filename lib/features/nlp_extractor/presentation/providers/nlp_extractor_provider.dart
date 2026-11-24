import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/injection_container.dart';
import '../../../../core/settings/settings_repository.dart';
import '../../data/datasources/nlp_analyzer_datasource.dart';
import '../../domain/entities/extracted_token.dart';
import '../../domain/usecases/analyze_text_usecase.dart';
import '../../domain/usecases/create_cards_from_tokens_usecase.dart';

class NlpExtractorState {
  final LearningLanguageMode mode;
  final String rawText;
  final bool isAnalyzing;
  final bool isSaving;
  final List<ExtractedToken> tokens;
  final Set<String> selectedWords;
  final String? errorMessage;
  final int? lastSavedCount;
  final int? lastElapsedMs;

  const NlpExtractorState({
    this.mode = LearningLanguageMode.englishForVietnamese,
    this.rawText =
        'Engineers inspect the structure and predict how portable transport can transform global export from a new perspective.',
    this.isAnalyzing = false,
    this.isSaving = false,
    this.tokens = const [],
    this.selectedWords = const {},
    this.errorMessage,
    this.lastSavedCount,
    this.lastElapsedMs,
  });

  NlpExtractorState copyWith({
    LearningLanguageMode? mode,
    String? rawText,
    bool? isAnalyzing,
    bool? isSaving,
    List<ExtractedToken>? tokens,
    Set<String>? selectedWords,
    String? errorMessage,
    int? lastSavedCount,
    int? lastElapsedMs,
  }) {
    return NlpExtractorState(
      mode: mode ?? this.mode,
      rawText: rawText ?? this.rawText,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      isSaving: isSaving ?? this.isSaving,
      tokens: tokens ?? this.tokens,
      selectedWords: selectedWords ?? this.selectedWords,
      errorMessage: errorMessage,
      lastSavedCount: lastSavedCount,
      lastElapsedMs: lastElapsedMs ?? this.lastElapsedMs,
    );
  }
}

class NlpExtractorNotifier extends StateNotifier<NlpExtractorState> {
  final AnalyzeTextUseCase analyzeTextUseCase;
  final CreateCardsFromTokensUseCase createCardsUseCase;
  final SettingsRepository settingsRepository;

  NlpExtractorNotifier({
    required this.analyzeTextUseCase,
    required this.createCardsUseCase,
    required this.settingsRepository,
  }) : super(const NlpExtractorState());

  void setLanguageMode(LearningLanguageMode mode) {
    final sampleText = mode == LearningLanguageMode.englishForVietnamese
        ? 'Engineers inspect the structure and predict how portable transport can transform global export from a new perspective.'
        : '森林里非常清澈，我们在树下休息。';
    state = state.copyWith(
      mode: mode,
      rawText: sampleText,
      tokens: const [],
      selectedWords: const {},
    );
  }

  Future<void> analyzeText(String input) async {
    if (input.trim().isEmpty) {
      state = state.copyWith(
        rawText: input,
        isAnalyzing: false,
        tokens: const [],
        selectedWords: const {},
        errorMessage: null,
      );
      return;
    }

    final sw = Stopwatch()..start();
    state = state.copyWith(
      rawText: input,
      isAnalyzing: true,
      errorMessage: null,
      lastSavedCount: null,
    );

    try {
      final settings = await settingsRepository.loadSettings();
      final result = await analyzeTextUseCase(
        input,
        mode: state.mode,
        enableOnlineLookup: settings.enableOnlineLookup,
      );
      sw.stop();

      result.fold(
        (failure) => state = state.copyWith(
          isAnalyzing: false,
          errorMessage: failure.message,
        ),
        (tokens) {
          final preselected = tokens
              .where((t) => !t.isAlreadySaved)
              .map((t) => t.surfaceWord)
              .toSet();
          state = state.copyWith(
            isAnalyzing: false,
            tokens: tokens,
            selectedWords: preselected,
            lastElapsedMs: sw.elapsedMilliseconds,
          );
        },
      );
    } catch (e) {
      sw.stop();
      state = state.copyWith(
        isAnalyzing: false,
        errorMessage: 'Lỗi phân tích văn bản: $e',
      );
    }
  }

  void toggleWordSelection(String surfaceWord) {
    final updated = Set<String>.from(state.selectedWords);
    if (updated.contains(surfaceWord)) {
      updated.remove(surfaceWord);
    } else {
      updated.add(surfaceWord);
    }
    state = state.copyWith(selectedWords: updated);
  }

  void toggleSelectAll() {
    if (state.selectedWords.length == state.tokens.length) {
      state = state.copyWith(selectedWords: const {});
    } else {
      state = state.copyWith(
        selectedWords: state.tokens.map((t) => t.surfaceWord).toSet(),
      );
    }
  }

  Future<void> createSelectedCards({String deckId = 'default_deck'}) async {
    final chosen = state.tokens
        .where((t) => state.selectedWords.contains(t.surfaceWord))
        .toList();
    if (chosen.isEmpty) return;

    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      final result = await createCardsUseCase(
        deckId: deckId,
        selectedTokens: chosen,
      );

      result.fold(
        (failure) => state = state.copyWith(
          isSaving: false,
          errorMessage: failure.message,
        ),
        (savedCount) {
          final savedSet = chosen.map((c) => c.surfaceWord).toSet();
          final updatedTokens = state.tokens.map((t) {
            if (savedSet.contains(t.surfaceWord)) {
              return t.copyWith(isAlreadySaved: true);
            }
            return t;
          }).toList();
          state = state.copyWith(
            isSaving: false,
            tokens: updatedTokens,
            selectedWords: const {},
            lastSavedCount: savedCount,
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Lỗi lưu thẻ: $e',
      );
    }
  }
}

final nlpExtractorNotifierProvider =
    StateNotifierProvider<NlpExtractorNotifier, NlpExtractorState>((ref) {
  return NlpExtractorNotifier(
    analyzeTextUseCase: sl<AnalyzeTextUseCase>(),
    createCardsUseCase: sl<CreateCardsFromTokensUseCase>(),
    settingsRepository: sl<SettingsRepository>(),
  );
});
