import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_anki/core/config/app_theme.dart';
import 'package:vocab_anki/core/config/injection_container.dart';
import 'package:vocab_anki/core/database/local_database.dart';
import 'package:vocab_anki/core/services/tts_cache_service.dart';
import 'package:vocab_anki/core/settings/study_settings.dart';
import 'package:vocab_anki/features/decks/domain/entities/vocab_card.dart';
import 'package:vocab_anki/features/pronunciation/data/services/pronunciation_assessment_service.dart';
import 'package:vocab_anki/features/pronunciation/domain/entities/pronunciation_result.dart';
import 'package:vocab_anki/features/pronunciation/presentation/widgets/flashcard_pronunciation_bar.dart';
import 'package:vocab_anki/features/pronunciation/presentation/widgets/pixel_volume_meter.dart';
import 'package:vocab_anki/features/pronunciation/presentation/widgets/pronunciation_breakdown_dialog.dart';
import 'package:vocab_anki/features/stats/domain/entities/study_stats.dart';
import 'package:vocab_anki/features/stats/presentation/pages/stats_page.dart';
import 'package:vocab_anki/features/stats/presentation/providers/stats_provider.dart';

class _FakePronunciationService extends PronunciationAssessmentService {
  _FakePronunciationService()
      : super(
          localDatabase: LocalDatabase(overridePath: ':memory:'),
          ttsCacheService: TtsCacheService(),
        );

  @override
  Future<PronunciationResult> stopAndAssess({
    required String cardId,
    required String word,
    required String targetIpa,
    required String contextSentence,
    required String accent,
    required PronunciationPracticeMode mode,
  }) async {
    stopMeterOnly();
    return PronunciationResult(
      cardId: cardId,
      word: word,
      contextSentence: contextSentence,
      targetIpa: targetIpa,
      accent: accent,
      mode: mode,
      overallScore: 74,
      rank: 'B',
      diagnosticTip: 'Thiếu âm bật /t/ ở cuối từ',
      phonemes: const [
        PhonemeScore(targetIpa: '/', detectedIpa: '/', score: 100, isDelimiter: true),
        PhonemeScore(targetIpa: 'ɪ', detectedIpa: 'ɪ', score: 92),
        PhonemeScore(targetIpa: 'n', detectedIpa: 'n', score: 90),
        PhonemeScore(targetIpa: 's', detectedIpa: 's', score: 85),
        PhonemeScore(targetIpa: 'p', detectedIpa: 'p', score: 78),
        PhonemeScore(targetIpa: 'ɛ', detectedIpa: 'ɛ', score: 72),
        PhonemeScore(targetIpa: 'k', detectedIpa: 'k', score: 66),
        PhonemeScore(targetIpa: 't', detectedIpa: '∅', score: 35),
        PhonemeScore(targetIpa: '/', detectedIpa: '/', score: 100, isDelimiter: true),
      ],
      wordScores: const [
        WordPronunciationScore(word: 'Engineers', score: 88),
        WordPronunciationScore(word: 'inspect', score: 74),
        WordPronunciationScore(word: 'the', score: 95),
        WordPronunciationScore(word: 'structure.', score: 58),
      ],
      recordedDurationMs: 900,
      assessedAt: DateTime(2026, 11, 25),
    );
  }

  @override
  Future<void> playReference({
    required String text,
    String audioUrl = '',
    required String accent,
  }) async {}
}

