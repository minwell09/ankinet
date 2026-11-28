import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_anki/core/config/app_theme.dart';
import 'package:vocab_anki/core/config/injection_container.dart';
import 'package:vocab_anki/core/database/local_database.dart';
import 'package:vocab_anki/core/services/tts_cache_service.dart';
import 'package:vocab_anki/core/srs/fsrs_scheduler.dart';
import 'package:vocab_anki/features/decks/domain/entities/related_word_suggestion.dart';
import 'package:vocab_anki/features/decks/domain/entities/vocab_card.dart';
import 'package:vocab_anki/features/pronunciation/data/services/pronunciation_assessment_service.dart';
import 'package:vocab_anki/features/study_session/presentation/widgets/tcg_flashcard_face.dart';

void main() {
  setUp(() {
    if (sl.isRegistered<PronunciationAssessmentService>()) {
      sl.unregister<PronunciationAssessmentService>();
    }
    sl.registerSingleton<PronunciationAssessmentService>(
      PronunciationAssessmentService(
        localDatabase: LocalDatabase(overridePath: ':memory:'),
        ttsCacheService: TtsCacheService(),
      ),
    );
  });

  tearDown(() {
    if (sl.isRegistered<PronunciationAssessmentService>()) {
      sl.unregister<PronunciationAssessmentService>();
    }
  });

  final reviewCard = VocabCard(
    id: 'card_inspect',
    deckId: 'default_deck',
    word: 'inspect',
    phonetic: '/ˌɪnˈspɛkt/',
    phoneticUs: '/ˌɪnˈspɛkt/',
    phoneticUk: '/ɪnspˈɛkt/',
    translation: 'kiểm tra, thanh tra',
    partOfSpeech: 'verb',
    contextSentence: 'Engineers inspect the structure before approval.',
    clozeSentence: 'Engineers [...] the structure before approval.',
    state: CardState.review,
    stability: 5.0,
    difficulty: 5.2,
    intervalDays: 5,
    repetitions: 3,
    easeFactor: 2.5,
    nextReviewAt: DateTime(2026, 11, 26),
  );

  test('TcgFlashcardFace.starLevelForCard maps FSRS mastery tiers 1..5', () {
    final newCard = VocabCard(
      id: 'c1',
      deckId: 'd1',
      word: 'new',
      phonetic: '/njuː/',
      translation: 'mới',
      contextSentence: '',
      state: CardState.newCard,
      stability: 0.0,
      repetitions: 0,
      intervalDays: 0,
      easeFactor: 2.5,
      nextReviewAt: DateTime(2026, 11, 26),
    );
    final masteredCard = VocabCard(
      id: 'c2',
      deckId: 'd1',
      word: 'master',
      phonetic: '/ˈmæstɚ/',
      translation: 'bậc thầy',
      contextSentence: '',
      state: CardState.review,
      stability: 35.0,
      repetitions: 9,
      intervalDays: 35,
      easeFactor: 2.5,
      nextReviewAt: DateTime(2026, 12, 26),
    );

    expect(TcgFlashcardFace.starLevelForCard(newCard), 1);
    expect(TcgFlashcardFace.starLevelForCard(reviewCard), 3);
    expect(TcgFlashcardFace.starLevelForCard(masteredCard), 5);
  });

  testWidgets('TcgFlashcardFace renders Front & Back TCG anatomy cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.stardewTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 520,
                child: TcgFlashcardFace(
                  card: reviewCard,
                  isBack: false,
                  cardIndex: 2,
                  totalCards: 7,
                  targetAccent: 'en-US',
                  showClozeContext: true,
                  relatedWords: const [],
                  onSpeakAccent: (_) {},
                  onEnqueueRelated: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('FRONT • CÂU HỎI'), findsOneWidget);
    expect(find.text('VERB'), findsOneWidget);
    expect(find.text('LUYỆN NÓI'), findsOneWidget);
    expect(find.text('[CLOZE]'), findsOneWidget);
    expect(
      find.text('Engineers [...] the structure before approval.'),
      findsOneWidget,
    );
    expect(find.text('STAB / 5.0d   DIFF / 5.2'), findsOneWidget);
    expect(find.text('CARD 3/7'), findsOneWidget);

    // Now render BACK face with related word chips
    final relatedCard = VocabCard(
      id: 'card_perspective',
      deckId: 'default_deck',
      word: 'perspective',
      phonetic: '/pɝˈspɛktɪv/',
      translation: 'quan điểm',
      contextSentence: '',
      intervalDays: 1,
      repetitions: 1,
      easeFactor: 2.5,
      nextReviewAt: DateTime(2026, 11, 26),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.stardewTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 520,
                child: TcgFlashcardFace(
                  card: reviewCard,
                  isBack: true,
                  cardIndex: 2,
                  totalCards: 7,
                  targetAccent: 'en-US',
                  showClozeContext: true,
                  relatedWords: [
                    RelatedWordSuggestion(
                      card: relatedCard,
                      sharedRadicals: const ['-spect-'],
                    ),
                  ],
                  onSpeakAccent: (_) {},
                  onEnqueueRelated: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('BACK • ĐÁP ÁN'), findsOneWidget);
    expect(find.text('kiểm tra, thanh tra'), findsOneWidget);
    expect(find.text('[NGỮ CẢNH]'), findsOneWidget);
    expect(
      find.text('Engineers inspect the structure before approval.'),
      findsOneWidget,
    );
    expect(find.text('perspective (-spect-)'), findsOneWidget);
    expect(find.text('STAB / 5.0d   DIFF / 5.2'), findsOneWidget);
  });
}
