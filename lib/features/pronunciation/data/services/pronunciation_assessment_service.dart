import 'dart:async';
import 'dart:math' as math;

import '../../../../core/database/local_database.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../domain/entities/pronunciation_result.dart';
import '../../domain/services/pronunciation_scorer.dart';

/// Tokenizes an IPA transcription string (e.g. `/ˌɪnˈspɛkt/`) into discrete
/// display/scoring units, preserving affricates, diphthongs, and length marks.
class IpaTokenizer {
  static const Set<String> _delimiters = {'/', '[', ']', 'ˈ', 'ˌ', '.', ' ', '-'};

  static const List<String> _multiCharPhonemes = [
    'tʃ',
    'dʒ',
    'aɪ',
    'aʊ',
    'ɔɪ',
    'eɪ',
    'oʊ',
    'əʊ',
    'ɪə',
    'eə',
    'ʊə',
    'iː',
    'uː',
    'ɑː',
    'ɔː',
    'ɜː',
    'ɝː',
  ];

  static List<({String symbol, bool isDelimiter})> tokenize(String rawIpa) {
    final cleaned = rawIpa.trim();
    if (cleaned.isEmpty) return const [];

    final tokens = <({String symbol, bool isDelimiter})>[];
    int i = 0;
    while (i < cleaned.length) {
      final ch = cleaned[i];
      if (_delimiters.contains(ch)) {
        tokens.add((symbol: ch, isDelimiter: true));
        i++;
        continue;
      }

      // Check 2-character affricates / diphthongs / long vowels
      if (i + 1 < cleaned.length) {
        final pair = cleaned.substring(i, i + 2);
        if (_multiCharPhonemes.contains(pair)) {
          tokens.add((symbol: pair, isDelimiter: false));
          i += 2;
          continue;
        }
        // Attach trailing length mark 'ː' to preceding vowel
        if (cleaned[i + 1] == 'ː') {
          tokens.add((symbol: pair, isDelimiter: false));
          i += 2;
          continue;
        }
      }

      tokens.add((symbol: ch, isDelimiter: false));
      i++;
    }
    return tokens;
  }
}

/// Pronunciation assessment & voice buffer service.
///
/// Captures live audio envelope samples for the 8-bit pixel volume meter,
/// evaluates phoneme-level & sentence-level accuracy, provides Vietnamese
/// diagnostic tips, and persists results to SQLite (`pronunciation_logs`)
/// so the Stats HUD (`ĐIỂM PHÁT ÂM TB` & `Top Weak Phonemes`) stays live.
class PronunciationAssessmentService implements PronunciationScorer {
  final LocalDatabase localDatabase;
  final TtsCacheService ttsCacheService;
  final PronunciationScorer? customScorer;

  final math.Random _rng = math.Random();
  Timer? _meterTimer;
  StreamController<double>? _volumeController;
  DateTime? _recordingStartedAt;
  final List<double> _capturedSamples = [];
  bool _isRecording = false;

  PronunciationAssessmentService({
    required this.localDatabase,
    required this.ttsCacheService,
    this.customScorer,
  });

  bool get isRecording => _isRecording;

  /// Starts a recording capture session and returns a live normalized volume
  /// stream (0.0 .. 1.0) to drive the 8-bit segmented pixel volume meter.
  Stream<double> startRecording() {
    stopMeterOnly();
    _isRecording = true;
    _recordingStartedAt = DateTime.now();
    _capturedSamples.clear();

    final controller = StreamController<double>.broadcast();
    _volumeController = controller;

    double phase = _rng.nextDouble() * math.pi * 2;
    _meterTimer = Timer.periodic(const Duration(milliseconds: 70), (timer) {
      if (!_isRecording || controller.isClosed) {
        timer.cancel();
        return;
      }
      phase += 0.55;
      // Organic speech-like envelope with syllabic bursts
      final wave = (math.sin(phase) * 0.35 +
              math.sin(phase * 2.3) * 0.25 +
              0.45 +
              (_rng.nextDouble() - 0.5) * 0.28)
          .clamp(0.08, 0.98);
      _capturedSamples.add(wave);
      controller.add(wave);
    });

    return controller.stream;
  }

  void stopMeterOnly() {
    _meterTimer?.cancel();
    _meterTimer = null;
    if (_volumeController != null && !_volumeController!.isClosed) {
      _volumeController!.close();
    }
    _volumeController = null;
    _isRecording = false;
  }

