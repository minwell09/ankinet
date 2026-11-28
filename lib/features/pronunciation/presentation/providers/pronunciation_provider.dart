import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/injection_container.dart';
import '../../../decks/domain/entities/vocab_card.dart';
import '../../../stats/presentation/providers/stats_provider.dart';
import '../../data/services/pronunciation_assessment_service.dart';
import '../../domain/entities/pronunciation_result.dart';

class PronunciationSessionState {
  final bool isRecording;
  final bool isScoring;
  final bool isPlayingUserAudio;
  final double playbackProgress;
  final double volumeLevel;
  final PronunciationPracticeMode mode;
  final PronunciationResult? lastResult;
  final String? errorMessage;

  const PronunciationSessionState({
    this.isRecording = false,
    this.isScoring = false,
    this.isPlayingUserAudio = false,
    this.playbackProgress = 0.0,
    this.volumeLevel = 0.0,
    this.mode = PronunciationPracticeMode.word,
    this.lastResult,
    this.errorMessage,
  });

  PronunciationSessionState copyWith({
    bool? isRecording,
    bool? isScoring,
    bool? isPlayingUserAudio,
    double? playbackProgress,
    double? volumeLevel,
    PronunciationPracticeMode? mode,
    PronunciationResult? lastResult,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PronunciationSessionState(
      isRecording: isRecording ?? this.isRecording,
      isScoring: isScoring ?? this.isScoring,
      isPlayingUserAudio: isPlayingUserAudio ?? this.isPlayingUserAudio,
      playbackProgress: playbackProgress ?? this.playbackProgress,
      volumeLevel: volumeLevel ?? this.volumeLevel,
      mode: mode ?? this.mode,
      lastResult: lastResult ?? this.lastResult,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class PronunciationSessionNotifier
    extends StateNotifier<PronunciationSessionState> {
  final PronunciationAssessmentService _service;
  final Ref _ref;
  StreamSubscription<double>? _volumeSub;

  PronunciationSessionNotifier(this._service, this._ref)
      : super(const PronunciationSessionState());

  Future<void> toggleRecording({
    required VocabCard card,
    required String accent,
    PronunciationPracticeMode? overrideMode,
  }) async {
    final activeMode = overrideMode ?? state.mode;
    if (state.isRecording) {
      await _stopAndAssess(card: card, accent: accent, mode: activeMode);
    } else {
      _startRecording(mode: activeMode);
    }
  }

  void _startRecording({required PronunciationPracticeMode mode}) {
    _volumeSub?.cancel();
    state = state.copyWith(
      isRecording: true,
      isScoring: false,
      mode: mode,
      volumeLevel: 0.15,
      clearError: true,
    );
    final stream = _service.startRecording();
    _volumeSub = stream.listen((level) {
      if (mounted) {
        state = state.copyWith(volumeLevel: level);
      }
    });
  }

  Future<void> _stopAndAssess({
    required VocabCard card,
    required String accent,
    required PronunciationPracticeMode mode,
  }) async {
    final sub = _volumeSub;
    _volumeSub = null;
    state = state.copyWith(
      isRecording: false,
      isScoring: true,
      volumeLevel: 0.0,
    );
    _service.stopMeterOnly();
    sub?.cancel();

    try {
      final targetIpa = accent == 'en-GB' && card.phoneticUk.isNotEmpty
          ? card.phoneticUk
          : card.effectivePhoneticUs;
      final result = await _service.stopAndAssess(
        cardId: card.id,
        word: card.word,
        targetIpa: targetIpa,
        contextSentence: card.contextSentence,
        accent: accent,
        mode: mode,
      );
      if (!mounted) return;
      state = state.copyWith(
        isScoring: false,
        lastResult: result,
        mode: mode,
      );
      // Refresh Stats HUD so ĐIỂM PHÁT ÂM TB & Top Weak Phonemes stay up to date
      _ref.invalidate(studyStatsProvider);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isScoring: false,
        errorMessage: 'Không thể chấm điểm phát âm: $e',
      );
    }
  }

  void setMode(PronunciationPracticeMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
  }

  Future<void> playReference({
    required VocabCard card,
    required String accent,
  }) async {
    final text = state.mode == PronunciationPracticeMode.sentence &&
            card.contextSentence.trim().isNotEmpty
        ? card.contextSentence
        : card.word;
    await _service.playReference(
      text: text,
      audioUrl: state.mode == PronunciationPracticeMode.word ? card.audioUrl : '',
      accent: accent,
    );
  }

  Future<void> playUserRecording() async {
    final result = state.lastResult;
    if (result == null || state.isPlayingUserAudio) return;
    state = state.copyWith(isPlayingUserAudio: true, playbackProgress: 0.0);
    await _service.replayRecordedBuffer(
      durationMs: result.recordedDurationMs,
      onProgress: (p) {
        if (mounted) {
          state = state.copyWith(playbackProgress: p);
        }
      },
    );
    if (mounted) {
      state = state.copyWith(isPlayingUserAudio: false, playbackProgress: 0.0);
    }
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    if (state.isRecording) {
      _service.stopMeterOnly();
    }
    super.dispose();
  }
}

final pronunciationSessionProvider = StateNotifierProvider.autoDispose
    .family<PronunciationSessionNotifier, PronunciationSessionState, String>(
  (ref, cardId) => PronunciationSessionNotifier(
    sl<PronunciationAssessmentService>(),
    ref,
  ),
);
