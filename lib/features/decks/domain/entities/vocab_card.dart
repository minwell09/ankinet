import 'package:equatable/equatable.dart';

import '../../../../core/srs/fsrs_scheduler.dart';
import '../../../../core/utils/cloze_masker.dart';

class VocabCard extends Equatable {
  final String id;
  final String deckId;
  final String word;
  final String lemma;
  final String phonetic;
  final String phoneticUs;
  final String phoneticUk;
  final String translation;
  final String partOfSpeech;
  final String contextSentence;
  final String clozeSentence;
  final String audioUrl;
  final CardState state;
  final int stepIndex;
  final double stability;
  final double difficulty;
  final int intervalDays;
  final int repetitions;
  final int lapses;
  final double easeFactor;
  final bool isLeech;
  final bool isSuspended;
  final DateTime? lastReviewAt;
  final DateTime nextReviewAt;

  const VocabCard({
    required this.id,
    required this.deckId,
    required this.word,
    this.lemma = '',
    required this.phonetic,
    this.phoneticUs = '',
    this.phoneticUk = '',
    required this.translation,
    this.partOfSpeech = 'vocab',
    required this.contextSentence,
    this.clozeSentence = '',
    this.audioUrl = '',
    this.state = CardState.newCard,
    this.stepIndex = 0,
    this.stability = 0.0,
    this.difficulty = 5.0,
    required this.intervalDays,
    required this.repetitions,
    this.lapses = 0,
    required this.easeFactor,
    this.isLeech = false,
    this.isSuspended = false,
    this.lastReviewAt,
    required this.nextReviewAt,
  });

  String get effectivePhoneticUs =>
      phoneticUs.isNotEmpty ? phoneticUs : phonetic;

  String get formattedPhoneticSummary {
    final us = effectivePhoneticUs;
    final uk = phoneticUk;
    if (us.isNotEmpty && uk.isNotEmpty) {
      return 'US $us • UK $uk';
    }
    return us.isNotEmpty ? us : uk;
  }

  /// Always masks the exact surface form appearing in the sentence (e.g. `running`
  /// or `ran` even if the card stores the lemma `run`), preventing the front of
  /// the flashcard from leaking the answer.
  String get effectiveClozeSentence {
    final baseSentence =
        clozeSentence.isNotEmpty ? clozeSentence : contextSentence;
    if (baseSentence.isEmpty) return '';

    if (baseSentence.contains(ClozeMasker.placeholder) &&
        !ClozeMasker.containsUnmaskedSurfaceForm(
          clozeSentence: baseSentence,
          word: word,
          lemma: lemma,
        )) {
      return baseSentence;
    }

    return ClozeMasker.maskSentence(
      sentence: contextSentence.isNotEmpty ? contextSentence : baseSentence,
      word: word,
      lemma: lemma,
    );
  }

  factory VocabCard.fromRow(Map<String, Object?> r) {
    final lastRev = r['last_review_at'] as int?;
    return VocabCard(
      id: r['id'] as String,
      deckId: r['deck_id'] as String,
      word: r['word'] as String,
      lemma: (r['lemma'] as String?) ?? '',
      phonetic: (r['phonetic'] as String?) ?? '',
      phoneticUs: (r['phonetic_us'] as String?) ?? '',
      phoneticUk: (r['phonetic_uk'] as String?) ?? '',
      translation: (r['translation'] as String?) ?? '',
      partOfSpeech: (r['part_of_speech'] as String?) ?? 'vocab',
      contextSentence: (r['context_sentence'] as String?) ?? '',
      clozeSentence: (r['cloze_sentence'] as String?) ?? '',
      audioUrl: (r['audio_url'] as String?) ?? '',
      state: CardState.fromCode((r['state'] as int?) ?? 0),
      stepIndex: (r['step_index'] as int?) ?? 0,
      stability: ((r['stability'] as num?) ?? 0.0).toDouble(),
      difficulty: ((r['difficulty'] as num?) ?? 5.0).toDouble(),
      intervalDays: (r['interval_days'] as int?) ?? 0,
      repetitions: (r['repetitions'] as int?) ?? 0,
      lapses: (r['lapses'] as int?) ?? 0,
      easeFactor: ((r['ease_factor'] as num?) ?? 2.5).toDouble(),
      isLeech: ((r['is_leech'] as int?) ?? 0) == 1,
      isSuspended: ((r['is_suspended'] as int?) ?? 0) == 1,
      lastReviewAt: lastRev != null
          ? DateTime.fromMillisecondsSinceEpoch(lastRev)
          : null,
      nextReviewAt: DateTime.fromMillisecondsSinceEpoch(
        (r['next_review_at'] as int?) ?? 0,
      ),
    );
  }

  @override
  List<Object?> get props => [
        id,
        deckId,
        word,
        lemma,
        phonetic,
        phoneticUs,
        phoneticUk,
        translation,
        partOfSpeech,
        contextSentence,
        clozeSentence,
        audioUrl,
        state,
        stepIndex,
        stability,
        difficulty,
        intervalDays,
        repetitions,
        lapses,
        easeFactor,
        isLeech,
        isSuspended,
        lastReviewAt,
        nextReviewAt,
      ];
}