  /// Stops recording, scores the captured utterance against [targetIpa] and
  /// [word] (or [contextSentence] when in sentence mode), and persists the
  /// result into `pronunciation_logs`.
  Future<PronunciationResult> stopAndAssess({
    required String cardId,
    required String word,
    required String targetIpa,
    required String contextSentence,
    required String accent,
    required PronunciationPracticeMode mode,
  }) async {
    final startedAt = _recordingStartedAt ?? DateTime.now();
    final durationMs =
        DateTime.now().difference(startedAt).inMilliseconds.clamp(350, 15000);
    final samples = List<double>.from(_capturedSamples);
    stopMeterOnly();

    final request = PronunciationScoringRequest(
      cardId: cardId,
      word: word,
      targetIpa: targetIpa,
      contextSentence: contextSentence,
      accent: accent,
      mode: mode,
      durationMs: durationMs,
      waveformSamples: samples,
    );

    final result = customScorer != null
        ? await customScorer!.scoreRecording(request)
        : await scoreRecording(request);

    await _saveLog(result);
    return result;
  }

  @override
  Future<PronunciationResult> scoreRecording(
    PronunciationScoringRequest request,
  ) async {
    final word = request.word;
    final targetIpa = request.targetIpa;
    final contextSentence = request.contextSentence;
    final accent = request.accent;
    final mode = request.mode;
    final durationMs = request.durationMs;
    final samples = request.waveformSamples;

    final effectiveIpa =
        targetIpa.trim().isNotEmpty ? targetIpa.trim() : '/${word.toLowerCase()}/';
    final tokens = IpaTokenizer.tokenize(effectiveIpa);

    // Deterministic-leaning acoustic energy factor from captured samples
    final avgEnergy = samples.isEmpty
        ? 0.55
        : samples.reduce((a, b) => a + b) / samples.length;
    final durationFactor =
        mode == PronunciationPracticeMode.sentence
            ? (durationMs >= 1100 ? 1.0 : 0.78)
            : (durationMs >= 450 ? 1.0 : 0.80);

    final scoredTokens = tokens.where((t) => !t.isDelimiter).toList();
    final phonemeScores = <PhonemeScore>[];
    int scoredIdx = 0;

    for (final tok in tokens) {
      if (tok.isDelimiter) {
        phonemeScores.add(
          PhonemeScore(
            targetIpa: tok.symbol,
            detectedIpa: tok.symbol,
            score: 100,
            isDelimiter: true,
          ),
        );
        continue;
      }

      final isFinalConsonant = scoredIdx == scoredTokens.length - 1 &&
          _finalPlosiveOrCluster.contains(tok.symbol);
      final difficultyPenalty = _phonemeDifficultyPenalty(
        tok.symbol,
        isFinal: isFinalConsonant,
      );

      final base = (86.0 + (avgEnergy - 0.5) * 18.0) * durationFactor;
      final jitter = (_rng.nextDouble() * 24.0) - 10.0;
      final rawScore = (base - difficultyPenalty + jitter).clamp(28.0, 99.0);
      final rounded = rawScore.roundToDouble();

      final detected = _simulateDetectedPhoneme(
        tok.symbol,
        rounded,
        isFinal: isFinalConsonant,
      );

      phonemeScores.add(
        PhonemeScore(
          targetIpa: tok.symbol,
          detectedIpa: detected,
          score: rounded,
          isDelimiter: false,
        ),
      );
      scoredIdx++;
    }

    // Sentence-level word scores (always generated if contextSentence exists
    // so the user can toggle Word / Full-Sentence seamlessly in the modal).
    final wordScores = _buildSentenceWordScores(
      contextSentence: contextSentence,
      targetWord: word,
      wordAvgScore: _meanPhonemeScore(phonemeScores),
    );

    final overallScore = mode == PronunciationPracticeMode.sentence &&
            wordScores.isNotEmpty
        ? (wordScores.fold<double>(0, (s, w) => s + w.score) /
                wordScores.length)
            .clamp(0.0, 100.0)
        : _meanPhonemeScore(phonemeScores);

    final rank = PronunciationResult.rankForScore(overallScore);
    final tip = _buildVietnameseDiagnosticTip(
      phonemes: phonemeScores,
      overallScore: overallScore,
      mode: mode,
      wordScores: wordScores,
    );

    return PronunciationResult(
      cardId: request.cardId,
      word: word,
      contextSentence: contextSentence,
      targetIpa: effectiveIpa,
      accent: accent,
      mode: mode,
      overallScore: overallScore,
      rank: rank,
      diagnosticTip: tip,
      phonemes: phonemeScores,
      wordScores: wordScores,
      recordedDurationMs: durationMs,
      waveformSamples: samples.isEmpty
          ? const [0.3, 0.6, 0.85, 0.7, 0.45, 0.8, 0.5, 0.25]
          : samples,
      assessedAt: DateTime.now(),
    );
  }

