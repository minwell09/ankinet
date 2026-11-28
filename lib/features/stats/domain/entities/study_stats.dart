import 'package:equatable/equatable.dart';

import '../../../pronunciation/domain/entities/pronunciation_result.dart';

class StudyStats extends Equatable {
  final int totalCards;
  final int newCardsCount;
  final int learningCardsCount;
  final int reviewCardsCount;
  final int leechCardsCount;
  final int reviewsToday;
  final int totalReviews30d;
  final double trueRetention30d; // 0.0 - 1.0
  final double averageRetrievability; // 0.0 - 1.0
  final int currentStreakDays;
  final Map<String, int> dailyReviewCounts; // YYYY-MM-DD -> count (last 180 days)
  final Map<int, int> upcomingDueByDayOffset; // 0..13 -> due count
  final double? averagePronunciationScore; // 0.0 - 100.0 (null if never assessed)
  final int totalPronunciationAttempts;
  final List<WeakPhonemeStat> weakPhonemes;

  const StudyStats({
    required this.totalCards,
    required this.newCardsCount,
    required this.learningCardsCount,
    required this.reviewCardsCount,
    required this.leechCardsCount,
    required this.reviewsToday,
    required this.totalReviews30d,
    required this.trueRetention30d,
    required this.averageRetrievability,
    required this.currentStreakDays,
    required this.dailyReviewCounts,
    required this.upcomingDueByDayOffset,
    this.averagePronunciationScore,
    this.totalPronunciationAttempts = 0,
    this.weakPhonemes = const [],
  });

  @override
  List<Object?> get props => [
        totalCards,
        newCardsCount,
        learningCardsCount,
        reviewCardsCount,
        leechCardsCount,
        reviewsToday,
        totalReviews30d,
        trueRetention30d,
        averageRetrievability,
        currentStreakDays,
        dailyReviewCounts,
        upcomingDueByDayOffset,
        averagePronunciationScore,
        totalPronunciationAttempts,
        weakPhonemes,
      ];
}
