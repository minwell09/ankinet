import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'fsrs_scheduler.dart';

class FsrsOptimizationResult {
  final int totalReviews;
  final int usableTransitions;
  final double initialLogLoss;
  final double optimizedLogLoss;
  final List<double> optimizedWeights;
  final bool metRecommendedThreshold;

  const FsrsOptimizationResult({
    required this.totalReviews,
    required this.usableTransitions,
    required this.initialLogLoss,
    required this.optimizedLogLoss,
    required this.optimizedWeights,
    required this.metRecommendedThreshold,
  });

  double get improvementPercent {
    if (initialLogLoss <= 0) return 0.0;
    return ((initialLogLoss - optimizedLogLoss) / initialLogLoss * 100.0)
        .clamp(0.0, 99.9);
  }
}

class _OptimizeIsolatePayload {
  final List<Map<String, Object?>> revlogRows;
  final List<double> initialWeights;

  const _OptimizeIsolatePayload({
    required this.revlogRows,
    required this.initialWeights,
  });
}

class _ReviewEvent {
  final int grade; // 1=Again, 2=Hard, 3=Good, 4=Easy
  final int reviewedAtMs;

  const _ReviewEvent({
    required this.grade,
    required this.reviewedAtMs,
  });
}

/// Optimizes the 17 parameters of FSRS-4.5 (`w[0..16]`) directly from the user's
/// personal `revlog` review history using L2-regularized Binary Cross-Entropy
/// (Log-Loss) minimization in a background isolate (`compute()`).
class FsrsWeightOptimizer {
  /// Recommended minimum number of review logs in `revlog` for reliable
  /// personal FSRS weight optimization.
  static const int recommendedMinReviews = 1000;

  static const List<double> _minBounds = [
    0.05, // w0
    0.20, // w1
    0.60, // w2
    2.00, // w3
    1.00, // w4
    0.10, // w5
    0.10, // w6
    0.00, // w7
    0.50, // w8
    0.02, // w9
    0.20, // w10
    0.50, // w11
    0.01, // w12
    0.05, // w13
    0.30, // w14
    0.05, // w15
    1.10, // w16
  ];

  static const List<double> _maxBounds = [
    3.00, // w0
    8.00, // w1
    20.00, // w2
    60.00, // w3
    9.50, // w4
    4.00, // w5
    3.50, // w6
    0.75, // w7
    3.50, // w8
    0.80, // w9
    2.50, // w10
    5.00, // w11
    0.50, // w12
    0.90, // w13
    3.50, // w14
    0.95, // w15
    6.00, // w16
  ];

  /// Runs the 17-weight optimization in a background isolate via [compute].
  Future<FsrsOptimizationResult> optimizeFromRevlog(
    List<Map<String, Object?>> revlogRows, {
    List<double>? startingWeights,
  }) async {
    final initW = (startingWeights != null && startingWeights.length == 17)
        ? List<double>.from(startingWeights)
        : List<double>.from(FsrsScheduler.defaultWeights);

    return compute(
      _optimizeInIsolate,
      _OptimizeIsolatePayload(
        revlogRows: revlogRows,
        initialWeights: initW,
      ),
    );
  }
}

FsrsOptimizationResult _optimizeInIsolate(_OptimizeIsolatePayload payload) {
  final totalReviews = payload.revlogRows.length;
  final metThreshold = totalReviews >= FsrsWeightOptimizer.recommendedMinReviews;

  // Group reviews chronologically per card_id
  final byCard = <String, List<_ReviewEvent>>{};
  for (final row in payload.revlogRows) {
    final cardId = (row['card_id'] as String?) ?? '';
    if (cardId.isEmpty) continue;
    final grade = ((row['grade'] as num?)?.toInt() ?? 3).clamp(1, 4);
    final ts = (row['reviewed_at'] as num?)?.toInt() ?? 0;
    byCard.putIfAbsent(cardId, () => <_ReviewEvent>[]).add(
          _ReviewEvent(grade: grade, reviewedAtMs: ts),
        );
  }

  final sequences = <List<_ReviewEvent>>[];
  var usableTransitions = 0;
  for (final list in byCard.values) {
    if (list.length < 2) continue;
    list.sort((a, b) => a.reviewedAtMs.compareTo(b.reviewedAtMs));
    sequences.add(list);
    usableTransitions += list.length - 1;
  }

  final currentW = List<double>.from(payload.initialWeights);
  if (sequences.isEmpty || usableTransitions == 0) {
    return FsrsOptimizationResult(
      totalReviews: totalReviews,
      usableTransitions: 0,
      initialLogLoss: 0.0,
      optimizedLogLoss: 0.0,
      optimizedWeights: currentW,
      metRecommendedThreshold: metThreshold,
    );
  }

  // Adaptive L2 regularization strength: stronger when sample size is small,
  // lighter when >= 1,000 reviews are available.
  final l2Lambda =
      0.0015 * (1000.0 / math.max(100.0, usableTransitions.toDouble()));

  final initialLoss = _evaluateLoss(currentW, sequences, l2Lambda);
  var bestLoss = initialLoss;

  // Multi-scale coordinate pattern search across all 17 FSRS weights
  const stepScales = [0.12, 0.05, 0.02, 0.008];
  for (final scale in stepScales) {
    for (var i = 0; i < 17; i++) {
      final range =
          FsrsWeightOptimizer._maxBounds[i] - FsrsWeightOptimizer._minBounds[i];
      final delta = math.max(0.002, range * scale);
      final originalVal = currentW[i];

      var improved = false;
      for (final dir in const [1.0, -1.0]) {
        final candidateVal = (originalVal + dir * delta).clamp(
          FsrsWeightOptimizer._minBounds[i],
          FsrsWeightOptimizer._maxBounds[i],
        );
        currentW[i] = candidateVal;
        _enforceMonotonicInitialStabilities(currentW);
        final loss = _evaluateLoss(currentW, sequences, l2Lambda);
        if (loss + 1e-7 < bestLoss) {
          bestLoss = loss;
          improved = true;
          break;
        } else {
          currentW[i] = originalVal;
        }
      }
      if (!improved) {
        currentW[i] = originalVal;
      }
    }
  }

  _enforceMonotonicInitialStabilities(currentW);
  final rounded = currentW
      .map((v) => double.parse(v.toStringAsFixed(4)))
      .toList(growable: false);

  return FsrsOptimizationResult(
    totalReviews: totalReviews,
    usableTransitions: usableTransitions,
    initialLogLoss: initialLoss,
    optimizedLogLoss: bestLoss,
    optimizedWeights: rounded,
    metRecommendedThreshold: metThreshold,
  );
}

