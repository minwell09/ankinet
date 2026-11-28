import '../../../../core/database/offline_dictionary_database.dart';

/// Result of a Dual-Resolution dictionary lookup:
/// - Keeps exact US/UK IPA of the user's queried word (e.g. `snapped` -> `/snæpt/`).
/// - Resolves the base lemma (e.g. `snap`) via Vietnamese cross-reference regex,
///   `irregular_lemmas`, or morphological suffix rules to display the full meaning.
class DictionaryLookupResult {
  final String queryWord;
  final OfflineDictEntry? surfaceEntry;
  final String? lemmaWord;
  final OfflineDictEntry? lemmaEntry;

  const DictionaryLookupResult({
    required this.queryWord,
    this.surfaceEntry,
    this.lemmaWord,
    this.lemmaEntry,
  });

  bool get isInflectedForm =>
      lemmaWord != null &&
      lemmaWord!.isNotEmpty &&
      lemmaWord!.toLowerCase() != queryWord.toLowerCase();

  /// Exact IPA US of the queried surface form (falls back to lemma if missing).
  String get ipaUs {
    final s = surfaceEntry?.ipaUs ?? '';
    if (s.isNotEmpty) return s;
    final sGeneric = surfaceEntry?.ipa ?? '';
    if (sGeneric.isNotEmpty) return sGeneric;
    final l = lemmaEntry?.ipaUs ?? '';
    return l.isNotEmpty ? l : (lemmaEntry?.ipa ?? '');
  }

  /// Exact IPA UK of the queried surface form (falls back to lemma if missing).
  String get ipaUk {
    final s = surfaceEntry?.ipaUk ?? '';
    if (s.isNotEmpty) return s;
    return lemmaEntry?.ipaUk ?? '';
  }

  String get displayPos {
    final lPos = lemmaEntry?.pos ?? '';
    final sPos = surfaceEntry?.pos ?? '';
    if (isInflectedForm && lPos.isNotEmpty && lPos != 'vocab') return lPos;
    if (sPos.isNotEmpty && sPos != 'vocab') return sPos;
    return lPos.isNotEmpty ? lPos : 'vocab';
  }

  /// Full Vietnamese meaning: prefers base lemma's definition when surface
  /// entry is only a short grammatical cross-reference.
  String get displayMeaning {
    final sVi = surfaceEntry?.vi.trim() ?? '';
    final lVi = lemmaEntry?.vi.trim() ?? '';
    if (isInflectedForm && lVi.isNotEmpty) {
      if (sVi.isEmpty || LookupPronunciationUseCase.isCrossReference(sVi)) {
        return lVi;
      }
    }
    return sVi.isNotEmpty ? sVi : lVi;
  }

  /// Word to save when saving by base lemma (default) vs inflected surface form.
  String wordToSave({required bool saveAsLemma}) =>
      (saveAsLemma && isInflectedForm) ? lemmaWord! : queryWord;

  String ipaUsToSave({required bool saveAsLemma}) {
    if (saveAsLemma && isInflectedForm && lemmaEntry != null) {
      return lemmaEntry!.ipaUs.isNotEmpty
          ? lemmaEntry!.ipaUs
          : (lemmaEntry!.ipa.isNotEmpty ? lemmaEntry!.ipa : ipaUs);
    }
    return ipaUs;
  }

  String ipaUkToSave({required bool saveAsLemma}) {
    if (saveAsLemma && isInflectedForm && lemmaEntry != null) {
      return lemmaEntry!.ipaUk.isNotEmpty ? lemmaEntry!.ipaUk : ipaUk;
    }
    return ipaUk;
  }
}

class LookupPronunciationUseCase {
  final OfflineDictionaryDatabase dictionaryDatabase;

  const LookupPronunciationUseCase(this.dictionaryDatabase);

  static final RegExp _crossRefRegex = RegExp(
    r'(?:quá khứ|phân từ|số nhiều|dạng chia|so sánh|ngôi thứ|biến thể|hình thức|dạng\s+\w+)[^.;\n]*?của\s+([a-zA-Z][a-zA-Z\-]*)',
    caseSensitive: false,
  );

  static final RegExp _simpleOfRegex = RegExp(
    r'\bcủa\s+([a-zA-Z][a-zA-Z\-]*)',
    caseSensitive: false,
  );