void main() {
  group('Pronunciation domain & tokenizer', () {
    test('IpaTokenizer preserves multi-character phonemes and delimiters', () {
      final tokens = IpaTokenizer.tokenize('/ˈstɹəktʃɝ/');
      final symbols = tokens.map((t) => t.symbol).toList();
      expect(symbols, contains('tʃ'));
      expect(tokens.first.isDelimiter, isTrue);
      expect(tokens.last.isDelimiter, isTrue);
    });

    test('PronunciationColors and rankForScore match spec thresholds', () {
      expect(PronunciationColors.forScore(92), PronunciationColors.accurate);
      expect(PronunciationColors.forScore(74), PronunciationColors.close);
      expect(PronunciationColors.forScore(45), PronunciationColors.missed);
      expect(PronunciationResult.rankForScore(92), 'S');
      expect(PronunciationResult.rankForScore(84), 'A');
      expect(PronunciationResult.rankForScore(74), 'B');
      expect(PronunciationResult.rankForScore(45), 'C');
    });

    test('StudySettings targetAccent round-trips through toMap/fromMap', () {
      const settings = StudySettings(targetAccent: 'en-GB');
      final restored = StudySettings.fromMap(settings.toMap());
      expect(restored.targetAccent, 'en-GB');

      final defaultRestored = StudySettings.fromMap(const {});
      expect(defaultRestored.targetAccent, 'en-US');
    });
  });

  group('Pronunciation UI widgets', () {
    setUp(() {
      if (sl.isRegistered<PronunciationAssessmentService>()) {
        sl.unregister<PronunciationAssessmentService>();
      }
      sl.registerSingleton<PronunciationAssessmentService>(
        _FakePronunciationService(),
      );
    });

    tearDown(() {
      if (sl.isRegistered<PronunciationAssessmentService>()) {
        sl.unregister<PronunciationAssessmentService>();
      }
    });

    final sampleCard = VocabCard(
      id: 'card_inspect',
      deckId: 'default_deck',
      word: 'inspect',
      phonetic: '/ˌɪnˈspɛkt/',
      phoneticUs: '/ˌɪnˈspɛkt/',
      phoneticUk: '/ɪnspˈɛkt/',
      translation: 'kiểm tra, thanh tra',
      contextSentence: 'Engineers inspect the structure.',
      intervalDays: 1,
      repetitions: 1,
      easeFactor: 2.5,
      nextReviewAt: DateTime(2026, 11, 26),
    );

    testWidgets(
      'FlashcardPronunciationBar toggles recording, scores, and opens breakdown dialog',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.stardewTheme,
              home: Scaffold(
                body: Center(
                  child: FlashcardPronunciationBar(
                    card: sampleCard,
                    targetAccent: 'en-US',
                    onSpeakAccent: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('US /ˌɪnˈspɛkt/'), findsOneWidget);
        expect(find.text('UK /ɪnspˈɛkt/'), findsOneWidget);
        expect(find.text('LUYỆN NÓI'), findsOneWidget);

        // Start recording
        await tester.tap(find.text('LUYỆN NÓI'));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('DỪNG GHI'), findsOneWidget);
        expect(find.byType(PixelVolumeMeter), findsOneWidget);

        // Stop recording -> score
        await tester.tap(find.text('DỪNG GHI'));
        await tester.pumpAndSettle();

        expect(find.text('74% • B'), findsOneWidget);
        expect(
          find.textContaining('Thiếu âm bật /t/ ở cuối từ'),
          findsOneWidget,
        );

        // Tap score badge -> opens Parchment RPG Breakdown Modal
        await tester.tap(find.text('74% • B'));
        await tester.pumpAndSettle();

        expect(find.byType(PronunciationBreakdownDialog), findsOneWidget);
        expect(find.text('74% CHÍNH XÁC'), findsOneWidget);
        expect(find.text('Nghe Mẫu'), findsOneWidget);
        expect(find.text('Giọng Của Bạn'), findsOneWidget);
        expect(find.text('TỪ ĐƠN'), findsOneWidget);
        expect(find.text('CẢ CÂU (SHADOWING)'), findsOneWidget);

        // Toggle Full-Sentence shadowing mode
        await tester.tap(find.text('CẢ CÂU (SHADOWING)'));
        await tester.pumpAndSettle();

        expect(find.text('SHADOWING CẢ CÂU (CHẤM ĐIỂM TỪNG TỪ)'), findsOneWidget);
        expect(find.text('Engineers'), findsOneWidget);
        expect(find.text('structure.'), findsOneWidget);
      },
    );

    testWidgets(
      'StatsPage displays ĐIỂM PHÁT ÂM TB card and Top Weak Phonemes section',
      (tester) async {
        const fakeStats = StudyStats(
          totalCards: 20,
          newCardsCount: 5,
          learningCardsCount: 3,
          reviewCardsCount: 12,
          leechCardsCount: 0,
          reviewsToday: 8,
          totalReviews30d: 120,
          trueRetention30d: 0.91,
          averageRetrievability: 0.88,
          currentStreakDays: 5,
          dailyReviewCounts: {},
          upcomingDueByDayOffset: {},
          averagePronunciationScore: 86.0,
          totalPronunciationAttempts: 14,
          weakPhonemes: [
            WeakPhonemeStat(
              phoneme: 'θ',
              averageScore: 52.0,
              attempts: 6,
              missCount: 4,
              tip: 'Âm /θ/ bị đọc giống /s/ — đặt nhẹ đầu lưỡi giữa hai hàm răng',
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              studyStatsProvider.overrideWith((ref) async => fakeStats),
            ],
            child: MaterialApp(
              theme: AppTheme.stardewTheme,
              home: const StatsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('VƯỜN ÔN TẬP (20 TUẦN)'), findsOneWidget);
        expect(find.text('PHÁT ÂM & ÂM CẦN LUYỆN'), findsOneWidget);
        expect(find.text('86% • A'), findsOneWidget);
        expect(find.text('/θ/'), findsOneWidget);
      },
    );
  });
}
