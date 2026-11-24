import 'package:equatable/equatable.dart';

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
      ];
}
