import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Semantic colors matching the Cozy 16-bit Stardew Valley Pixel RPG palette
/// and the Pronunciation Assessment spec.
class PronunciationColors {
  static const Color accurate = Color(0xFF3E8E35); // #3E8E35 green
  static const Color close = Color(0xFFD9822B); // #D9822B amber
  static const Color missed = Color(0xFFC93B3B); // #C93B3B red
  static const Color recordingCoral = Color(0xFFD94E4E); // #D94E4E coral red
  static const Color rankSGold = Color(0xFFF2A93B); // Harvest gold for S rank

  static Color forScore(double score) {
    if (score >= 80) return accurate;
    if (score >= 60) return close;
    return missed;
  }

  static Color forRank(String rank) {
    switch (rank.toUpperCase()) {
      case 'S':
        return accurate;
      case 'A':
        return accurate;
      case 'B':
        return close;
      default:
        return missed;
    }
  }
}

enum PhonemeAccuracyStatus {
  accurate,
  close,
  missed,
}

enum PronunciationPracticeMode {
  word,
  sentence,
}

class PhonemeScore extends Equatable {
  /// Target IPA symbol (e.g. 't', 'ɛ', 'tʃ', or delimiter like 'ˈ', '/').
  final String targetIpa;

  /// Detected IPA symbol from the learner's speech ('∅' when dropped/omitted).
  final String detectedIpa;

  /// Accuracy score in 0..100. Ignored when [isDelimiter] is true.
  final double score;

  /// True for structural symbols like '/', 'ˈ', 'ˌ', '.' that are rendered
  /// inline on the card without being scored as phonemes.
  final bool isDelimiter;

  const PhonemeScore({
    required this.targetIpa,
    required this.detectedIpa,
    required this.score,
    this.isDelimiter = false,
  });

  PhonemeAccuracyStatus get status {
    if (score >= 80) return PhonemeAccuracyStatus.accurate;
    if (score >= 60) return PhonemeAccuracyStatus.close;
    return PhonemeAccuracyStatus.missed;
  }

  Color get color => PronunciationColors.forScore(score);

  Map<String, dynamic> toJson() => {
        'target': targetIpa,
        'detected': detectedIpa,
        'score': score,
        'isDelimiter': isDelimiter,
      };

  factory PhonemeScore.fromJson(Map<String, dynamic> json) {
    return PhonemeScore(
      targetIpa: (json['target'] as String?) ?? '',
      detectedIpa: (json['detected'] as String?) ?? '',
      score: ((json['score'] as num?) ?? 0).toDouble(),
      isDelimiter: (json['isDelimiter'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props => [targetIpa, detectedIpa, score, isDelimiter];
}

class WordPronunciationScore extends Equatable {
  final String word;
  final double score;

  const WordPronunciationScore({
    required this.word,
    required this.score,
  });

  PhonemeAccuracyStatus get status {
    if (score >= 80) return PhonemeAccuracyStatus.accurate;
    if (score >= 60) return PhonemeAccuracyStatus.close;
    return PhonemeAccuracyStatus.missed;
  }

  Color get color => PronunciationColors.forScore(score);

  @override
  List<Object?> get props => [word, score];
}

class PronunciationResult extends Equatable {
  final String cardId;
  final String word;
  final String contextSentence;
  final String targetIpa;
  final String accent; // 'en-US' or 'en-GB'
  final PronunciationPracticeMode mode;
  final double overallScore; // 0..100
  final String rank; // 'S', 'A', 'B', 'C'
  final String diagnosticTip;
  final List<PhonemeScore> phonemes;
  final List<WordPronunciationScore> wordScores;
  final int recordedDurationMs;
  final List<double> waveformSamples;
  final DateTime assessedAt;

  const PronunciationResult({
    required this.cardId,
    required this.word,
    required this.contextSentence,
    required this.targetIpa,
    required this.accent,
    required this.mode,
    required this.overallScore,
    required this.rank,
    required this.diagnosticTip,
    required this.phonemes,
    this.wordScores = const [],
    this.recordedDurationMs = 0,
    this.waveformSamples = const [],
    required this.assessedAt,
  });

  List<PhonemeScore> get scoredPhonemes =>
      phonemes.where((p) => !p.isDelimiter).toList(growable: false);

  String get compactBadgeLabel => '${overallScore.round()}% • $rank';

  static String rankForScore(double score) {
    if (score >= 90) return 'S';
    if (score >= 80) return 'A';
    if (score >= 65) return 'B';
    return 'C';
  }

  String encodePhonemesJson() => jsonEncode(
        scoredPhonemes.map((p) => p.toJson()).toList(growable: false),
      );

  @override
  List<Object?> get props => [
        cardId,
        word,
        contextSentence,
        targetIpa,
        accent,
        mode,
        overallScore,
        rank,
        diagnosticTip,
        phonemes,
        wordScores,
        recordedDurationMs,
        waveformSamples,
        assessedAt,
      ];
}

class WeakPhonemeStat extends Equatable {
  final String phoneme;
  final double averageScore;
  final int attempts;
  final int missCount;
  final String tip;

  const WeakPhonemeStat({
    required this.phoneme,
    required this.averageScore,
    required this.attempts,
    required this.missCount,
    required this.tip,
  });

  @override
  List<Object?> get props => [phoneme, averageScore, attempts, missCount, tip];
}
