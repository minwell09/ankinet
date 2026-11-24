/// Utility for creating Cloze deletion sentences that always mask the actual
/// **surface form** appearing in the sentence, even when the flashcard stores
/// only the base lemma (e.g. card word = `run`, sentence contains `running` or `ran`).
class ClozeMasker {
  static const String placeholder = '[...]';

  /// Built-in reverse index of common irregular lemmas -> inflected surface forms.
  /// Additional irregulars from `nlp_bundle.json` / `offline_dict.db` can be
  /// registered dynamically via [registerIrregularSurfaceToLemmaMap].
  static final Map<String, Set<String>> _lemmaToIrregularSurfaces = {
    'be': {'am', 'is', 'are', 'was', 'were', 'been', 'being'},
    'go': {'went', 'gone', 'goes', 'going'},
    'run': {'ran', 'running', 'runs'},
    'have': {'had', 'has', 'having'},
    'do': {'did', 'does', 'done', 'doing'},
    'write': {'wrote', 'written', 'writing', 'writes'},
    'speak': {'spoke', 'spoken', 'speaking', 'speaks'},
    'take': {'took', 'taken', 'taking', 'takes'},
    'give': {'gave', 'given', 'giving', 'gives'},
    'see': {'saw', 'seen', 'seeing', 'sees'},
    'know': {'knew', 'known', 'knowing', 'knows'},
    'think': {'thought', 'thinking', 'thinks'},
    'bring': {'brought', 'bringing', 'brings'},
    'buy': {'bought', 'buying', 'buys'},
    'teach': {'taught', 'teaching', 'teaches'},
    'catch': {'caught', 'catching', 'catches'},
    'seek': {'sought', 'seeking', 'seeks'},
    'fight': {'fought', 'fighting', 'fights'},
    'build': {'built', 'building', 'builds'},
    'send': {'sent', 'sending', 'sends'},
    'spend': {'spent', 'spending', 'spends'},
    'lend': {'lent', 'lending', 'lends'},
    'mean': {'meant', 'meaning', 'means'},
    'keep': {'kept', 'keeping', 'keeps'},
    'sleep': {'slept', 'sleeping', 'sleeps'},
    'feel': {'felt', 'feeling', 'feels'},
    'leave': {'left', 'leaving', 'leaves'},
    'lose': {'lost', 'losing', 'loses'},
    'find': {'found', 'finding', 'finds'},
    'hold': {'held', 'holding', 'holds'},
    'tell': {'told', 'telling', 'tells'},
    'sell': {'sold', 'selling', 'sells'},
    'lead': {'led', 'leading', 'leads'},
    'meet': {'met', 'meeting', 'meets'},
    'win': {'won', 'winning', 'wins'},
    'begin': {'began', 'begun', 'beginning', 'begins'},
    'become': {'became', 'becoming', 'becomes'},
    'come': {'came', 'coming', 'comes'},
    'overcome': {'overcame', 'overcoming', 'overcomes'},
    'break': {'broke', 'broken', 'breaking', 'breaks'},
    'choose': {'chose', 'chosen', 'choosing', 'chooses'},
    'drive': {'drove', 'driven', 'driving', 'drives'},
    'eat': {'ate', 'eaten', 'eating', 'eats'},
    'fall': {'fell', 'fallen', 'falling', 'falls'},
    'fly': {'flew', 'flown', 'flying', 'flies'},
    'forget': {'forgot', 'forgotten', 'forgetting', 'forgets'},
    'forgive': {'forgave', 'forgiven', 'forgiving', 'forgives'},
    'freeze': {'froze', 'frozen', 'freezing', 'freezes'},
    'grow': {'grew', 'grown', 'growing', 'grows'},
    'hide': {'hid', 'hidden', 'hiding', 'hides'},
    'ride': {'rode', 'ridden', 'riding', 'rides'},
    'rise': {'rose', 'risen', 'rising', 'rises'},
    'shake': {'shook', 'shaken', 'shaking', 'shakes'},
    'show': {'showed', 'shown', 'showing', 'shows'},
    'steal': {'stole', 'stolen', 'stealing', 'steals'},
    'throw': {'threw', 'thrown', 'throwing', 'throws'},
    'wear': {'wore', 'worn', 'wearing', 'wears'},
    'understand': {'understood', 'understanding', 'understands'},
    'child': {'children'},
    'man': {'men'},
    'woman': {'women'},
    'mouse': {'mice'},
    'tooth': {'teeth'},
    'foot': {'feet'},
    'person': {'people'},
    'phenomenon': {'phenomena'},
    'criterion': {'criteria'},
    'analysis': {'analyses'},
    'hypothesis': {'hypotheses'},
    'thesis': {'theses'},
    'crisis': {'crises'},
    'matrix': {'matrices'},
    'index': {'indices', 'indexes'},
    'leaf': {'leaves'},
    'life': {'lives'},
    'knife': {'knives'},
    'wolf': {'wolves'},
  };

