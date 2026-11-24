import 'package:equatable/equatable.dart';

/// Represents a structural radical or morpheme root extracted from a token.
class RadicalComponent extends Equatable {
  final String symbol;
  final String meaning;
  final int strokeCount;

  const RadicalComponent({
    required this.symbol,
    required this.meaning,
    this.strokeCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'meaning': meaning,
        'stroke_count': strokeCount,
      };

  factory RadicalComponent.fromJson(Map<String, dynamic> json) {
    return RadicalComponent(
      symbol: (json['symbol'] as String?) ?? '',
      meaning: (json['meaning'] as String?) ?? '',
      strokeCount: (json['stroke_count'] as int?) ?? 0,
    );
  }

  @override
  List<Object?> get props => [symbol, meaning, strokeCount];
}

/// Represents a tokenized vocabulary item from user-inputted text,
/// enriched with phonetic transcription, translation, cloze sentence, and structural radicals.
class ExtractedToken extends Equatable {
  final String surfaceWord;
  final String lemma;
  final String phonetic;
  final String phoneticUs;
  final String phoneticUk;
  final String translation;
  final String partOfSpeech;
  final String sourceSentence;
  final String clozeSentence;
  final String audioUrl;
  final List<RadicalComponent> radicals;
  final bool isAlreadySaved;
  final bool isFromOfflineBundle;

  const ExtractedToken({
    required this.surfaceWord,
    this.lemma = '',
    required this.phonetic,
    this.phoneticUs = '',
    this.phoneticUk = '',
    required this.translation,
    required this.partOfSpeech,
    required this.sourceSentence,
    this.clozeSentence = '',
    this.audioUrl = '',
    required this.radicals,
    this.isAlreadySaved = false,
    this.isFromOfflineBundle = false,
  });

  String get effectivePhoneticUs =>
      phoneticUs.isNotEmpty ? phoneticUs : phonetic;

  ExtractedToken copyWith({
    String? surfaceWord,
    String? lemma,
    String? phonetic,
    String? phoneticUs,
    String? phoneticUk,
    String? translation,
    String? partOfSpeech,
    String? sourceSentence,
    String? clozeSentence,
    String? audioUrl,
    List<RadicalComponent>? radicals,
    bool? isAlreadySaved,
    bool? isFromOfflineBundle,
  }) {
    return ExtractedToken(
      surfaceWord: surfaceWord ?? this.surfaceWord,
      lemma: lemma ?? this.lemma,
      phonetic: phonetic ?? this.phonetic,
      phoneticUs: phoneticUs ?? this.phoneticUs,
      phoneticUk: phoneticUk ?? this.phoneticUk,
      translation: translation ?? this.translation,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      sourceSentence: sourceSentence ?? this.sourceSentence,
      clozeSentence: clozeSentence ?? this.clozeSentence,
      audioUrl: audioUrl ?? this.audioUrl,
      radicals: radicals ?? this.radicals,
      isAlreadySaved: isAlreadySaved ?? this.isAlreadySaved,
      isFromOfflineBundle: isFromOfflineBundle ?? this.isFromOfflineBundle,
    );
  }

  @override
  List<Object?> get props => [
        surfaceWord,
        lemma,
        phonetic,
        phoneticUs,
        phoneticUk,
        translation,
        partOfSpeech,
        sourceSentence,
        clozeSentence,
        audioUrl,
        radicals,
        isAlreadySaved,
        isFromOfflineBundle,
      ];
}