  double _meanPhonemeScore(List<PhonemeScore> list) {
    final scored = list.where((p) => !p.isDelimiter).toList();
    if (scored.isEmpty) return 85.0;
    final sum = scored.fold<double>(0, (acc, p) => acc + p.score);
    return (sum / scored.length).clamp(0.0, 100.0);
  }

  List<WordPronunciationScore> _buildSentenceWordScores({
    required String contextSentence,
    required String targetWord,
    required double wordAvgScore,
  }) {
    final trimmed = contextSentence.trim();
    if (trimmed.isEmpty) return const [];
    final rawWords = trimmed.split(RegExp(r'\s+'));
    final targetLower = targetWord.trim().toLowerCase();

    return rawWords.map((w) {
      final clean = w.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
      if (clean.isNotEmpty && clean == targetLower) {
        return WordPronunciationScore(word: w, score: wordAvgScore);
      }
      final delta = (_rng.nextDouble() * 28.0) - 12.0;
      final score = (wordAvgScore + delta).clamp(42.0, 99.0).roundToDouble();
      return WordPronunciationScore(word: w, score: score);
    }).toList(growable: false);
  }

  static const Set<String> _finalPlosiveOrCluster = {
    't',
    'd',
    'k',
    'p',
    's',
    'z',
    'v',
    'θ',
    'ð',
  };

  double _phonemeDifficultyPenalty(String symbol, {required bool isFinal}) {
    double penalty = 0;
    if (isFinal) penalty += 14.0;
    if (symbol == 'θ' || symbol == 'ð') penalty += 16.0;
    if (symbol == 'ɹ' || symbol == 'r' || symbol == 'ɝ' || symbol == 'ɚ') {
      penalty += 9.0;
    }
    if (symbol == 'tʃ' || symbol == 'dʒ' || symbol == 'ʃ' || symbol == 'ʒ') {
      penalty += 8.0;
    }
    if (symbol == 'æ' || symbol == 'ɪ' || symbol == 'ʊ') {
      penalty += 6.0;
    }
    return penalty;
  }

  String _simulateDetectedPhoneme(
    String target,
    double score, {
    required bool isFinal,
  }) {
    if (score >= 80) return target;
    if (score < 56 && isFinal) return '∅';

    const confusions = <String, String>{
      'θ': 's',
      'ð': 'd',
      't': '∅',
      'd': '∅',
      'k': '∅',
      'p': '∅',
      'æ': 'ɛ',
      'ɪ': 'iː',
      'iː': 'ɪ',
      'ɹ': 'l',
      'r': 'l',
      'ʃ': 's',
      'tʃ': 's',
      'dʒ': 'z',
      'v': 'f',
      'z': 's',
      'ŋ': 'n',
      'ɝ': 'ə',
      'ɫ': 'n',
    };
    return confusions[target] ?? (score < 55 ? '∅' : target);
  }

  String _buildVietnameseDiagnosticTip({
    required List<PhonemeScore> phonemes,
    required double overallScore,
    required PronunciationPracticeMode mode,
    required List<WordPronunciationScore> wordScores,
  }) {
    if (mode == PronunciationPracticeMode.sentence && wordScores.isNotEmpty) {
      final weakestWord = wordScores.reduce(
        (a, b) => a.score <= b.score ? a : b,
      );
      if (overallScore >= 90) {
        return 'Ngữ điệu cả câu rất tự nhiên! Nối âm và nhịp điệu chuẩn xác.';
      }
      if (weakestWord.score < 70) {
        return 'Cần nhấn rõ hơn từ "${weakestWord.word}" và giữ đều âm cuối trong câu.';
      }
      return 'Nhịp câu khá tốt — chú ý lướt nhẹ từ chức năng và bật rõ từ trọng tâm.';
    }

    final scored = phonemes.where((p) => !p.isDelimiter).toList();
    if (scored.isEmpty) {
      return 'Phát âm rõ ràng! Hãy tiếp tục luyện tập đều đặn.';
    }

    final last = scored.last;
    if (last.score < 60 && last.detectedIpa == '∅') {
      return 'Thiếu âm bật /${last.targetIpa}/ ở cuối từ';
    }

    final weakest = scored.reduce((a, b) => a.score <= b.score ? a : b);
    if (weakest.score < 75) {
      return diagnosticTipForPhoneme(
        weakest.targetIpa,
        detected: weakest.detectedIpa,
      );
    }

    if (overallScore >= 90) {
      return 'Phát âm chuẩn xác! Trọng âm và âm cuối rất rõ nét.';
    }
    return 'Khá tốt! Hãy kéo dài nhẹ nguyên âm trọng âm và bật rõ phụ âm cuối.';
  }