  static bool isCrossReference(String vi) {
    final lower = vi.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.length > 110) return false;
    return lower.contains('quá khứ') ||
        lower.contains('phân từ') ||
        lower.contains('số nhiều của') ||
        lower.contains('dạng chia của') ||
        lower.contains('ngôi thứ') ||
        lower.contains('so sánh hơn của') ||
        lower.contains('so sánh nhất của') ||
        _crossRefRegex.hasMatch(lower);
  }

  static String? extractCrossReferenceLemma(String vi) {
    final m1 = _crossRefRegex.firstMatch(vi);
    if (m1 != null) return m1.group(1)?.toLowerCase();
    if (isCrossReference(vi)) {
      final m2 = _simpleOfRegex.firstMatch(vi);
      if (m2 != null) return m2.group(1)?.toLowerCase();
    }
    return null;
  }

  static List<String> suffixCandidates(String w) {
    final out = <String>[];
    if (w.endsWith('ies') && w.length > 4) {
      out.add('${w.substring(0, w.length - 3)}y');
    }
    if (w.endsWith('ied') && w.length > 4) {
      out.add('${w.substring(0, w.length - 3)}y');
    }
    if (w.endsWith('ves') && w.length > 4) {
      out.add('${w.substring(0, w.length - 3)}f');
      out.add('${w.substring(0, w.length - 3)}fe');
    }
    if (w.endsWith('ing') && w.length > 5) {
      final stem = w.substring(0, w.length - 3);
      out.add(stem);
      out.add('${stem}e');
      if (stem.length >= 3 && stem[stem.length - 1] == stem[stem.length - 2]) {
        out.add(stem.substring(0, stem.length - 1));
      }
    }
    if (w.endsWith('ed') && w.length > 4) {
      final stem = w.substring(0, w.length - 2);
      out.add(stem);
      out.add(w.substring(0, w.length - 1)); // e.g. baked -> bake
      if (stem.length >= 3 && stem[stem.length - 1] == stem[stem.length - 2]) {
        out.add(stem.substring(0, stem.length - 1)); // snapped -> snap
      }
    }
    if (w.endsWith('es') && w.length > 4) {
      out.add(w.substring(0, w.length - 2));
      out.add(w.substring(0, w.length - 1));
    }
    if (w.endsWith('s') &&
        !w.endsWith('ss') &&
        !w.endsWith('us') &&
        !w.endsWith('is') &&
        w.length > 3) {
      out.add(w.substring(0, w.length - 1));
    }
    return out.where((c) => c != w && c.length >= 2).toSet().toList();
  }

  /// Backward-compatible single-entry call.
  Future<OfflineDictEntry?> call(String rawWord) async {
    final resolved = await lookupDual(rawWord);
    if (resolved == null) return null;
    return OfflineDictEntry(
      word: resolved.queryWord,
      ipa: resolved.ipaUs.isNotEmpty ? resolved.ipaUs : resolved.ipaUk,
      ipaUs: resolved.ipaUs,
      ipaUk: resolved.ipaUk,
      pos: resolved.displayPos,
      vi: resolved.displayMeaning,
    );
  }

  /// Dual-Resolution lookup: keeps exact IPA of [rawWord] while resolving
  /// full Vietnamese meaning from its base lemma if inflected.
  Future<DictionaryLookupResult?> lookupDual(String rawWord) async {
    final word = rawWord.trim().toLowerCase();
    if (word.isEmpty) return null;

    final initial = await dictionaryDatabase.lookupBatch([word]);
    final surfaceEntry = initial[word];

    final needsLemmaLookup = surfaceEntry == null ||
        surfaceEntry.vi.trim().isEmpty ||
        isCrossReference(surfaceEntry.vi);

    String? resolvedLemma;
    OfflineDictEntry? lemmaEntry;

    if (needsLemmaLookup) {
      final candidates = <String>[];

      // 1. Regex from Vietnamese cross-reference ("... của snap")
      if (surfaceEntry != null && surfaceEntry.vi.isNotEmpty) {
        final regexLemma = extractCrossReferenceLemma(surfaceEntry.vi);
        if (regexLemma != null && regexLemma != word) {
          candidates.add(regexLemma);
        }
      }

      // 2. Irregular lemmas table in offline_dict.db
      final irregulars = await dictionaryDatabase.lookupIrregularLemmas([word]);
      final irrLemma = irregulars[word];
      if (irrLemma != null &&
          irrLemma.isNotEmpty &&
          irrLemma != word &&
          !candidates.contains(irrLemma)) {
        candidates.add(irrLemma);
      }

      // 3. Suffix stripping rules (-ed, -ing, -s, -es, -ies, doubled consonant)
      for (final c in suffixCandidates(word)) {
        if (!candidates.contains(c)) candidates.add(c);
      }

      if (candidates.isNotEmpty) {
        final baseHits = await dictionaryDatabase.lookupBatch(candidates);
        for (final c in candidates) {
          final hit = baseHits[c];
          if (hit != null &&
              hit.vi.trim().isNotEmpty &&
              !isCrossReference(hit.vi)) {
            resolvedLemma = c;
            lemmaEntry = hit;
            break;
          }
        }
        // Fallback: accept any hit even if meaning is short
        if (lemmaEntry == null) {
          for (final c in candidates) {
            final hit = baseHits[c];
            if (hit != null) {
              resolvedLemma = c;
              lemmaEntry = hit;
              break;
            }
          }
        }
      }
    }

    if (surfaceEntry == null && lemmaEntry == null) return null;

    return DictionaryLookupResult(
      queryWord: word,
      surfaceEntry: surfaceEntry,
      lemmaWord: resolvedLemma,
      lemmaEntry: lemmaEntry,
    );
  }
}
