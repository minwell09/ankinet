import '../../domain/entities/extracted_token.dart';

class ExtractedTokenModel extends ExtractedToken {
  const ExtractedTokenModel({
    required super.surfaceWord,
    super.lemma,
    required super.phonetic,
    super.phoneticUs,
    super.phoneticUk,
    required super.translation,
    required super.partOfSpeech,
    required super.sourceSentence,
    super.clozeSentence,
    super.audioUrl,
    required super.radicals,
    super.isAlreadySaved,
    super.isFromOfflineBundle,
  });

  factory ExtractedTokenModel.fromJson(Map<String, dynamic> json) {
    final radicalList = (json['radicals'] as List<dynamic>? ?? [])
        .map((r) => RadicalComponent.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();

    final surface = json['surface_word'] as String;
    final phonetic = (json['phonetic'] as String?) ?? '';
    return ExtractedTokenModel(
      surfaceWord: surface,
      lemma: (json['lemma'] as String?) ?? surface,
      phonetic: phonetic,
      phoneticUs: (json['phonetic_us'] as String?) ?? '',
      phoneticUk: (json['phonetic_uk'] as String?) ?? '',
      translation: (json['translation'] as String?) ?? '',
      partOfSpeech: (json['pos'] as String?) ?? 'vocab',
      sourceSentence: (json['source_sentence'] as String?) ?? '',
      clozeSentence: (json['cloze_sentence'] as String?) ?? '',
      audioUrl: (json['audio_url'] as String?) ?? '',
      radicals: radicalList,
      isAlreadySaved: (json['is_already_saved'] as bool?) ?? false,
      isFromOfflineBundle: (json['is_from_offline_bundle'] as bool?) ?? false,
    );
  }
}
