import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/local_database.dart';
import '../../../../core/database/offline_dictionary_database.dart';
import '../../../../core/utils/cloze_masker.dart';
import '../models/extracted_token_model.dart';

enum LearningLanguageMode {
  englishForVietnamese, // EN -> VI with live IPA & English Roots/Prefixes/Suffixes
  cjkRadicals, // Hanzi/Kanji -> Pinyin & Radicals
}

abstract class NlpAnalyzerDataSource {
  Future<List<ExtractedTokenModel>> tokenizeAndAnalyze(
    String rawText, {
    LearningLanguageMode mode = LearningLanguageMode.englishForVietnamese,
    bool enableOnlineLookup = true,
  });
}

class _IsolateAnalyzePayload {
  final String rawText;
  final String modeName;
  final Map<String, dynamic> bundle;

  const _IsolateAnalyzePayload({
    required this.rawText,
    required this.modeName,
    required this.bundle,
  });
}

/// Top-level function executed inside a background isolate via [compute]
/// to prevent UI frame drops when tokenizing & decomposing long articles.
List<Map<String, dynamic>> _tokenizeAndDecomposeInIsolate(
  _IsolateAnalyzePayload payload,
) {
  final rawText = payload.rawText.trim();
  if (rawText.isEmpty) return const [];

  if (payload.modeName == LearningLanguageMode.cjkRadicals.name) {
    return _analyzeCjkInIsolate(rawText);
  }

  final offlineDict =
      (payload.bundle['offline_dict'] as Map<String, dynamic>?) ?? const {};
  final irregulars =
      (payload.bundle['irregular_lemmas'] as Map<String, dynamic>?) ?? const {};
  final prefixes =
      (payload.bundle['prefixes'] as Map<String, dynamic>?) ?? _defaultPrefixes;
  final roots =
      (payload.bundle['roots'] as Map<String, dynamic>?) ?? _defaultRoots;
  final suffixes =
      (payload.bundle['suffixes'] as Map<String, dynamic>?) ?? _defaultSuffixes;

  ClozeMasker.registerIrregularSurfaceToLemmaMap(irregulars);

  // Split text into sentences so every card stores its exact contextual sentence
  final sentences = rawText
      .split(RegExp(r'(?<=[.!?。\n])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final effectiveSentences = sentences.isEmpty ? [rawText] : sentences;

  final seen = <String>{};
  final results = <Map<String, dynamic>>[];

  for (final sentence in effectiveSentences) {
    final matches = RegExp(r"[A-Za-z]{3,}").allMatches(sentence);
    for (final m in matches) {
      final surface = m.group(0)!.toLowerCase();
      if (_stopWords.contains(surface)) continue;
      if (!seen.add(surface)) continue;

      final lemma = _lemmatizeWord(
        surface,
        irregulars: irregulars,
        offlineDict: offlineDict,
      );

      final radicals = _decomposeMorphology(
        surface,
        lemma: lemma,
        prefixes: prefixes,
        roots: roots,
        suffixes: suffixes,
        offlineDict: offlineDict,
      );

      final dictEntry =
          (offlineDict[surface] ?? offlineDict[lemma]) as Map<String, dynamic>?;
      final bool inCoreBundle = dictEntry != null;

      final String ipaUs = (dictEntry?['ipa_us'] as String?) ?? '';
      final String ipaUk = (dictEntry?['ipa_uk'] as String?) ?? '';
      final String ipa = (dictEntry?['ipa'] as String?) ??
          (ipaUs.isNotEmpty
              ? ipaUs
              : (ipaUk.isNotEmpty ? ipaUk : _fallbackG2pIpa(surface)));
      final String pos =
          (dictEntry?['pos'] as String?) ?? _inferPos(surface);
      final String viMeaning = (dictEntry?['vi'] as String?) ??
          _synthesizeVietnamese(surface, pos, radicals);

      // Mask the exact surface form (and any inflected form of lemma) in the sentence
      final clozeSentence = ClozeMasker.maskSentence(
        sentence: sentence,
        word: surface,
        lemma: lemma,
      );

      results.add({
        'surface_word': surface,
        'lemma': lemma,
        'phonetic': ipa,
        'phonetic_us': ipaUs,
        'phonetic_uk': ipaUk,
        'translation': viMeaning,
        'pos': pos,
        'source_sentence': sentence,
        'cloze_sentence': clozeSentence,
        'audio_url': '',
        'radicals': radicals,
        'is_from_offline_bundle': inCoreBundle,
      });

      if (results.length >= 40) break;
    }
    if (results.length >= 40) break;
  }

  return results;
}

List<Map<String, dynamic>> _analyzeCjkInIsolate(String rawText) {
  final sentences = rawText
      .split(RegExp(r'(?<=[。！？.!?\n])\s*'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final effectiveSentences = sentences.isEmpty ? [rawText] : sentences;
  final seen = <String>{};
  final results = <Map<String, dynamic>>[];

  for (final sentence in effectiveSentences) {
    final matches = RegExp(r'[\u4e00-\u9fff]{1,4}').allMatches(sentence);
    for (final m in matches) {
      final token = m.group(0)!;
      if (!seen.add(token)) continue;
      final radicals = token.split('').map((ch) {
        return {
          'symbol': ch,
          'meaning': _cjkCharHint[ch] ?? 'Hán tự / bộ thủ ($ch)',
          'stroke_count': 0,
        };
      }).toList();
      final cloze = sentence.replaceFirst(token, '[...]');
      results.add({
        'surface_word': token,
        'lemma': token,
        'phonetic': _cjkPinyinHint[token] ?? token,
        'translation': _cjkMeaningHint[token] ?? '(Từ Hán) $token',
        'pos': 'hanzi',
        'source_sentence': sentence,
        'cloze_sentence': cloze,
        'audio_url': '',
        'radicals': radicals,
        'is_from_offline_bundle': _cjkMeaningHint.containsKey(token),
      });
      if (results.length >= 30) break;
    }
  }
  return results;
}

const Map<String, String> _cjkPinyinHint = {
  '森林': 'sēn lín',
  '清澈': 'qīng chè',
  '休息': 'xiū xi',
  '树下': 'shù xià',
};

const Map<String, String> _cjkMeaningHint = {
  '森林': '(n.) rừng rậm (bộ Mộc 木)',
  '清澈': '(adj.) trong vắt, trong trẻo (bộ Thủy 氵)',
  '休息': '(v.) nghỉ ngơi (bộ Nhân 亻 + Mộc 木)',
  '树下': '(n.) dưới gốc cây',
};

const Map<String, String> _cjkCharHint = {
  '森': 'Mộc (木×3): rừng cây rậm rạp',
  '林': 'Mộc (木×2): rừng cây',
  '清': 'Thủy (氵) + Thanh (青): nước trong',
  '澈': 'Thủy (氵): trong suốt tới đáy',
  '休': 'Nhân (亻) tựa vào Mộc (木): nghỉ ngơi',
  '息': 'Tự (自) + Tâm (心): hơi thở, nghỉ',
  '树': 'Mộc (木): cây cối',
  '下': 'Hạ: bên dưới',
};

String _lemmatizeWord(
  String w, {
  required Map<String, dynamic> irregulars,
  required Map<String, dynamic> offlineDict,
}) {
  final irr = irregulars[w] as String?;
  if (irr != null && irr.isNotEmpty) return irr;

  if (offlineDict.containsKey(w) &&
      !w.endsWith('ed') &&
      !w.endsWith('ing') &&
      !w.endsWith('s')) {
    return w;
  }

  final candidates = <String>[];
  if (w.endsWith('ies') && w.length > 4) {
    candidates.add('${w.substring(0, w.length - 3)}y');
  }
  if (w.endsWith('ied') && w.length > 4) {
    candidates.add('${w.substring(0, w.length - 3)}y');
  }
  if (w.endsWith('ves') && w.length > 4) {
    candidates.add('${w.substring(0, w.length - 3)}f');
    candidates.add('${w.substring(0, w.length - 3)}fe');
  }
  if (w.endsWith('ing') && w.length > 5) {
    final stem = w.substring(0, w.length - 3);
    candidates.add(stem);
    candidates.add('${stem}e');
    if (stem.length >= 3 &&
        stem[stem.length - 1] == stem[stem.length - 2]) {
      candidates.add(stem.substring(0, stem.length - 1));
    }
  }
  if (w.endsWith('ed') && w.length > 4) {
    final stem = w.substring(0, w.length - 2);
    candidates.add(stem);
    candidates.add(w.substring(0, w.length - 1));
    if (stem.length >= 3 &&
        stem[stem.length - 1] == stem[stem.length - 2]) {
      candidates.add(stem.substring(0, stem.length - 1));
    }
  }
  if (w.endsWith('es') && w.length > 4) {
    candidates.add(w.substring(0, w.length - 2));
    candidates.add(w.substring(0, w.length - 1));
  }
  if (w.endsWith('s') &&
      !w.endsWith('ss') &&
      !w.endsWith('us') &&
      !w.endsWith('is') &&
      w.length > 3) {
    candidates.add(w.substring(0, w.length - 1));
  }

  for (final c in candidates) {
    if (offlineDict.containsKey(c) || irregulars.containsValue(c)) return c;
  }
  return candidates.isNotEmpty ? candidates.first : w;
}

const Set<String> _commonBaseStems = {
  'wood', 'gold', 'wool', 'silk', 'earth', 'dark', 'soft', 'hard', 'sharp',
  'short', 'wide', 'deep', 'broad', 'sweet', 'bright', 'light', 'tight',
  'loose', 'weak', 'thick', 'quick', 'fresh', 'glad', 'sad', 'mad', 'red',
  'black', 'white', 'flat', 'even', 'open', 'broken', 'strength', 'length',
  'fright', 'threat', 'haste', 'less', 'worse', 'awake', 'fall', 'rise',
  'write', 'speak', 'take', 'give', 'eat', 'drive', 'ride', 'freeze', 'steal',
  'choose', 'forget', 'forgive', 'fish', 'fisher', 'fire', 'water', 'sea',
  'sun', 'moon', 'star', 'hand', 'foot', 'head', 'heart', 'home', 'house',
  'work', 'play', 'time', 'life', 'book', 'note', 'road', 'way', 'day',
  'night', 'rain', 'snow', 'wind', 'weather', 'harbor', 'ferry', 'rope',
  'police', 'chair', 'gentle', 'craft', 'sales', 'business', 'spokes',
  'watch', 'guard', 'port', 'spect', 'struct', 'dict', 'form', 'tract',
};

const Map<String, String> _compoundTailRoots = {
  'men': 'man',
  'man': 'man',
  'women': 'woman',
  'woman': 'woman',
  'work': 'work',
  'land': 'land',
  'boat': 'boat',
  'ship': 'ship',
  'house': 'house',
  'light': 'light',
  'water': 'water',
  'wood': 'wood',
  'side': 'side',
  'line': 'line',
  'time': 'time',
  'keeper': 'keep',
  'maker': 'make',
  'holder': 'hold',
  'fighter': 'fight',
};

bool _isKnownEnglishStem(
  String stem,
  Map<String, dynamic> offlineDict,
  Map<String, dynamic> roots,
) {
  if (stem.length < 3) return false;
  if (_commonBaseStems.contains(stem) || offlineDict.containsKey(stem)) {
    return true;
  }
  // Silent-e restoration (e.g., mak + er -> make, us + able -> use)
  if (offlineDict.containsKey('${stem}e') ||
      _commonBaseStems.contains('${stem}e')) {
    return true;
  }
  // Doubled final consonant (e.g., runn + er -> run, flatt + en -> flat)
  if (stem.length >= 4 && stem[stem.length - 1] == stem[stem.length - 2]) {
    final undoubled = stem.substring(0, stem.length - 1);
    if (offlineDict.containsKey(undoubled) ||
        _commonBaseStems.contains(undoubled)) {
      return true;
    }
  }
  // y -> i alternation (e.g., happi + ness -> happy)
  if (stem.endsWith('i') && stem.length >= 4) {
    final yForm = '${stem.substring(0, stem.length - 1)}y';
    if (offlineDict.containsKey(yForm) || _commonBaseStems.contains(yForm)) {
      return true;
    }
  }
  // Valid Greco-Latin root of length >= 4 at the start/end of stem (e.g., perspect, struct, port)
  for (final root in roots.keys) {
    if (root.length >= 4 &&
        (stem == root || stem.startsWith(root) || stem.endsWith(root))) {
      return true;
    }
  }
  return false;
}

List<Map<String, dynamic>> _decomposeMorphology(
  String word, {
  required String lemma,
  required Map<String, dynamic> prefixes,
  required Map<String, dynamic> roots,
  required Map<String, dynamic> suffixes,
  Map<String, dynamic> offlineDict = const {},
}) {
  final target = (lemma.isNotEmpty ? lemma : word).toLowerCase().trim();
  final surfaceLower = word.toLowerCase().trim();
  final components = <Map<String, dynamic>>[];
  final addedSymbols = <String>{};

  void addComponent(String symbol, String meaning) {
    if (addedSymbols.add(symbol)) {
      components.add({
        'symbol': symbol,
        'meaning': meaning,
        'stroke_count': 0,
      });
    }
  }

  // 1. Compound nouns & irregular compound plurals (e.g., fishermen -> fish + man)
  // Check both surface and lemma so irregular plurals like fishermen/fisherman are caught cleanly.
  for (final candidate in {target, surfaceLower}) {
    if (candidate.length < 6) continue;
    for (final tailEntry in _compoundTailRoots.entries) {
      final tail = tailEntry.key;
      final canonicalTail = tailEntry.value;
      if (candidate.endsWith(tail) && candidate.length >= tail.length + 3) {
        final left = candidate.substring(0, candidate.length - tail.length);
        // Handle linker -er- in compounds like fisher+men -> fish + man
        String? validLeft;
        if (left.endsWith('er') &&
            left.length >= 5 &&
            _isKnownEnglishStem(
              left.substring(0, left.length - 2),
              offlineDict,
              const {},
            )) {
          validLeft = left.substring(0, left.length - 2);
        } else if (left.length >= 3 &&
            _isKnownEnglishStem(left, offlineDict, const {})) {
          validLeft = left;
        }
        if (validLeft != null) {
          addComponent(validLeft, 'gốc từ ghép: $validLeft');
          addComponent(canonicalTail, 'gốc từ ghép: $canonicalTail');
          return components;
        }
      }
    }
  }

  // 2. Anchored & stem-validated prefix extraction (longest-first on lemma)
  String coreStem = target;
  final sortedPrefixes = prefixes.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  String? matchedPrefix;
  for (final entry in sortedPrefixes) {
    final p = entry.key;
    if (target.startsWith(p) && target.length >= p.length + 3) {
      final remainder = target.substring(p.length);
      if (_isKnownEnglishStem(remainder, offlineDict, roots)) {
        matchedPrefix = p;
        coreStem = remainder;
        addComponent('$p-', entry.value.toString());
        break;
      }
    }
  }

  // 3. Anchored & stem-validated suffix extraction (longest-first on lemma)
  final sortedSuffixes = suffixes.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  String? matchedSuffix;
  for (final entry in sortedSuffixes) {
    final s = entry.key;
    if (coreStem.endsWith(s) && coreStem.length >= s.length + 3) {
      final stripped = coreStem.substring(0, coreStem.length - s.length);
      if (_isKnownEnglishStem(stripped, offlineDict, roots)) {
        matchedSuffix = s;
        coreStem = stripped;
        addComponent('-$s', entry.value.toString());
        break;
      }
    }
  }

  // 4. Boundary-aligned Greco-Latin root extraction (no naive interior substring collisions)
  final sortedRoots = roots.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  final matchedRootKeys = <String>[];

  for (final entry in sortedRoots) {
    final r = entry.key;
    if (matchedRootKeys.length >= 2) break;
    // Skip shorter sub-root if a longer overlapping root already matched (e.g., spec after spect)
    if (matchedRootKeys.any((existing) => existing.contains(r))) continue;

    final bool boundaryMatch;
    if (r.length >= 4) {
      // 4+ char Greco-Latin root must align to a morpheme boundary of the stripped coreStem
      boundaryMatch = coreStem == r ||
          coreStem.startsWith(r) ||
          coreStem.endsWith(r);
    } else if (r.length == 3) {
      // 3-char roots (bio, geo, vis, act, gen) ONLY match if exact stem or
      // prefix-aligned with a validated affix — never random interior substrings like fis[her]men!
      boundaryMatch = coreStem == r ||
          ((matchedPrefix != null || matchedSuffix != null) &&
              (coreStem.startsWith(r) || coreStem.endsWith(r)) &&
              coreStem.length <= r.length + 3);
    } else {
      boundaryMatch = false;
    }

    if (boundaryMatch) {
      matchedRootKeys.add(r);
      addComponent('-$r-', entry.value.toString());
    }
  }

  // 5. Fallback: preserve the clean base stem rather than slicing arbitrary characters
  if (components.isEmpty && target.isNotEmpty) {
    addComponent(target, 'gốc từ vựng ($target)');
  }

  return components;
}

String _inferPos(String word) {
  if (word.endsWith('tion') ||
      word.endsWith('sion') ||
      word.endsWith('ment') ||
      word.endsWith('ness') ||
      word.endsWith('ity') ||
      word.endsWith('ance') ||
      word.endsWith('ence')) {
    return 'noun';
  }
  if (word.endsWith('able') ||
      word.endsWith('ible') ||
      word.endsWith('ous') ||
      word.endsWith('ive') ||
      word.endsWith('al') ||
      word.endsWith('ful') ||
      word.endsWith('less') ||
      word.endsWith('ic')) {
    return 'adj';
  }
  if (word.endsWith('ly')) return 'adv';
  if (word.endsWith('ize') ||
      word.endsWith('ise') ||
      word.endsWith('ify') ||
      word.endsWith('ate') ||
      word.endsWith('ed') ||
      word.endsWith('ing')) {
    return 'verb';
  }
  return 'vocab';
}

String _synthesizeVietnamese(
  String word,
  String pos,
  List<Map<String, dynamic>> radicals,
) {
  final parts = radicals.map((r) => r['meaning']).join(' + ');
  return '($pos) $parts';
}

String _fallbackG2pIpa(String word) {
  String p = word.toLowerCase();
  p = p
      .replaceAll('tion', 'ʃən')
      .replaceAll('sion', 'ʒən')
      .replaceAll('ture', 'tʃər')
      .replaceAll('ough', 'oʊ')
      .replaceAll('igh', 'aɪ')
      .replaceAll('ph', 'f')
      .replaceAll('sh', 'ʃ')
      .replaceAll('ch', 'tʃ')
      .replaceAll('th', 'θ')
      .replaceAll('qu', 'kw')
      .replaceAll('ck', 'k')
      .replaceAll('ee', 'iː')
      .replaceAll('ea', 'iː')
      .replaceAll('oo', 'uː')
      .replaceAll('ou', 'aʊ')
      .replaceAll('ow', 'aʊ')
      .replaceAll('ai', 'eɪ')
      .replaceAll('ay', 'eɪ')
      .replaceAll('oi', 'ɔɪ')
      .replaceAll('oy', 'ɔɪ')
      .replaceAll('au', 'ɔː')
      .replaceAll('aw', 'ɔː')
      .replaceAll('er', 'ər')
      .replaceAll('ir', 'ɜːr')
      .replaceAll('ur', 'ɜːr')
      .replaceAll('ar', 'ɑːr')
      .replaceAll('or', 'ɔːr')
      .replaceAll('ing', 'ɪŋ');
  return '/$p/';
}

const Set<String> _stopWords = {
  'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'any', 'can',
  'had', 'her', 'was', 'one', 'our', 'out', 'day', 'get', 'has', 'him',
  'his', 'how', 'man', 'new', 'now', 'old', 'see', 'two', 'way', 'who',
  'boy', 'did', 'its', 'let', 'put', 'say', 'she', 'too', 'use', 'that',
  'with', 'have', 'this', 'will', 'your', 'from', 'they', 'know', 'want',
  'been', 'good', 'much', 'some', 'time', 'very', 'when', 'come', 'here',
  'just', 'like', 'long', 'make', 'many', 'more', 'only', 'over', 'such',
  'take', 'than', 'them', 'well', 'were', 'what', 'into', 'about', 'after',
  'also', 'back', 'even', 'most', 'must', 'said', 'same', 'then', 'there',
  'these', 'their', 'those', 'through', 'under', 'where', 'which', 'while',
  'would', 'could', 'should', 'other', 'every', 'first', 'still', 'being',
};

const Map<String, String> _defaultPrefixes = {
  'trans': 'tiền tố: vượt qua, chuyển đổi',
  'inter': 'tiền tố: giữa các bên, liên kết',
  'super': 'tiền tố: siêu, vượt trội',
  'under': 'tiền tố: bên dưới, chưa đủ',
  'over': 'tiền tố: quá mức, phía trên',
  'anti': 'tiền tố: chống lại, kháng',
  'auto': 'tiền tố: tự động, bản thân',
  'pre': 'tiền tố: trước (before)',
  'pro': 'tiền tố: hướng về phía trước',
  'sub': 'tiền tố: bên dưới, phụ',
  'con': 'tiền tố: cùng nhau (together)',
  'com': 'tiền tố: cùng nhau (together)',
  'dis': 'tiền tố: không, tách rời',
  'un': 'tiền tố: không, ngược lại',
  're': 'tiền tố: làm lại / quay lại',
  'in': 'tiền tố: vào trong / không',
  'im': 'tiền tố: vào trong / không',
  'de': 'tiền tố: giảm xuống, loại bỏ',
  'ex': 'tiền tố: đưa ra ngoài (out)',
};

const Map<String, String> _defaultRoots = {
  'spect': 'gốc: nhìn, quan sát (look/see)',
  'spec': 'gốc: nhìn, đặc tính (look)',
  'port': 'gốc: mang, vận chuyển (carry)',
  'struct': 'gốc: xây dựng, kết cấu (build)',
  'dict': 'gốc: nói, tuyên bố (say/speak)',
  'scrib': 'gốc: viết, ghi chép (write)',
  'script': 'gốc: văn bản, chữ viết (write)',
  'graph': 'gốc: viết, biểu đồ',
  'phon': 'gốc: âm thanh, giọng nói',
  'form': 'gốc: hình thái, định hình (shape)',
  'tract': 'gốc: kéo, thu hút (pull/draw)',
  'press': 'gốc: ấn, ép (press)',
  'cred': 'gốc: tin tưởng (believe)',
  'cogn': 'gốc: nhận thức, biết (know)',
  'duc': 'gốc: dẫn dắt (lead)',
};

const Map<String, String> _defaultSuffixes = {
  'tion': 'hậu tố (n.): sự việc, quá trình',
  'sion': 'hậu tố (n.): sự việc, trạng thái',
  'ment': 'hậu tố (n.): kết quả / hành động',
  'ness': 'hậu tố (n.): phẩm chất, trạng thái',
  'ity': 'hậu tố (n.): tính chất, năng lực',
  'able': 'hậu tố (adj.): có thể',
  'ible': 'hậu tố (adj.): có thể',
  'ous': 'hậu tố (adj.): đầy, có tính chất',
  'ive': 'hậu tố (adj.): có xu hướng',
  'ful': 'hậu tố (adj.): đầy, nhiều',
  'less': 'hậu tố (adj.): không có',
  'ize': 'hậu tố (v.): làm cho trở thành',
  'ify': 'hậu tố (v.): hóa, làm cho',
  'ly': 'hậu tố (adv.): một cách...',
  'er': 'hậu tố (n./adj.): người/vật thực hiện',
  'or': 'hậu tố (n.): người/thiết bị thực hiện',
  'al': 'hậu tố (adj.): thuộc về',
};

/// Multi-Tier Hybrid NLP Analyzer Datasource:
/// 1. **Isolate Morphology & Lemmatization**: Runs sentence splitting, tokenization,
///    5,519 WordNet irregular lemmatization, surface-form Cloze generation, and
///    288 Greek/Latin root decomposition inside `compute()`.
/// 2. **Dedicated SQLite Offline Dictionary (`assets/nlp/offline_dict.db`)**:
///    Queries 185,189 English headwords (104,717 EN-VI CC BY-SA 4.0 meanings +
///    185,189 Wiktionary/CMUdict IPA pronunciations) via indexed SQLite `WHERE word IN (...)`
///    without parsing large JSON files into memory.
/// 3. **Context-Aware API / LLM Pipeline (`Sentence + Glossary -> dict_cache(word, sentence_hash)`)**:
///    Checks `dict_cache` by `(word, sentence_hash)` first; for uncached/contextual words,
///    sends the full sentence + offline glossary/morpheme hints to Gemini LLM (if API key configured)
///    or Google Translate GTX + Dictionary API, and caches the result keyed by `(word, sentence_hash)`.
class HybridNlpAnalyzerDataSourceImpl implements NlpAnalyzerDataSource {
  final Dio _dio;
  final LocalDatabase? localDatabase;
  final OfflineDictionaryDatabase _offlineDictDb;

  Map<String, dynamic>? _cachedBundle;

  HybridNlpAnalyzerDataSourceImpl({
    Dio? dio,
    this.localDatabase,
    OfflineDictionaryDatabase? offlineDictionaryDatabase,
  })  : _offlineDictDb =
            offlineDictionaryDatabase ?? OfflineDictionaryDatabase(),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 4),
              ),
            );

  /// Computes a deterministic 12-char MD5 hash of the normalized source sentence
  /// so `dict_cache` keys translations by `(word, sentence_hash)`.
  static String computeSentenceHash(String sentence) {
    final norm =
        sentence.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (norm.isEmpty) return '';
    return md5.convert(utf8.encode(norm)).toString().substring(0, 12);
  }

  Future<Map<String, dynamic>> _loadBundle() async {
    if (_cachedBundle != null) return _cachedBundle!;
    try {
      final raw = await rootBundle.loadString('assets/nlp/nlp_bundle.json');
      _cachedBundle = jsonDecode(raw) as Map<String, dynamic>;
      final irregulars =
          (_cachedBundle!['irregular_lemmas'] as Map<String, dynamic>?) ??
              const {};
      ClozeMasker.registerIrregularSurfaceToLemmaMap(irregulars);
    } catch (_) {
      _cachedBundle = const {};
    }
    return _cachedBundle!;
  }

  @override
  Future<List<ExtractedTokenModel>> tokenizeAndAnalyze(
    String rawText, {
    LearningLanguageMode mode = LearningLanguageMode.englishForVietnamese,
    bool enableOnlineLookup = true,
  }) async {
    final bundle = await _loadBundle();

    // 1. Run CPU-intensive tokenization + lemmatization + morphology in background isolate
    final rawMaps = await compute(
      _tokenizeAndDecomposeInIsolate,
      _IsolateAnalyzePayload(
        rawText: rawText,
        modeName: mode.name,
        bundle: bundle,
      ),
    );

    if (rawMaps.isEmpty) return const [];

    var tokens = rawMaps.map(ExtractedTokenModel.fromJson).toList();

    // 2. Enrich tokens from the dedicated 185,189-word SQLite Offline Dictionary (`assets/nlp/offline_dict.db`)
    if (mode == LearningLanguageMode.englishForVietnamese) {
      final lookupCandidates = <String>{
        for (final t in tokens) t.surfaceWord,
        for (final t in tokens)
          if (t.lemma.isNotEmpty) t.lemma,
      };
      final sqlEntries = await _offlineDictDb.lookupBatch(lookupCandidates);

      if (sqlEntries.isNotEmpty) {
        tokens = tokens.map((t) {
          final surfaceHit = sqlEntries[t.surfaceWord];
          final lemmaHit =
              t.lemma.isNotEmpty ? sqlEntries[t.lemma] : null;
          final bestVi = (surfaceHit != null && surfaceHit.vi.isNotEmpty)
              ? surfaceHit
              : ((lemmaHit != null && lemmaHit.vi.isNotEmpty)
                  ? lemmaHit
                  : null);
          final bestIpaUs = (surfaceHit != null && surfaceHit.ipaUs.isNotEmpty)
              ? surfaceHit.ipaUs
              : ((lemmaHit != null && lemmaHit.ipaUs.isNotEmpty)
                  ? lemmaHit.ipaUs
                  : t.phoneticUs);
          final bestIpaUk = (surfaceHit != null && surfaceHit.ipaUk.isNotEmpty)
              ? surfaceHit.ipaUk
              : ((lemmaHit != null && lemmaHit.ipaUk.isNotEmpty)
                  ? lemmaHit.ipaUk
                  : t.phoneticUk);
          final bestIpa = (surfaceHit != null && surfaceHit.ipa.isNotEmpty)
              ? surfaceHit.ipa
              : ((lemmaHit != null && lemmaHit.ipa.isNotEmpty)
                  ? lemmaHit.ipa
                  : (bestIpaUs.isNotEmpty
                      ? bestIpaUs
                      : (bestIpaUk.isNotEmpty ? bestIpaUk : t.phonetic)));

          // Correct lemma if the surface word itself is a base entry in the 104k EN-VI dictionary
          final effectiveLemma = (lemmaHit != null && lemmaHit.vi.isNotEmpty)
              ? t.lemma
              : ((surfaceHit != null && surfaceHit.vi.isNotEmpty)
                  ? t.surfaceWord
                  : t.lemma);

          if (bestVi != null) {
            return ExtractedTokenModel(
              surfaceWord: t.surfaceWord,
              lemma: effectiveLemma,
              phonetic: bestIpa,
              phoneticUs: bestIpaUs,
              phoneticUk: bestIpaUk,
              translation: bestVi.vi,
              partOfSpeech:
                  bestVi.pos != 'vocab' ? bestVi.pos : t.partOfSpeech,
              sourceSentence: t.sourceSentence,
              clozeSentence: ClozeMasker.maskSentence(
                sentence: t.sourceSentence,
                word: t.surfaceWord,
                lemma: effectiveLemma,
              ),
              audioUrl: t.audioUrl,
              radicals: t.radicals,
              isFromOfflineBundle: true,
            );
          } else if (bestIpa != t.phonetic ||
              bestIpaUs != t.phoneticUs ||
              bestIpaUk != t.phoneticUk) {
            return ExtractedTokenModel(
              surfaceWord: t.surfaceWord,
              lemma: effectiveLemma,
              phonetic: bestIpa,
              phoneticUs: bestIpaUs,
              phoneticUk: bestIpaUk,
              translation: t.translation,
              partOfSpeech: t.partOfSpeech,
              sourceSentence: t.sourceSentence,
              clozeSentence: t.clozeSentence,
              audioUrl: t.audioUrl,
              radicals: t.radicals,
              isFromOfflineBundle: t.isFromOfflineBundle,
            );
          }
          return t;
        }).toList();
      }
    }

    if (localDatabase == null) return tokens;

    final db = await localDatabase!.database;

    // 3. Check SQLite `dict_cache` keyed by `(word, sentence_hash)` (with fallback to `(word, '')`)
    final words = tokens.map((t) => t.surfaceWord).toList();
    final placeholders = List.filled(words.length, '?').join(',');
    final cachedRows = await db.query(
      'dict_cache',
      where: 'word IN ($placeholders)',
      whereArgs: words,
    );

    final cacheByCompositeKey = <String, Map<String, Object?>>{};
    for (final r in cachedRows) {
      final w = (r['word'] as String?) ?? '';
      final sh = (r['sentence_hash'] as String?) ?? '';
      cacheByCompositeKey['$w|$sh'] = r;
    }

    // Load optional Gemini API Key from app_settings for LLM contextual translation
    String geminiApiKey = '';
    try {
      final keyRows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: const ['gemini_api_key'],
        limit: 1,
      );
      if (keyRows.isNotEmpty) {
        geminiApiKey = ((keyRows.first['value'] as String?) ?? '').trim();
      }
    } catch (_) {}

    final enriched = <ExtractedTokenModel>[];
    final toFetchOnline = <int>[];

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final sHash = computeSentenceHash(t.sourceSentence);
      final cached = cacheByCompositeKey['${t.surfaceWord}|$sHash'] ??
          cacheByCompositeKey['${t.surfaceWord}|'];

      if (cached != null) {
        final cachedPhonetic = (cached['phonetic'] as String?) ?? '';
        final cachedPhoneticUs = (cached['phonetic_us'] as String?) ?? '';
        final cachedPhoneticUk = (cached['phonetic_uk'] as String?) ?? '';
        final cachedTranslation = (cached['translation'] as String?) ?? '';
        final cachedPos =
            (cached['part_of_speech'] as String?) ?? t.partOfSpeech;
        final cachedAudio = (cached['audio_url'] as String?) ?? '';
        enriched.add(
          ExtractedTokenModel(
            surfaceWord: t.surfaceWord,
            lemma: t.lemma,
            phonetic: cachedPhonetic.isNotEmpty ? cachedPhonetic : t.phonetic,
            phoneticUs:
                cachedPhoneticUs.isNotEmpty ? cachedPhoneticUs : t.phoneticUs,
            phoneticUk:
                cachedPhoneticUk.isNotEmpty ? cachedPhoneticUk : t.phoneticUk,
            translation: cachedTranslation.isNotEmpty
                ? cachedTranslation
                : t.translation,
            partOfSpeech: cachedPos,
            sourceSentence: t.sourceSentence,
            clozeSentence: t.clozeSentence,
            audioUrl: cachedAudio,
            radicals: t.radicals,
            isFromOfflineBundle: true,
          ),
        );
      } else {
        enriched.add(t);
        final needsOnline =
            (!t.isFromOfflineBundle || geminiApiKey.isNotEmpty) &&
                enableOnlineLookup &&
                toFetchOnline.length < 8;
        if (needsOnline) {
          toFetchOnline.add(i);
        }
      }
    }

    // 4. Context-Aware API / LLM Translation (sends full sentence + offline glossary)
    //    and persists results to `dict_cache` keyed by `(word, sentence_hash)`
    if (toFetchOnline.isNotEmpty &&
        mode == LearningLanguageMode.englishForVietnamese) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final cacheBatch = db.batch();

      await Future.wait(
        toFetchOnline.map((idx) async {
          final current = enriched[idx];
          final sHash = computeSentenceHash(current.sourceSentence);
          final glossaryHint = current.isFromOfflineBundle
              ? current.translation
              : current.radicals
                  .map((r) => '${r.symbol} (${r.meaning})')
                  .join(', ');

          final online = await _lookupContextualEnVi(
            word: current.surfaceWord,
            lemma: current.lemma,
            sentence: current.sourceSentence,
            glossaryHint: glossaryHint,
            geminiApiKey: geminiApiKey,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null);

          if (online != null) {
            final updatedUs = current.phoneticUs.isNotEmpty
                ? current.phoneticUs
                : (online['ipa_us'] ?? '');
            final updatedUk = current.phoneticUk.isNotEmpty
                ? current.phoneticUk
                : (online['ipa_uk'] ?? '');
            final updated = ExtractedTokenModel(
              surfaceWord: current.surfaceWord,
              lemma: current.lemma,
              phonetic: online['ipa']!.isNotEmpty
                  ? online['ipa']!
                  : current.phonetic,
              phoneticUs: updatedUs,
              phoneticUk: updatedUk,
              translation: online['translation']!.isNotEmpty
                  ? online['translation']!
                  : current.translation,
              partOfSpeech: online['pos']!.isNotEmpty
                  ? online['pos']!
                  : current.partOfSpeech,
              sourceSentence: current.sourceSentence,
              clozeSentence: current.clozeSentence,
              audioUrl: online['audio'] ?? '',
              radicals: current.radicals,
              isFromOfflineBundle: true,
            );
            enriched[idx] = updated;
            cacheBatch.insert(
              'dict_cache',
              {
                'word': updated.surfaceWord,
                'sentence_hash': sHash,
                'context_sentence': updated.sourceSentence,
                'lemma': updated.lemma,
                'phonetic': updated.phonetic,
                'phonetic_us': updated.phoneticUs,
                'phonetic_uk': updated.phoneticUk,
                'translation': updated.translation,
                'part_of_speech': updated.partOfSpeech,
                'audio_url': updated.audioUrl,
                'radicals_json': jsonEncode(
                  updated.radicals.map((r) => r.toJson()).toList(),
                ),
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }),
      ).timeout(const Duration(seconds: 6), onTimeout: () => const []);

      try {
        await cacheBatch
            .commit(noResult: true)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    return enriched;
  }

  /// Pipeline: Offline Dictionary Glossary -> Contextual LLM (Gemini with Sentence + Glossary)
  /// or Google Translate GTX + Dictionary API -> returns contextual meaning & IPA.
  Future<Map<String, String>?> _lookupContextualEnVi({
    required String word,
    required String lemma,
    required String sentence,
    required String glossaryHint,
    required String geminiApiKey,
  }) async {
    try {
      final dictFuture = _fetchDictionaryApi(word, lemma);
      final viFuture = geminiApiKey.isNotEmpty
          ? _fetchGeminiContextualMeaning(
              word: word,
              lemma: lemma,
              sentence: sentence,
              glossaryHint: glossaryHint,
              apiKey: geminiApiKey,
            )
          : _fetchGoogleTranslateContextualVi(
              word: word,
              sentence: sentence,
              glossaryHint: glossaryHint,
            );

      final results = await Future.wait([dictFuture, viFuture]);
      final dictInfo = results[0];
      final viInfo = results[1];
      if (dictInfo['ipa']!.isEmpty && viInfo['meaning']!.isEmpty) {
        return null;
      }
      final pos = viInfo['pos']!.isNotEmpty
          ? viInfo['pos']!
          : (dictInfo['pos'] ?? '');
      final rawMeaning = viInfo['meaning']!;
      final meaning = rawMeaning.isNotEmpty
          ? (rawMeaning.startsWith('(') || pos.isEmpty
              ? rawMeaning
              : '($pos) $rawMeaning')
          : '';
      return {
        'ipa': dictInfo['ipa'] ?? '',
        'ipa_us': dictInfo['ipa_us'] ?? '',
        'ipa_uk': dictInfo['ipa_uk'] ?? '',
        'audio': dictInfo['audio'] ?? '',
        'pos': pos,
        'translation': meaning,
      };
    } catch (_) {
      return null;
    }
  }

  /// Calls Gemini LLM with both the full [sentence] and the offline [glossaryHint]
  /// so polysemous words are translated according to their exact sentence context.
  Future<Map<String, String>> _fetchGeminiContextualMeaning({
    required String word,
    required String lemma,
    required String sentence,
    required String glossaryHint,
    required String apiKey,
  }) async {
    try {
      final prompt =
          'Translate the English word "$word" (lemma: "$lemma") into Vietnamese '
          'specifically as used in this sentence:\n'
          'Sentence: "$sentence"\n'
          'Offline Glossary / Morpheme Hint: $glossaryHint\n'
          'Reply strictly in JSON: {"pos": "noun|verb|adj|adv", "meaning": "concise Vietnamese meaning in context"}';

      final response = await _dio.post<Map<String, dynamic>>(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.1,
            'responseMimeType': 'application/json',
          },
        },
      );
      final candidates = response.data?['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content =
            (candidates.first as Map)['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final text = ((parts.first as Map)['text'] as String?) ?? '';
          final parsed = jsonDecode(text) as Map<String, dynamic>;
          final meaning = (parsed['meaning'] as String?)?.trim() ?? '';
          final pos = (parsed['pos'] as String?)?.trim() ?? '';
          if (meaning.isNotEmpty) {
            return {'meaning': meaning, 'pos': pos};
          }
        }
      }
    } catch (_) {}
    // Fallback to Google Translate contextual lookup if LLM call fails
    return _fetchGoogleTranslateContextualVi(
      word: word,
      sentence: sentence,
      glossaryHint: glossaryHint,
    );
  }

  Future<Map<String, String>> _fetchDictionaryApi(
    String word,
    String lemma,
  ) async {
    for (final candidate in {word, lemma}) {
      if (candidate.isEmpty) continue;
      try {
        final response = await _dio.get<List<dynamic>>(
          'https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(candidate)}',
        );
        final data = response.data;
        if (data != null && data.isNotEmpty) {
          final first = data.first as Map<String, dynamic>;
          String ipa = (first['phonetic'] as String?) ?? '';
          String ipaUs = '';
          String ipaUk = '';
          String audio = '';
          if (first['phonetics'] is List) {
            for (final p in (first['phonetics'] as List)) {
              if (p is Map) {
                final text = (p['text'] as String?) ?? '';
                final pAudio = (p['audio'] as String?) ?? '';
                if (ipa.isEmpty && text.isNotEmpty) {
                  ipa = text;
                }
                if (audio.isEmpty && pAudio.isNotEmpty) {
                  audio = pAudio;
                }
                final lowerAudio = pAudio.toLowerCase();
                if (text.isNotEmpty && lowerAudio.contains('-us')) {
                  ipaUs = text;
                } else if (text.isNotEmpty && lowerAudio.contains('-uk')) {
                  ipaUk = text;
                }
              }
            }
          }
          String pos = '';
          if (first['meanings'] is List &&
              (first['meanings'] as List).isNotEmpty) {
            final m = (first['meanings'] as List).first as Map<String, dynamic>;
            pos = (m['partOfSpeech'] as String?) ?? '';
          }
          return {
            'ipa': ipa,
            'ipa_us': ipaUs,
            'ipa_uk': ipaUk,
            'audio': audio,
            'pos': pos,
          };
        }
      } catch (_) {}
    }
    return {'ipa': '', 'ipa_us': '', 'ipa_uk': '', 'audio': '', 'pos': ''};
  }

  Future<Map<String, String>> _fetchGoogleTranslateContextualVi({
    required String word,
    required String sentence,
    required String glossaryHint,
  }) async {
    try {
      final url =
          'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=vi&dt=t&dt=bd&q=${Uri.encodeComponent(word)}';
      final response = await _dio.get<List<dynamic>>(url);
      final data = response.data;
      if (data != null && data.isNotEmpty) {
        String primaryMeaning = '';
        if (data[0] is List && (data[0] as List).isNotEmpty) {
          primaryMeaning = ((data[0] as List).first as List).first.toString();
        }
        String pos = '';
        final extraSynonyms = <String>[];
        if (data.length > 1 &&
            data[1] is List &&
            (data[1] as List).isNotEmpty) {
          final firstDict = (data[1] as List).first as List;
          pos = firstDict[0].toString();
          if (firstDict.length > 1 && firstDict[1] is List) {
            for (final syn in (firstDict[1] as List).take(3)) {
              final s = syn.toString();
              if (s.toLowerCase() != primaryMeaning.toLowerCase()) {
                extraSynonyms.add(s);
              }
            }
          }
        }
        final fullMeaning = extraSynonyms.isNotEmpty
            ? '$primaryMeaning; ${extraSynonyms.join(", ")}'
            : primaryMeaning;
        return {'meaning': fullMeaning, 'pos': pos};
      }
    } catch (_) {}
    return {'meaning': '', 'pos': ''};
  }
}