  /// Registers a `surface -> lemma` map (e.g. from WordNet 5,500+ irregulars)
  /// into the reverse `lemma -> {surfaces}` index.
  static void registerIrregularSurfaceToLemmaMap(Map<String, dynamic> surfaceToLemma) {
    surfaceToLemma.forEach((surface, lemmaObj) {
      final s = surface.trim().toLowerCase();
      final l = lemmaObj.toString().trim().toLowerCase();
      if (s.isNotEmpty && l.isNotEmpty && s != l) {
        _lemmaToIrregularSurfaces.putIfAbsent(l, () => <String>{}).add(s);
      }
    });
  }

  /// Masks the surface form of [word] (or any inflected form of [lemma] / [word])
  /// inside [sentence] with `[...]`.
  static String maskSentence({
    required String sentence,
    required String word,
    String lemma = '',
  }) {
    final trimmedSentence = sentence.trim();
    if (trimmedSentence.isEmpty) return '';

    final cleanWord = word.trim().toLowerCase();
    final cleanLemma = lemma.trim().toLowerCase();
    if (cleanWord.isEmpty && cleanLemma.isEmpty) return trimmedSentence;

    // 1. Build regex matching exact surface word, irregular surface variants,
    // and regular morphological inflections of the word/lemma.
    final pattern = buildSurfaceRegex(word: cleanWord, lemma: cleanLemma);
    if (pattern != null && pattern.hasMatch(trimmedSentence)) {
      return trimmedSentence.replaceAll(pattern, placeholder);
    }

    // 2. Fallback for CJK / multi-character tokens without word boundaries
    final target = cleanWord.isNotEmpty ? cleanWord : cleanLemma;
    final looseRegex = RegExp(RegExp.escape(target), caseSensitive: false);
    if (looseRegex.hasMatch(trimmedSentence)) {
      return trimmedSentence.replaceAll(looseRegex, placeholder);
    }

    return trimmedSentence;
  }

  /// Returns true if [clozeSentence] still exposes any unmasked surface form
  /// of [word] or [lemma].
  static bool containsUnmaskedSurfaceForm({
    required String clozeSentence,
    required String word,
    String lemma = '',
  }) {
    if (clozeSentence.trim().isEmpty) return false;
    final regex = buildSurfaceRegex(
      word: word.trim().toLowerCase(),
      lemma: lemma.trim().toLowerCase(),
    );
    if (regex == null) return false;
    return regex.hasMatch(clozeSentence);
  }

  /// Builds a word-boundary [RegExp] that matches [word], [lemma], any known
  /// irregular surface forms, and regular English inflections (e.g. `run` -> `running`).
  static RegExp? buildSurfaceRegex({
    required String word,
    String lemma = '',
  }) {
    final bases = <String>{
      if (word.isNotEmpty) word,
      if (lemma.isNotEmpty) lemma,
    };
    if (bases.isEmpty) return null;

    // Also include reverse lookup if `word` itself is an irregular surface form
    for (final entry in _lemmaToIrregularSurfaces.entries) {
      if (bases.contains(entry.key) || entry.value.any(bases.contains)) {
        bases.add(entry.key);
      }
    }

    final exactForms = <String>{...bases};
    final stems = <String>{};

    for (final b in bases) {
      final irr = _lemmaToIrregularSurfaces[b];
      if (irr != null) {
        exactForms.addAll(irr);
      }

      if (RegExp(r'^[a-z]+$').hasMatch(b) && b.length >= 2) {
        stems.add(b);
        // Consonant doubling: run -> runn(ing), stop -> stopp(ed)
        final lastChar = b[b.length - 1];
        if (!'aeiouwy'.contains(lastChar)) {
          stems.add('$b$lastChar');
        }
        // Silent -e drop: create -> creat(ing), make -> mak(ing)
        if (b.endsWith('e') && b.length >= 3) {
          stems.add(b.substring(0, b.length - 1));
        }
        // -y -> -i: study -> studi(es/ed), happy -> happi(er/est/ly)
        if (b.endsWith('y') && b.length >= 3) {
          stems.add('${b.substring(0, b.length - 1)}i');
        }
        // -f / -fe -> -v: leaf -> leav(es), wolf -> wolv(es)
        if (b.endsWith('f') && b.length >= 3) {
          stems.add('${b.substring(0, b.length - 1)}v');
        } else if (b.endsWith('fe') && b.length >= 4) {
          stems.add('${b.substring(0, b.length - 2)}v');
        }
      }
    }

    // Sort longest first so regex engine prefers full matches
    final sortedExact = exactForms.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final sortedStems = stems.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    final parts = <String>[
      ...sortedExact.map(RegExp.escape),
      if (sortedStems.isNotEmpty)
        '(?:${sortedStems.map(RegExp.escape).join('|')})(?:s|es|d|ed|ing|er|ers|or|ors|est|ly|ment|ments|tion|tions|sion|sions|ness|ity|ities|able|ible|ive|al)?',
    ];

    if (parts.isEmpty) return null;
    return RegExp(
      '\\b(?:${parts.join('|')})\\b',
      caseSensitive: false,
    );
  }
}
