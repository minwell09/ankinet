/// Normalizes narrow phonetic IPA transcriptions (e.g., from Open Dict Data / CMUdict)
/// into cleaner, learner-friendly broad IPA:
/// - Converts narrow dark-L `ɫ` -> `l` and alveolar approximant `ɹ` -> `r`
/// - Removes redundant primary stress marks `ˈ` on single-syllable words
///   (e.g., `/ˈɫɪft/` or `/lˈɪft/` -> `/lɪft/`).
class IpaNormalizer {
  static final RegExp _vowelNucleusRegex = RegExp(
    r'[aeiouɑɒæʌəɜɛɪɔʊʉɝɚ]+',
    caseSensitive: false,
  );

  static String normalize(String rawIpa) {
    final trimmed = rawIpa.trim();
    if (trimmed.isEmpty) return '';

    final hadSlashes = trimmed.startsWith('/') && trimmed.endsWith('/');
    String inner = hadSlashes
        ? trimmed.substring(1, trimmed.length - 1).trim()
        : trimmed;

    // 1. Replace narrow allophones with standard broad learner symbols
    inner = inner
        .replaceAll('ɫ', 'l')
        .replaceAll('ɹ', 'r')
        .replaceAll('ɾ', 't');

    // 2. Remove redundant primary stress ˈ on single-syllable words (single word, 1 vowel nucleus)
    if (!inner.contains(' ') && !inner.contains('.')) {
      final vowelGroups = _vowelNucleusRegex.allMatches(inner).length;
      if (vowelGroups <= 1 && !inner.contains('ˌ')) {
        inner = inner.replaceAll('ˈ', '').replaceAll("'", '');
      }
    }

    if (inner.isEmpty) return '';
    return hadSlashes ? '/$inner/' : inner;
  }
}
