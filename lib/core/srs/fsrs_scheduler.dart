import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'sm2_scheduler.dart';

/// Card learning states in FSRS / Anki.
enum CardState {
  newCard(0),
  learning(1),
  review(2),
  relearning(3);

  final int code;
  const CardState(this.code);

  static CardState fromCode(int code) {
    return CardState.values.firstWhere(
      (s) => s.code == code,
      orElse: () => CardState.newCard,
    );
  }
}

/// FSRS-4.5 Schedule calculation output for a single rating.
class FsrsScheduleOutput extends Equatable {
  final CardState state;
  final int stepIndex;
  final double stability;
  final double difficulty;
  final int intervalDays;
  final int reps;
  final int lapses;
  final DateTime nextReviewAt;
  final String intervalLabel;
  final bool becameLeech;
  final bool suspended;

  const FsrsScheduleOutput({
    required this.state,
    required this.stepIndex,
    required this.stability,
    required this.difficulty,
    required this.intervalDays,
    required this.reps,
    required this.lapses,
    required this.nextReviewAt,
    required this.intervalLabel,
    this.becameLeech = false,
    this.suspended = false,
  });

  @override
  List<Object?> get props => [
        state,
        stepIndex,
        stability,
        difficulty,
        intervalDays,
        reps,
        lapses,
        nextReviewAt,
        intervalLabel,
        becameLeech,
        suspended,
      ];
}

/// FSRS-4.5 (Free Spaced Repetition Scheduler) implementation with
/// configurable learning steps, relearning steps, desired retention, and leech detection.
class FsrsScheduler {
  /// Default FSRS-4.5 17 parameters trained on millions of Anki reviews.
  static const List<double> defaultWeights = [
    0.4872, // w0: initial stability (Again)
    1.4003, // w1: initial stability (Hard)
    3.7145, // w2: initial stability (Good)
    13.8206, // w3: initial stability (Easy)
    5.1618, // w4: initial difficulty base
    1.2298, // w5: initial difficulty slope
    0.8975, // w6: difficulty delta
    0.031, // w7: mean reversion weight
    1.6474, // w8: recall stability exponent
    0.1367, // w9: recall stability decay
    1.0461, // w10: recall retrievability factor
    2.1072, // w11: forget stability base
    0.0793, // w12: forget difficulty factor
    0.3246, // w13: forget stability power
    1.587, // w14: forget retrievability factor
    0.2272, // w15: hard penalty
    2.8755, // w16: easy bonus
  ];

  static const double _factor = 19.0 / 81.0;
  static const double _decay = -0.5;

  final List<double> w;

  const FsrsScheduler({this.w = defaultWeights});

  /// Power-law forgetting curve R(t, S) = (1 + FACTOR * t / S)^DECAY.
  /// At t = S, R = 0.90 (90% retrievability).
  double retrievability({
    required double elapsedDays,
    required double stability,
  }) {
    if (stability <= 0 || elapsedDays <= 0) return 1.0;
    return math.pow(1.0 + _factor * (elapsedDays / stability), _decay).toDouble().clamp(0.01, 1.0);
  }

  /// Calculates next interval in days for a target retention R and stability S.
  int nextIntervalDays({
    required double stability,
    required double desiredRetention,
    int maxInterval = 36500,
  }) {
    final r = desiredRetention.clamp(0.70, 0.99);
    final raw = (stability / _factor) * (math.pow(r, 1.0 / _decay) - 1.0);
    return raw.round().clamp(1, maxInterval);
  }

  double _initStability(ReviewGrade grade) {
    final idx = _gradeValue(grade) - 1;
    return math.max(0.1, w[idx]);
  }

  double _initDifficulty(ReviewGrade grade) {
    final g = _gradeValue(grade);
    final d0 = w[4] - w[5] * (g - 3);
    return d0.clamp(1.0, 10.0);
  }

  double _nextDifficulty(double currentD, ReviewGrade grade) {
    final g = _gradeValue(grade);
    final nextD = currentD - w[6] * (g - 3);
    final d0Good = _initDifficulty(ReviewGrade.good);
    final reverted = w[7] * d0Good + (1.0 - w[7]) * nextD;
    return reverted.clamp(1.0, 10.0);
  }

