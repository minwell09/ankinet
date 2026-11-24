import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/injection_container.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/settings/study_settings.dart';
import '../../../../core/srs/fsrs_scheduler.dart';
import '../../../../core/srs/sm2_scheduler.dart';
import '../../../decks/domain/entities/related_word_suggestion.dart';
import '../../../decks/domain/entities/vocab_card.dart';
import '../../../decks/domain/usecases/manage_cards_and_decks_usecase.dart';
import '../../../decks/presentation/providers/deck_provider.dart';
import '../../domain/usecases/study_session_usecases.dart';

class StudySessionState {
  final bool isLoading;
  final String? errorMessage;
  final List<VocabCard> queue;
  final int currentIndex;
  final bool showAnswer;
  final bool hasRevealed;
  final List<RelatedWordSuggestion> relatedWords;
  final String? snackbarMessage;
  final bool snackbarIsError;
  final int reviewedCount;

  const StudySessionState({
    this.isLoading = true,
    this.errorMessage,
    this.queue = const [],
    this.currentIndex = 0,
    this.showAnswer = false,
    this.hasRevealed = false,
    this.relatedWords = const [],
    this.snackbarMessage,
    this.snackbarIsError = false,
    this.reviewedCount = 0,
  });

  bool get isCompleted => !isLoading && currentIndex >= queue.length;
  VocabCard? get currentCard =>
      currentIndex < queue.length ? queue[currentIndex] : null;

  StudySessionState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<VocabCard>? queue,
    int? currentIndex,
    bool? showAnswer,
    bool? hasRevealed,
    List<RelatedWordSuggestion>? relatedWords,
    String? snackbarMessage,
    bool? snackbarIsError,
    int? reviewedCount,
    bool clearSnackbar = false,
  }) {
    return StudySessionState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      showAnswer: showAnswer ?? this.showAnswer,
      hasRevealed: hasRevealed ?? this.hasRevealed,
      relatedWords: relatedWords ?? this.relatedWords,
      snackbarMessage:
          clearSnackbar ? null : (snackbarMessage ?? this.snackbarMessage),
      snackbarIsError: snackbarIsError ?? this.snackbarIsError,
      reviewedCount: reviewedCount ?? this.reviewedCount,
    );
  }
}

class StudySessionNotifier extends StateNotifier<StudySessionState> {
  final String deckId;
  final GetDueCardsUseCase getDueCardsUseCase;
  final SubmitReviewUseCase submitReviewUseCase;
  final GetRelatedWordsUseCase getRelatedWordsUseCase;
  final UpdateCardUseCase updateCardUseCase;
  final DeleteCardUseCase deleteCardUseCase;
  final TtsCacheService ttsCacheService;

  DateTime _cardShownAt = DateTime.now();

  StudySessionNotifier({
    required this.deckId,
    required this.getDueCardsUseCase,
    required this.submitReviewUseCase,
    required this.getRelatedWordsUseCase,
    required this.updateCardUseCase,
    required this.deleteCardUseCase,
    required this.ttsCacheService,
  }) : super(const StudySessionState()) {
    loadQueue();
  }