void _enforceMonotonicInitialStabilities(List<double> w) {
  // Ensure w0 (Again) < w1 (Hard) < w2 (Good) < w3 (Easy)
  if (w[1] <= w[0] + 0.1) w[1] = w[0] + 0.1;
  if (w[2] <= w[1] + 0.25) w[2] = w[1] + 0.25;
  if (w[3] <= w[2] + 0.5) w[3] = w[2] + 0.5;
}

double _evaluateLoss(
  List<double> w,
  List<List<_ReviewEvent>> sequences,
  double l2Lambda,
) {
  const factor = 19.0 / 81.0;
  const decay = -0.5;

  double totalBce = 0.0;
  int count = 0;

  final d0Good = (w[4] - w[5] * (3 - 3)).clamp(1.0, 10.0);

  for (final seq in sequences) {
    final first = seq.first;
    final g0 = first.grade;
    var s = math.max(0.1, w[g0 - 1]);
    var d = (w[4] - w[5] * (g0 - 3)).clamp(1.0, 10.0);
    var prevTs = first.reviewedAtMs;

    for (var k = 1; k < seq.length; k++) {
      final ev = seq[k];
      final rawDeltaDays = (ev.reviewedAtMs - prevTs) / 86400000.0;
      final elapsedDays = rawDeltaDays < 0.05 ? 0.25 : rawDeltaDays;
      prevTs = ev.reviewedAtMs;

      final r = math
          .pow(1.0 + factor * (elapsedDays / math.max(0.1, s)), decay)
          .toDouble()
          .clamp(0.001, 0.999);

      final y = ev.grade > 1 ? 1.0 : 0.0;
      totalBce += -(y * math.log(r) + (1.0 - y) * math.log(1.0 - r));
      count++;

      // Transition (S, D) using FSRS-4.5 equations
      final nextD = d - w[6] * (ev.grade - 3);
      d = (w[7] * d0Good + (1.0 - w[7]) * nextD).clamp(1.0, 10.0);

      if (ev.grade == 1) {
        final sMin = w[11] *
            math.pow(d, -w[12]) *
            (math.pow(s + 1.0, w[13]) - 1.0) *
            math.exp((1.0 - r) * w[14]);
        s = math.min(s, sMin).clamp(0.1, 36500.0);
      } else {
        final hardPenalty = ev.grade == 2 ? w[15] : 1.0;
        final easyBonus = ev.grade == 4 ? w[16] : 1.0;
        final inc = math.exp(w[8]) *
            (11.0 - d) *
            math.pow(s, -w[9]) *
            (math.exp((1.0 - r) * w[10]) - 1.0) *
            hardPenalty *
            easyBonus;
        s = (s * (1.0 + inc)).clamp(0.1, 36500.0);
      }
    }
  }

  final avgBce = count > 0 ? (totalBce / count) : 0.0;

  // L2 regularization penalty toward FSRS-4.5 default weights
  var l2 = 0.0;
  for (var i = 0; i < 17; i++) {
    final diff = (w[i] - FsrsScheduler.defaultWeights[i]) /
        math.max(0.5, FsrsScheduler.defaultWeights[i].abs());
    l2 += diff * diff;
  }

  return avgBce + l2Lambda * l2;
}