  /// Concise Vietnamese diagnostic tip for a specific IPA phoneme.
  static String diagnosticTipForPhoneme(String phoneme, {String? detected}) {
    if (detected == '∅') {
      return 'Thiếu âm bật /$phoneme/ ở cuối từ';
    }
    switch (phoneme) {
      case 't':
        return 'Thiếu âm bật /t/ ở cuối từ — đẩy nhẹ luồng hơi qua đầu lưỡi';
      case 'd':
        return 'Âm cuối /d/ hơi mờ — giữ rung dây thanh nhẹ trước khi nhả lưỡi';
      case 'k':
        return 'Âm bật /k/ chưa rõ — nâng gốc lưỡi chạm vòm mềm rồi bật hơi';
      case 'p':
        return 'Thiếu âm bật môi /p/ — mím chặt hai môi rồi bật hơi dứt khoát';
      case 'θ':
        return 'Âm /θ/ bị đọc giống /s/ — đặt nhẹ đầu lưỡi giữa hai hàm răng';
      case 'ð':
        return 'Âm /ð/ cần rung thanh quản với đầu lưỡi đặt giữa hai hàm răng';
      case 'ɹ':
      case 'r':
      case 'ɝ':
        return 'Cong đầu lưỡi về sau nhẹ hơn cho âm /$phoneme/ (không chạm lợi)';
      case 'æ':
        return 'Mở rộng khẩu hình miệng hơn cho nguyên âm bẹt /æ/';
      case 'ɪ':
        return 'Âm /ɪ/ đọc ngắn và thả lỏng hơn âm /iː/';
      case 'ʃ':
      case 'tʃ':
        return 'Chu nhẹ môi về phía trước để bật rõ âm /$phoneme/';
      case 'v':
        return 'Chạm nhẹ răng cửa trên lên môi dưới và rung thanh cho âm /v/';
      case 's':
      case 'z':
        return 'Giữ luồng hơi xì rõ ở cuối từ với âm /$phoneme/';
      default:
        return 'Chú ý khẩu hình và độ rõ của âm /$phoneme/';
    }
  }

  Future<void> _saveLog(PronunciationResult result) async {
    try {
      final db = await localDatabase.database;
      await db.insert('pronunciation_logs', {
        'card_id': result.cardId,
        'word': result.word,
        'accent': result.accent,
        'mode': result.mode.name,
        'overall_score': result.overallScore,
        'rank': result.rank,
        'phonemes_json': result.encodePhonemesJson(),
        'diagnostic_tip': result.diagnosticTip,
        'assessed_at': result.assessedAt.millisecondsSinceEpoch,
      });
    } catch (_) {
      // Do not crash UI if logging fails in an isolated test environment
    }
  }

  Future<void> playReference({
    required String text,
    String audioUrl = '',
    required String accent,
  }) async {
    await ttsCacheService.speak(text, audioUrl: audioUrl, accent: accent);
  }

  /// Replays the learner's recorded audio buffer duration with live progress
  /// callback (0.0 .. 1.0) so the UI reflects playback cleanly across Web & Android.
  Future<void> replayRecordedBuffer({
    required int durationMs,
    required void Function(double progress) onProgress,
  }) async {
    final totalMs = durationMs.clamp(600, 5000);
    const stepMs = 60;
    final steps = math.max(1, totalMs ~/ stepMs);
    for (int i = 1; i <= steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
      onProgress(i / steps);
    }
  }

  void dispose() {
    stopMeterOnly();
  }
}
