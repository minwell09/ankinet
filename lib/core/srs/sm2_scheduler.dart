/// Review rating buttons inspired by AnkiDroid.
enum ReviewGrade {
  again, // 1: Failed recall, reset repetitions
  hard,  // 2: Difficult recall, small interval multiplier
  good,  // 3: Standard recall, multiply by ease factor
  easy,  // 4: Effortless recall, bonus interval & ease increase
}

/// Output of an SM-2 / Anki scheduling step.
class SrsScheduleResult {
  final int intervalDays;
  final int repetitions;
  final double easeFactor;
  final DateTime nextReviewAt;

  const SrsScheduleResult({
    required this.intervalDays,
    required this.repetitions,
    required this.easeFactor,
    required this.nextReviewAt,
  });
}

/// AnkiDroid-compatible SM-2 Spaced Repetition Scheduler.
class Sm2Scheduler {
  static const double minEaseFactor = 1.3;

  SrsScheduleResult calculateNext({
    required ReviewGrade grade,
    required int currentIntervalDays,
    required int currentRepetitions,
    required double currentEaseFactor,
    DateTime? now,
  }) {
    final reviewTime = now ?? DateTime.now();
    int nextReps = currentRepetitions;
    int nextInterval = currentIntervalDays;
    double nextEase = currentEaseFactor;

    switch (grade) {
      case ReviewGrade.again:
        nextReps = 0;
        nextInterval = 1;
        nextEase = (currentEaseFactor - 0.20).clamp(minEaseFactor, 3.0);
        break;
      case ReviewGrade.hard:
        nextReps = currentRepetitions + 1;
        nextInterval = currentIntervalDays == 0
            ? 1
            : (currentIntervalDays * 1.2).round().clamp(1, 36500);
        nextEase = (currentEaseFactor - 0.15).clamp(minEaseFactor, 3.0);
        break;
      case ReviewGrade.good:
        nextReps = currentRepetitions + 1;
        if (currentRepetitions == 0) {
          nextInterval = 1;
        } else if (currentRepetitions == 1) {
          nextInterval = 6;
        } else {
          nextInterval = (currentIntervalDays * currentEaseFactor).round();
        }
        break;
      case ReviewGrade.easy:
        nextReps = currentRepetitions + 1;
        if (currentRepetitions == 0) {
          nextInterval = 4;
        } else {
          nextInterval =
              (currentIntervalDays * currentEaseFactor * 1.3).round();
        }
        nextEase = (currentEaseFactor + 0.15).clamp(minEaseFactor, 3.0);
        break;
    }

    return SrsScheduleResult(
      intervalDays: nextInterval,
      repetitions: nextReps,
      easeFactor: nextEase,
      nextReviewAt: reviewTime.add(Duration(days: nextInterval)),
    );
  }
}
