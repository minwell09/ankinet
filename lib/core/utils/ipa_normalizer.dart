/// Normalizes narrow phonetic IPA transcriptions (e.g., from Open Dict Data / CMUdict)
/// into cleaner, learner-friendly broad IPA:
/// - Converts narrow dark-L `ɫ` -> `l` and alveolar approximant `ɹ` -> `r`
/// - Removes redundant primary stress marks `ˈ` on single-syllable words
///   (e.g., `/ˈɫɪft/`, `/lˈɪft/`, `/tˈæpt/` -> `/lɪft/`, `/tæpt/`)
/// - Fixes initial mid-onset stress placement from `ipa-dict` UK entries
///   (e.g., `/pˈɔːtəbəl/` -> `/ˈpɔːtəbəl/`, `/stɹˈʌktʃɐ/` -> `/ˈstrʌktʃɐ/`).
class IpaNormalizer {
  static final RegExp _vowelNucleusRegex = RegExp(
    r'[aeiouɑɒæʌəɜɛɪɔʊʉɝɚɐ]+',
    caseSensitive: false,
  );

  // Matches initial consonant onset followed immediately by primary stress ˈ before the first vowel
  static final RegExp _initialMidOnsetStressRegex = RegExp(
    r'^([^aeiouɑɒæʌəɜɛɪɔʊʉɝɚɐˈˌ\s.]{1,4})ˈ([aeiouɑɒæʌəɜɛɪɔʊʉɝɚɐ])',
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

    // 2. Single-word stress cleanup
    if (!inner.contains(' ') && !inner.contains('.')) {
      final vowelGroups = _vowelNucleusRegex.allMatches(inner).length;
      if (vowelGroups <= 1 && !inner.contains('ˌ')) {
        // Remove redundant primary stress ˈ on single-syllable words (e.g., /tˈæpt/ -> /tæpt/)
        inner = inner.replaceAll('ˈ', '').replaceAll("'", '');
      } else {
        // Fix initial mid-onset stress placement from UK ipa-dict (e.g., /pˈɔːtəbəl/ -> /ˈpɔːtəbəl/)
        inner = inner.replaceFirstMapped(
          _initialMidOnsetStressRegex,
          (m) => 'ˈ${m.group(1)}${m.group(2)}',
        );
      }
    }

    if (inner.isEmpty) return '';
    return hadSlashes ? '/$inner/' : inner;
  }
}