  double _nextRecallStability({
    required double d,
    required double s,
    required double r,
    required ReviewGrade grade,
  }) {
    final hardPenalty = grade == ReviewGrade.hard ? w[15] : 1.0;
    final easyBonus = grade == ReviewGrade.easy ? w[16] : 1.0;
    final increment = math.exp(w[8]) *
        (11.0 - d) *
        math.pow(s, -w[9]) *
        (math.exp((1.0 - r) * w[10]) - 1.0) *
        hardPenalty *
        easyBonus;
    return (s * (1.0 + increment)).clamp(0.1, 36500.0);
  }

  double _nextForgetStability({
    required double d,
    required double s,
    required double r,
  }) {
    final sMin = w[11] *
        math.pow(d, -w[12]) *
        (math.pow(s + 1.0, w[13]) - 1.0) *
        math.exp((1.0 - r) * w[14]);
    return math.min(s, sMin).clamp(0.1, 36500.0);
  }

  int _gradeValue(ReviewGrade grade) {
    switch (grade) {
      case ReviewGrade.again:
        return 1;
      case ReviewGrade.hard:
        return 2;
      case ReviewGrade.good:
        return 3;
      case ReviewGrade.easy:
        return 4;
    }
  }

  /// Preview all 4 rating outcomes for UI buttons (e.g., Again 1m, Hard 6m, Good 10m, Easy 14d).
  Map<ReviewGrade, FsrsScheduleOutput> previewAllGrades({
    required CardState currentState,
    required int currentStepIndex,
    required double currentStability,
    required double currentDifficulty,
    required int currentIntervalDays,
    required int currentReps,
    required int currentLapses,
    DateTime? lastReviewAt,
    DateTime? now,
    double desiredRetention = 0.90,
    List<int> learningStepsMinutes = const [1, 10],
    List<int> relearningStepsMinutes = const [10],
    int leechThreshold = 8,
    bool suspendLeeches = false,
  }) {
    final result = <ReviewGrade, FsrsScheduleOutput>{};
    for (final grade in ReviewGrade.values) {
      result[grade] = schedule(
        grade: grade,
        currentState: currentState,
        currentStepIndex: currentStepIndex,
        currentStability: currentStability,
        currentDifficulty: currentDifficulty,
        currentIntervalDays: currentIntervalDays,
        currentReps: currentReps,
        currentLapses: currentLapses,
        lastReviewAt: lastReviewAt,
        now: now,
        desiredRetention: desiredRetention,
        learningStepsMinutes: learningStepsMinutes,
        relearningStepsMinutes: relearningStepsMinutes,
        leechThreshold: leechThreshold,
        suspendLeeches: suspendLeeches,
      );
    }
    return result;
  }

