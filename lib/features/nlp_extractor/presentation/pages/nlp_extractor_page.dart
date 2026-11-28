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

  String? _resolveSelectedDeckId() {
    final decks = ref.read(deckListProvider).valueOrNull ?? const [];
    if (_selectedDeckId != null && decks.any((d) => d.id == _selectedDeckId)) {
      return _selectedDeckId;
    }
    return decks.isNotEmpty ? decks.first.id : null;
  }

  Future<void> _quickPaste(NlpExtractorNotifier notifier) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _textController.text = text;
      await notifier.analyzeText(text, deckId: _resolveSelectedDeckId());
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
    final isTranslatingAi = ref.watch(
      nlpExtractorNotifierProvider.select((s) => s.isTranslatingAi),
    );
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
    final recentSnippets =
        ref.watch(nlpExtractorNotifierProvider.select((s) => s.recentSnippets));
    final notifier = ref.read(nlpExtractorNotifierProvider.notifier);

    ref.listen<NlpExtractorState>(nlpExtractorNotifierProvider, (prev, next) {
      if (prev?.mode != next.mode) {
        _textController.text = next.rawText;
      }
      if (next.lastSavedCount != null &&
          next.saveRevision != prev?.saveRevision) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã tạo ${next.lastSavedCount} thẻ FSRS + Cloze thành công!',
            ),
          ),
        );
        ref.read(cardsRevisionProvider.notifier).state++;
        ref.invalidate(deckListProvider);
        ref.invalidate(studyStatsProvider);
      }
    });

    final isEnVi = mode == LearningLanguageMode.englishForVietnamese;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final editorHeight =
        tokens.isEmpty ? (screenHeight * 0.36).clamp(180.0, 300.0) : 112.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('TÁCH TỪ NLP'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Switcher moved cleanly below AppBar
            SegmentedButton<LearningLanguageMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: LearningLanguageMode.englishForVietnamese,
                  label: Text('EN-VI'),
                ),
                ButtonSegment(
                  value: LearningLanguageMode.cjkRadicals,
                  label: Text('Bộ thủ'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                notifier.setLanguageMode(selection.first);
              },
            ),
            const SizedBox(height: 12),

            // Input Box with bottom-right Paste & Clear toolbar
            PixelCard(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: editorHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBF6EA),
                      border: Border.all(
                        color: px.border.withValues(alpha: 0.65),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: TextField(
                            controller: _textController,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(fontSize: 14, height: 1.45),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                42,
                              ),
                              hintText: isEnVi
                                  ? 'Dán đoạn văn hoặc bài báo Tiếng Anh để tách từ vựng, tra IPA & tạo câu Cloze...'
                                  : 'Dán câu hoặc đoạn văn chữ Hán để tách bộ thủ...',
                            ),
                          ),
                        ),
                        // Bottom-right quick actions (Paste & Clear)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _EditorActionIcon(
                                icon: Icons.content_paste_rounded,
                                tooltip: 'Dán nhanh',
                                onTap: () => _quickPaste(notifier),
                              ),
                              const SizedBox(width: 6),
                              _EditorActionIcon(
                                icon: Icons.delete_outline_rounded,
                                tooltip: 'Xóa',
                                onTap: _quickClear,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  PixelButton(
                    expand: true,
                    backgroundColor: px.primary,
                    foregroundColor: px.ink,
                    icon: isAnalyzing ? Icons.hourglass_top : Icons.bolt,
                    label: isAnalyzing
                        ? 'ĐANG PHÂN TÍCH...'
                        : 'PHÂN TÍCH VĂN BẢN',
                    onPressed: isAnalyzing
                        ? null
                        : () => notifier.analyzeText(
                              _textController.text,
                              deckId: _resolveSelectedDeckId(),
                            ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (errorMessage != null && errorMessage.isNotEmpty)
              PixelCard(
                margin: const EdgeInsets.only(bottom: 10),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(10),
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
              // Tier 2 AI contextual translation bar + elapsed badge
              Row(
                children: [
                  if (elapsedMs != null)
                    PixelBadge(
                      label: 'SQLite ${elapsedMs}ms',
                      backgroundColor: px.surfaceAlt,
                    ),
                  const Spacer(),
                  if (isEnVi)
                    PixelButton(
                      label: isTranslatingAi
                          ? 'ĐANG DỊCH AI...'
                          : 'Dịch sát ngữ cảnh',
                      icon: Icons.auto_awesome_rounded,
                      backgroundColor: px.cyan,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      onPressed: isTranslatingAi
                          ? null
                          : () async {
                              final msg =
                                  await notifier.translateContextWithAi();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(msg)),
                              );
                            },
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Sticky top batch control bar: [☑ Chọn tất cả] • [Bộ thẻ ▾] • [+ LƯU X THẺ]
              Builder(
                builder: (context) {
                  final decks =
                      ref.watch(deckListProvider).valueOrNull ?? const [];
                  final effectiveDeckId =
                      decks.any((d) => d.id == _selectedDeckId)
                          ? _selectedDeckId!
                          : (decks.isNotEmpty ? decks.first.id : 'default_deck');
                  final allSelected = selectedCount == tokens.length;

                  return PixelCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: notifier.toggleSelectAll,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                allSelected
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 20,
                                color: allSelected ? px.emerald : px.inkMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                allSelected ? 'Bỏ chọn' : 'Tất cả',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: px.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (decks.isNotEmpty)
                          Expanded(
                            child: Container(
                              height: 32,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: px.surfaceAlt,
                                border: Border.all(
                                  color: px.border.withValues(alpha: 0.45),
                                  width: 1,
                                ),
                              ),
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
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
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
                          )
                        else
                          const Spacer(),
                        const SizedBox(width: 8),
                        PixelButton(
                          backgroundColor: px.emerald,
                          foregroundColor: Colors.white,
                          icon: Icons.add_rounded,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          label: isSaving
                              ? 'ĐANG LƯU...'
                              : 'LƯU $selectedCount THẺ',
                          onPressed: selectedCount == 0 || isSaving
                              ? null
                              : () => notifier.createSelectedCards(
                                    deckId: effectiveDeckId,
                                  ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              Expanded(
                child: ListView.builder(
                  itemCount: tokens.length,
                  itemBuilder: (context, index) {
                    return _TokenRowConsumer(token: tokens[index]);
                  },
                ),
              ),
            ] else
              Expanded(
                child: recentSnippets.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ĐOẠN VĂN ĐÃ TÁCH GẦN ĐÂY',
                            style: TextStyle(
                              fontFamily: AppTheme.pixelDisplayFont,
                              fontFamilyFallback: AppTheme.fontFallback,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: px.inkOnWood.withValues(alpha: 0.9),
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.separated(
                              itemCount: recentSnippets.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = recentSnippets[index];
                                return PixelCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  onTap: () {
                                    _textController.text = item.text;
                                    notifier.analyzeText(
                                      item.text,
                                      deckId: _resolveSelectedDeckId(),
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.history_rounded,
                                        size: 18,
                                        color: px.primaryBorder,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          item.text,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: px.ink),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${item.tokenCount} từ',
                                        style: TextStyle(
                                          fontFamily: AppTheme.monoFont,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: px.emerald,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.topCenter,
                        child: PixelCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: px.primary.withValues(alpha: 0.22),
                                  border: Border.all(
                                    color: px.border,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.auto_stories_rounded,
                                  color: px.primaryBorder,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'MẸO TÁCH TỪ NHANH',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(fontSize: 13),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isEnVi
                                          ? 'Dán đoạn báo hoặc phụ đề vào khung trên để tự động lấy IPA Anh-Mỹ, nghĩa Việt và câu điền khuyết.'
                                          : 'Dán câu chữ Hán để tách bộ thủ và lưu nhanh thành thẻ học.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

class _EditorActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _EditorActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: px.surfaceAlt,
            border: Border.all(
              color: px.border.withValues(alpha: 0.55),
              width: 1.5,
            ),
          ),
          child: Icon(icon, size: 17, color: px.ink),
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
      onEditTranslation: (newVal) => ref
          .read(nlpExtractorNotifierProvider.notifier)
          .updateTokenTranslation(word, newVal),
    );
  }
}
