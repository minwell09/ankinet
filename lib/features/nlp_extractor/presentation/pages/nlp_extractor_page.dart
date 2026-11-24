import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../decks/presentation/providers/deck_provider.dart';
import '../../../stats/presentation/providers/stats_provider.dart';
import '../../data/datasources/nlp_analyzer_datasource.dart';
import '../providers/nlp_extractor_provider.dart';
import '../widgets/selectable_token_chip.dart';

class NlpExtractorPage extends ConsumerStatefulWidget {
  const NlpExtractorPage({super.key});

  @override
  ConsumerState<NlpExtractorPage> createState() => _NlpExtractorPageState();
}

class _NlpExtractorPageState extends ConsumerState<NlpExtractorPage> {
  late final TextEditingController _textController;
  String? _selectedDeckId;

  @override
  void initState() {
    super.initState();
    final initialText = ref.read(nlpExtractorNotifierProvider).rawText;
    _textController = TextEditingController(text: initialText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _quickPaste(NlpExtractorNotifier notifier) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _textController.text = text;
      await notifier.analyzeText(text);
    }
  }

  void _quickClear() {
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final mode = ref.watch(nlpExtractorNotifierProvider.select((s) => s.mode));
    final isAnalyzing =
        ref.watch(nlpExtractorNotifierProvider.select((s) => s.isAnalyzing));
    final isSaving =
        ref.watch(nlpExtractorNotifierProvider.select((s) => s.isSaving));
    final tokens =
        ref.watch(nlpExtractorNotifierProvider.select((s) => s.tokens));
    final selectedCount = ref.watch(
      nlpExtractorNotifierProvider.select((s) => s.selectedWords.length),
    );
    final elapsedMs =
        ref.watch(nlpExtractorNotifierProvider.select((s) => s.lastElapsedMs));
    final errorMessage =
        ref.watch(nlpExtractorNotifierProvider.select((s) => s.errorMessage));
    final notifier = ref.read(nlpExtractorNotifierProvider.notifier);

    ref.listen<NlpExtractorState>(nlpExtractorNotifierProvider, (prev, next) {
      if (prev?.mode != next.mode) {
        _textController.text = next.rawText;
      }
      if (next.lastSavedCount != null &&
          next.lastSavedCount != prev?.lastSavedCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã tạo ${next.lastSavedCount} thẻ FSRS + Cloze thành công!',
            ),
          ),
        );
        ref.invalidate(deckListProvider);
        ref.invalidate(studyStatsProvider);
      }
    });

    final isEnVi = mode == LearningLanguageMode.englishForVietnamese;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          isEnVi ? 'TÁCH TỪ NLP • EN ➔ VI' : 'NLP EXTRACTOR • CJK',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<LearningLanguageMode>(
              segments: const [
                ButtonSegment(
                  value: LearningLanguageMode.englishForVietnamese,
                  label: Text('EN-VI'),
                ),
                ButtonSegment(
                  value: LearningLanguageMode.cjkRadicals,
                  label: Text('BỘ THỦ'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                notifier.setLanguageMode(selection.first);
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PixelCard(
              woodFrame: true,
              backgroundColor: px.cardParchment,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _textController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: isEnVi
                          ? 'Dán đoạn văn / bài báo Tiếng Anh vào đây'
                          : 'Paste article, subtitle, or sentence',
                      hintText: isEnVi
                          ? 'Tự động tách từ, phiên âm US/UK IPA, câu Cloze & nghĩa Tiếng Việt...'
                          : 'Enter text to tokenize...',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Dán nhanh (Quick Paste)',
                            icon: const Icon(Icons.content_paste_rounded),
                            onPressed: () => _quickPaste(notifier),
                          ),
                          IconButton(
                            tooltip: 'Xóa nhanh',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: _quickClear,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PixelButton(
                    expand: true,
                    backgroundColor: px.primary,
                    icon: isAnalyzing ? Icons.hourglass_top : Icons.psychology,
                    label: isAnalyzing
                        ? 'ĐANG PHÂN TÍCH VĂN BẢN...'
                        : (isEnVi
                            ? 'PHÂN TÍCH (OFFLINE SQLITE + CACHE)'
                            : 'TOKENIZE & TRANSCRIBE'),
                    onPressed: isAnalyzing
                        ? null
                        : () => notifier.analyzeText(_textController.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (errorMessage != null && errorMessage.isNotEmpty)
              PixelCard(
                margin: const EdgeInsets.only(bottom: 12),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                child: Row(
                  children: [
                    Expanded(child: Text(errorMessage)),
                    const SizedBox(width: 8),
                    PixelButton(
                      label: 'THỬ LẠI',
                      backgroundColor: px.coral,
                      onPressed: () =>
                          notifier.analyzeText(_textController.text),
                    ),
                  ],
                ),
              ),
            if (tokens.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PixelBadge(
                          label: 'CHỌN: $selectedCount / ${tokens.length}',
                          backgroundColor: px.gold,
                          foregroundColor: const Color(0xFF1E1B2E),
                        ),
                        if (elapsedMs != null)
                          PixelBadge(
                            label: '${elapsedMs}ms',
                            backgroundColor: px.surfaceAlt,
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: notifier.toggleSelectAll,
                    icon: const Icon(Icons.select_all, size: 18),
                    label: Text(
                      selectedCount == tokens.length
                          ? 'Bỏ chọn hết'
                          : 'Chọn tất cả',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  itemCount: tokens.length,
                  itemBuilder: (context, index) {
                    return _TokenRowConsumer(token: tokens[index]);
                  },
                ),
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final decks =
                      ref.watch(deckListProvider).valueOrNull ?? const [];
                  final effectiveDeckId = decks.any((d) => d.id == _selectedDeckId)
                      ? _selectedDeckId!
                      : (decks.isNotEmpty ? decks.first.id : 'default_deck');

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (decks.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: px.surface,
                            border: Border.all(color: px.border, width: 2),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'LƯU VÀO BỘ THẺ:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: px.inkMuted,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    isDense: true,
                                    value: effectiveDeckId,
                                    items: decks.map((d) {
                                      return DropdownMenuItem<String>(
                                        value: d.id,
                                        child: Text(
                                          d.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedDeckId = val);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      PixelButton(
                        expand: true,
                        backgroundColor: px.emerald,
                        icon: Icons.add_card,
                        label: isSaving
                            ? 'ĐANG LƯU THẺ...'
                            : 'LƯU $selectedCount THẺ FSRS (KÈM CÂU CLOZE)',
                        onPressed: selectedCount == 0 || isSaving
                            ? null
                            : () => notifier.createSelectedCards(
                                  deckId: effectiveDeckId,
                                ),
                      ),
                    ],
                  );
                },
              ),
            ] else
              Expanded(
                child: Center(
                  child: PixelCard(
                    backgroundColor: px.surfaceAlt,
                    child: Text(
                      isEnVi
                          ? 'Nhấn Dán nhanh hoặc PHÂN TÍCH ở trên để tách từ vựng, tra US/UK IPA và tạo câu điền khuyết (Cloze).'
                          : 'Tap Quick Paste or Analyze above to tokenize text and create flashcards.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TokenRowConsumer extends ConsumerWidget {
  final dynamic token;

  const _TokenRowConsumer({required this.token});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final word = token.surfaceWord as String;
    final isSelected = ref.watch(
      nlpExtractorNotifierProvider
          .select((s) => s.selectedWords.contains(word)),
    );
    return SelectableTokenCard(
      token: token,
      isSelected: isSelected,
      onTap: () => ref
          .read(nlpExtractorNotifierProvider.notifier)
          .toggleWordSelection(word),
    );
  }
}