  /// Computes the next FSRS schedule state given a rating.
  FsrsScheduleOutput schedule({
    required ReviewGrade grade,
    required CardState currentState,
    required int currentStepIndex,
    required double currentStability,
    required double currentDifficulty,
    required int currentIntervalDays,
    required int currentReps,
    required int currentLapses,
    DateTime? lastReviewAt,
    DateTime? now,
    double desiredRetention = 0.90,
    List<int> learningStepsMinutes = const [1, 10],
    List<int> relearningStepsMinutes = const [10],
    int leechThreshold = 8,
    bool suspendLeeches = false,
  }) {
    final reviewTime = now ?? DateTime.now();
    final learnSteps = learningStepsMinutes.isEmpty ? const [1, 10] : learningStepsMinutes;
    final relearnSteps = relearningStepsMinutes.isEmpty ? const [10] : relearningStepsMinutes;

    final elapsedDays = lastReviewAt != null
        ? math.max(0.0, reviewTime.difference(lastReviewAt).inHours / 24.0)
        : currentIntervalDays.toDouble();

    final s0 = currentStability > 0 ? currentStability : _initStability(grade);
    final d0 = currentDifficulty > 0 ? currentDifficulty : _initDifficulty(grade);

    // 1. NEW CARD
    if (currentState == CardState.newCard) {
      final initS = _initStability(grade);
      final initD = _initDifficulty(grade);

      switch (grade) {
        case ReviewGrade.again:
          final mins = learnSteps.first;
          return FsrsScheduleOutput(
            state: CardState.learning,
            stepIndex: 0,
            stability: initS,
            difficulty: initD,
            intervalDays: 0,
            reps: currentReps + 1,
            lapses: currentLapses,
            nextReviewAt: reviewTime.add(Duration(minutes: mins)),
            intervalLabel: _formatMinutes(mins),
          );
        case ReviewGrade.hard:
          final mins = learnSteps.length > 1
              ? ((learnSteps[0] + learnSteps[1]) / 2).round()
              : (learnSteps.first * 1.5).round();
          return FsrsScheduleOutput(
            state: CardState.learning,
            stepIndex: 0,
            stability: initS,
            difficulty: initD,
            intervalDays: 0,
            reps: currentReps + 1,
            lapses: currentLapses,
            nextReviewAt: reviewTime.add(Duration(minutes: mins)),
            intervalLabel: _formatMinutes(mins),
          );
        case ReviewGrade.good:
          if (learnSteps.length > 1) {
            final mins = learnSteps[1];
            return FsrsScheduleOutput(
              state: CardState.learning,
              stepIndex: 1,
              stability: initS,
              difficulty: initD,
              intervalDays: 0,
              reps: currentReps + 1,
              lapses: currentLapses,
              nextReviewAt: reviewTime.add(Duration(minutes: mins)),
              intervalLabel: _formatMinutes(mins),
            );
          } else {
            final ivl = nextIntervalDays(
              stability: initS,
              desiredRetention: desiredRetention,
            );
            return FsrsScheduleOutput(
              state: CardState.review,
              stepIndex: 0,
              stability: initS,
              difficulty: initD,
              intervalDays: ivl,
              reps: currentReps + 1,
              lapses: currentLapses,
              nextReviewAt: reviewTime.add(Duration(days: ivl)),
              intervalLabel: _formatDays(ivl),
            );
          }
        case ReviewGrade.easy:
          final ivl = math.max(
            4,
            nextIntervalDays(
              stability: initS,
              desiredRetention: desiredRetention,
            ),
          );
          return FsrsScheduleOutput(
            state: CardState.review,
            stepIndex: 0,
            stability: initS,
            difficulty: initD,
            intervalDays: ivl,
            reps: currentReps + 1,
            lapses: currentLapses,
            nextReviewAt: reviewTime.add(Duration(days: ivl)),
            intervalLabel: _formatDays(ivl),
          );
      }
    }

    // 2. LEARNING OR RELEARNING CARD
    if (currentState == CardState.learning ||
        currentState == CardState.relearning) {
      final isLearning = currentState == CardState.learning;
      final steps = isLearning ? learnSteps : relearnSteps;
      final nextD = _nextDifficulty(d0, grade);
      final r = retrievability(elapsedDays: elapsedDays, stability: s0);

      switch (grade) {
        case ReviewGrade.again:
          final mins = steps.first;
          final forgetS = isLearning
              ? _initStability(ReviewGrade.again)
              : _nextForgetStability(d: nextD, s: s0, r: r);
          return FsrsScheduleOutput(
            state: currentState,
            stepIndex: 0,
            stability: forgetS,
            difficulty: nextD,
            intervalDays: 0,
            reps: currentReps + 1,
            lapses: currentLapses,
            nextReviewAt: reviewTime.add(Duration(minutes: mins)),
            intervalLabel: _formatMinutes(mins),
          );
        case ReviewGrade.hard:
          final idx = currentStepIndex.clamp(0, steps.length - 1);
          final mins = (steps[idx] * 1.3).round().clamp(1, 1440);
          return FsrsScheduleOutput(
            state: currentState,
            stepIndex: idx,
            stability: s0,
            difficulty: nextD,
            intervalDays: 0,
            reps: currentReps + 1,
            lapses: currentLapses,
            nextReviewAt: reviewTime.add(Duration(minutes: mins)),
            intervalLabel: _formatMinutes(mins),
          );
        case ReviewGrade.good:
          final nextStep = currentStepIndex + 1;
          if (nextStep < steps.length) {
            final mins = steps[nextStep];
            return FsrsScheduleOutput(
              state: currentState,
              stepIndex: nextStep,
              stability: s0,
              difficulty: nextD,
              intervalDays: 0,
              reps: currentReps + 1,
              lapses: currentLapses,
              nextReviewAt: reviewTime.add(Duration(minutes: mins)),
              intervalLabel: _formatMinutes(mins),
            );
          } else {
            final gradS = isLearning && currentStability <= w[1]
                ? _initStability(ReviewGrade.good)
                : _nextRecallStability(
                    d: nextD,
                    s: s0,
                    r: r,
                    grade: ReviewGrade.good,
                  );
            final ivl = nextIntervalDays(
              stability: gradS,
              desiredRetention: desiredRetention,
            );
            return FsrsScheduleOutput(
              state: CardState.review,
              stepIndex: 0,
              stability: gradS,
              difficulty: nextD,
              intervalDays: ivl,
              reps: currentReps + 1,
              lapses: currentLapses,
              nextReviewAt: reviewTime.add(Duration(days: ivl)),
              intervalLabel: _formatDays(ivl),
            );
          }
        case ReviewGrade.easy:
          final easyS = isLearning
              ? _initStability(ReviewGrade.easy)
              : _nextRecallStability(
                  d: nextD,
                  s: s0,
                  r: r,
                  grade: ReviewGrade.easy,
                );
          final ivl = math.max(
            4,
            nextIntervalDays(
              stability: easyS,
              desiredRetention: desiredRetention,
            ),
          );
          return FsrsScheduleOutput(
            state: CardState.review,
            stepIndex: 0,
            stability: easyS,
            difficulty: nextD,
            intervalDays: ivl,
            reps: currentReps + 1,
            lapses: currentLapses,
            nextReviewAt: reviewTime.add(Duration(days: ivl)),
            intervalLabel: _formatDays(ivl),
          );
      }
    }

    // 3. REVIEW CARD
    final r = retrievability(
      elapsedDays: math.max(1.0, elapsedDays),
      stability: s0,
    );
    final nextD = _nextDifficulty(d0, grade);

    if (grade == ReviewGrade.again) {
      final forgetS = _nextForgetStability(d: nextD, s: s0, r: r);
      final newLapses = currentLapses + 1;
      final isLeech = newLapses >= leechThreshold;
      final mins = relearnSteps.first;
      return FsrsScheduleOutput(
        state: CardState.relearning,
        stepIndex: 0,
        stability: forgetS,
        difficulty: nextD,
        intervalDays: 0,
        reps: currentReps + 1,
        lapses: newLapses,
        nextReviewAt: reviewTime.add(Duration(minutes: mins)),
        intervalLabel: _formatMinutes(mins),
        becameLeech: isLeech,
        suspended: isLeech && suspendLeeches,
      );
    }

    // Enforce strict ordering: Hard <= Good < Easy
    final sHard = _nextRecallStability(
      d: _nextDifficulty(d0, ReviewGrade.hard),
      s: s0,
      r: r,
      grade: ReviewGrade.hard,
    );
    final sGood = _nextRecallStability(
      d: _nextDifficulty(d0, ReviewGrade.good),
      s: s0,
      r: r,
      grade: ReviewGrade.good,
    );
    final sEasy = _nextRecallStability(
      d: _nextDifficulty(d0, ReviewGrade.easy),
      s: s0,
      r: r,
      grade: ReviewGrade.easy,
    );

    final ivlHard = nextIntervalDays(
      stability: sHard,
      desiredRetention: desiredRetention,
    );
    final ivlGood = math.max(
      ivlHard + 1,
      nextIntervalDays(
        stability: sGood,
        desiredRetention: desiredRetention,
      ),
    );
    final ivlEasy = math.max(
      ivlGood + 1,
      nextIntervalDays(
        stability: sEasy,
        desiredRetention: desiredRetention,
      ),
    );

    late final double chosenS;
    late final int chosenIvl;
    switch (grade) {
      case ReviewGrade.hard:
        chosenS = sHard;
        chosenIvl = ivlHard;
        break;
      case ReviewGrade.good:
        chosenS = sGood;
        chosenIvl = ivlGood;
        break;
      case ReviewGrade.easy:
        chosenS = sEasy;
        chosenIvl = ivlEasy;
        break;
      case ReviewGrade.again:
        chosenS = sHard;
        chosenIvl = 1;
        break;
    }

    return FsrsScheduleOutput(
      state: CardState.review,
      stepIndex: 0,
      stability: chosenS,
      difficulty: nextD,
      intervalDays: chosenIvl,
      reps: currentReps + 1,
      lapses: currentLapses,
      nextReviewAt: reviewTime.add(Duration(days: chosenIvl)),
      intervalLabel: _formatDays(chosenIvl),
    );
  }

  static String _formatMinutes(int mins) {
    if (mins < 60) return '${mins}m';
    final hours = (mins / 60).round();
    return '${hours}h';
  }

  static String _formatDays(int days) {
    if (days < 30) return '${days}d';
    if (days < 365) {
      final months = (days / 30.0).toStringAsFixed(1);
      return '${months.endsWith('.0') ? months.substring(0, months.length - 2) : months}mo';
    }
    final years = (days / 365.0).toStringAsFixed(1);
    return '${years}y';
  }
}
