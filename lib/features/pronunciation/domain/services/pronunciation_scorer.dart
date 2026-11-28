import '../entities/pronunciation_result.dart';

/// Input payload for any post-recording pronunciation scoring engine.
class PronunciationScoringRequest {
  final String cardId;
  final String word;
  final String targetIpa;
  final String contextSentence;
  final String accent;
  final PronunciationPracticeMode mode;
  final int durationMs;
  final List<double> waveformSamples;
  final String? audioFilePath;

  const PronunciationScoringRequest({
    required this.cardId,
    required this.word,
    required this.targetIpa,
    required this.contextSentence,
    required this.accent,
    required this.mode,
    required this.durationMs,
    required this.waveformSamples,
    this.audioFilePath,
  });
}

/// Abstract interface decoupling post-recording audio evaluation from the UI.
///
/// Swap in an on-device or cloud IPA/STT scoring model (e.g. Wav2Vec2, Whisper,
/// Azure Pronunciation Assessment) by implementing [PronunciationScorer] and
/// registering it in DI — no UI changes required.
abstract class PronunciationScorer {
  Future<PronunciationResult> scoreRecording(
    PronunciationScoringRequest request,
  );
}

/// Placeholder stub used while the on-device / cloud AI pronunciation scoring
/// model is under training. Replace in DI once the model is ready.
class StubPronunciationScorer implements PronunciationScorer {
  const StubPronunciationScorer();

  @override
  Future<PronunciationResult> scoreRecording(
    PronunciationScoringRequest request,
  ) {
    throw UnimplementedError(
      'AI PronunciationScorer model is coming soon. Plug your model implementation into DI.',
    );
  }
}