  Future<void> loadQueue() async {
    state = state.copyWith(isLoading: true, errorMessage: null, clearSnackbar: true);
    final res = await getDueCardsUseCase(deckId);
    res.fold(
      (failure) => state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      ),
      (cards) {
        _cardShownAt = DateTime.now();
        if (cards.isNotEmpty) {
          ttsCacheService.preloadWords(cards.map((c) => c.word).toList());
        }
        state = state.copyWith(
          isLoading: false,
          queue: List<VocabCard>.from(cards),
          currentIndex: 0,
          showAnswer: false,
          hasRevealed: false,
          relatedWords: const [],
        );
      },
    );
  }

  /// Merges newly created or newly due cards from SQLite into the active study
  /// session queue without losing the user's current card or progress.
  Future<void> refreshQueueForNewCards() async {
    if (state.isLoading) return;
    final res = await getDueCardsUseCase(deckId);
    res.fold(
      (_) {},
      (latestDue) {
        if (latestDue.isEmpty) return;
        final existingIds = state.queue.map((c) => c.id).toSet();
        final newlyAdded =
            latestDue.where((c) => !existingIds.contains(c.id)).toList();
        if (newlyAdded.isEmpty) return;

        final updatedQueue = List<VocabCard>.from(state.queue)
          ..addAll(newlyAdded);
        ttsCacheService.preloadWords(newlyAdded.map((c) => c.word).toList());
        state = state.copyWith(queue: updatedQueue);
      },
    );
  }

  Future<void> revealAnswer(StudySettings settings) async {
    final card = state.currentCard;
    if (card == null) return;
    final firstReveal = !state.hasRevealed;
    state = state.copyWith(
      showAnswer: true,
      hasRevealed: true,
      clearSnackbar: true,
    );

    if (firstReveal) {
      if (settings.autoPlayTts) {
        ttsCacheService.speak(card.word, audioUrl: card.audioUrl);
      }
      final relatedRes = await getRelatedWordsUseCase(card.id);
      relatedRes.fold(
        (_) {},
        (list) => state = state.copyWith(relatedWords: list),
      );
    }
  }

  Future<void> toggleFlip(StudySettings settings) async {
    await setFlipped(!state.showAnswer, settings);
  }

  Future<void> setFlipped(bool flipped, StudySettings settings) async {
    if (flipped) {
      await revealAnswer(settings);
    } else {
      state = state.copyWith(showAnswer: false);
    }
  }

  Future<bool> gradeCurrentCard(
    ReviewGrade grade,
    StudySettings settings,
  ) async {
    final card = state.currentCard;
    if (card == null) return false;

    final elapsedMs =
        DateTime.now().difference(_cardShownAt).inMilliseconds.clamp(0, 120000);
    final res = await submitReviewUseCase(
      card: card,
      grade: grade,
      settings: settings,
      durationMs: elapsedMs,
    );

    return res.fold(
      (failure) {
        state = state.copyWith(
          snackbarMessage: failure.message,
          snackbarIsError: true,
        );
        return false;
      },
      (scheduleOut) {
        String? msg;
        bool isErr = false;
        if (scheduleOut.becameLeech) {
          isErr = true;
          msg = scheduleOut.suspended
              ? 'Thẻ "${card.word}" thành Leech (${scheduleOut.lapses} lần quên) và đã tạm ẩn!'
              : 'Thẻ "${card.word}" được gắn nhãn Leech (${scheduleOut.lapses} lần quên)!';
        }

        final updatedQueue = List<VocabCard>.from(state.queue);
        final minsUntilNext =
            scheduleOut.nextReviewAt.difference(DateTime.now()).inMinutes;
        if (!scheduleOut.suspended &&
            (scheduleOut.state == CardState.learning ||
                scheduleOut.state == CardState.relearning) &&
            minsUntilNext <= 30) {
          updatedQueue.add(
            VocabCard(
              id: card.id,
              deckId: card.deckId,
              word: card.word,
              lemma: card.lemma,
              phonetic: card.phonetic,
              phoneticUs: card.phoneticUs,
              phoneticUk: card.phoneticUk,
              translation: card.translation,
              partOfSpeech: card.partOfSpeech,
              contextSentence: card.contextSentence,
              clozeSentence: card.clozeSentence,
              audioUrl: card.audioUrl,
              state: scheduleOut.state,
              stepIndex: scheduleOut.stepIndex,
              stability: scheduleOut.stability,
              difficulty: scheduleOut.difficulty,
              intervalDays: scheduleOut.intervalDays,
              repetitions: scheduleOut.reps,
              lapses: scheduleOut.lapses,
              easeFactor: card.easeFactor,
              isLeech: card.isLeech || scheduleOut.becameLeech,
              isSuspended: scheduleOut.suspended,
              lastReviewAt: DateTime.now(),
              nextReviewAt: scheduleOut.nextReviewAt,
            ),
          );
        }

        _cardShownAt = DateTime.now();
        state = state.copyWith(
          queue: updatedQueue,
          currentIndex: state.currentIndex + 1,
          showAnswer: false,
          hasRevealed: false,
          relatedWords: const [],
          reviewedCount: state.reviewedCount + 1,
          snackbarMessage: msg,
          snackbarIsError: isErr,
          clearSnackbar: msg == null,
        );
        return true;
      },
    );
  }

  void enqueueRelatedCard(VocabCard relatedCard) {
    final alreadyRemaining = state.queue
        .skip(state.currentIndex + 1)
        .any((c) => c.id == relatedCard.id);
    if (alreadyRemaining) {
      state = state.copyWith(
        snackbarMessage: '"${relatedCard.word}" đã có trong hàng đợi ôn tập.',
        snackbarIsError: false,
      );
      return;
    }
    final updated = List<VocabCard>.from(state.queue)
      ..insert(state.currentIndex + 1, relatedCard);
    ttsCacheService.preloadWords([relatedCard.word]);
    state = state.copyWith(
      queue: updated,
      snackbarMessage: 'Đã xếp "${relatedCard.word}" vào thẻ kế tiếp!',
      snackbarIsError: false,
    );
  }

  void speakWord(String word, {String? audioUrl, String accent = 'en-US'}) {
    ttsCacheService.speak(word, audioUrl: audioUrl ?? '', accent: accent);
  }

  void clearSnackbar() {
    state = state.copyWith(clearSnackbar: true);
  }

  Future<bool> editCurrentCard({
    required String word,
    required String partOfSpeech,
    required String phoneticUs,
    required String phoneticUk,
    required String translation,
    required String contextSentence,
  }) async {
    final card = state.currentCard;
    if (card == null) return false;
    final res = await updateCardUseCase(
      cardId: card.id,
      word: word,
      partOfSpeech: partOfSpeech,
      phoneticUs: phoneticUs,
      phoneticUk: phoneticUk,
      translation: translation,
      contextSentence: contextSentence,
    );
    return res.fold(
      (failure) {
        state = state.copyWith(
          snackbarMessage: 'Lỗi cập nhật thẻ: ${failure.message}',
          snackbarIsError: true,
        );
        return false;
      },
      (updatedCard) {
        final updatedQueue = List<VocabCard>.from(state.queue);
        updatedQueue[state.currentIndex] = updatedCard;
        state = state.copyWith(
          queue: updatedQueue,
          snackbarMessage: 'Đã cập nhật thẻ "${updatedCard.word}"!',
          snackbarIsError: false,
        );
        return true;
      },
    );
  }

  Future<bool> deleteCurrentCard() async {
    final card = state.currentCard;
    if (card == null) return false;
    final res = await deleteCardUseCase(card.id);
    return res.fold(
      (failure) {
        state = state.copyWith(
          snackbarMessage: 'Lỗi xóa thẻ: ${failure.message}',
          snackbarIsError: true,
        );
        return false;
      },
      (_) {
        final updatedQueue = List<VocabCard>.from(state.queue)
          ..removeAt(state.currentIndex);
        _cardShownAt = DateTime.now();
        state = state.copyWith(
          queue: updatedQueue,
          showAnswer: false,
          hasRevealed: false,
          relatedWords: const [],
          snackbarMessage: 'Đã xóa thẻ "${card.word}"!',
          snackbarIsError: false,
        );
        return true;
      },
    );
  }
}

final studySessionProvider = StateNotifierProvider.autoDispose
    .family<StudySessionNotifier, StudySessionState, String>((ref, deckId) {
  final notifier = StudySessionNotifier(
    deckId: deckId,
    getDueCardsUseCase: sl<GetDueCardsUseCase>(),
    submitReviewUseCase: sl<SubmitReviewUseCase>(),
    getRelatedWordsUseCase: sl<GetRelatedWordsUseCase>(),
    updateCardUseCase: sl<UpdateCardUseCase>(),
    deleteCardUseCase: sl<DeleteCardUseCase>(),
    ttsCacheService: sl<TtsCacheService>(),
  );

  // Automatically merge newly saved/imported cards into an open study queue
  ref.listen<int>(cardsRevisionProvider, (_, __) {
    notifier.refreshQueueForNewCards();
  });

  return notifier;
});
