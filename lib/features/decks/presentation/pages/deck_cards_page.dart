import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/config/injection_container.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../stats/presentation/providers/stats_provider.dart';
import '../../domain/entities/vocab_card.dart';
import '../../domain/usecases/manage_cards_and_decks_usecase.dart';
import '../providers/deck_provider.dart';
import '../widgets/card_edit_dialog.dart';

class DeckCardsPage extends ConsumerStatefulWidget {
  final String deckId;

  const DeckCardsPage({super.key, required this.deckId});

  @override
  ConsumerState<DeckCardsPage> createState() => _DeckCardsPageState();
}

class _DeckCardsPageState extends ConsumerState<DeckCardsPage> {
  String _search = '';

  Future<void> _editCard(VocabCard card) async {
    final form = await showPixelEditCardDialog(context, card);
    if (form == null) return;

    final res = await sl<UpdateCardUseCase>()(
      cardId: card.id,
      word: form.word,
      partOfSpeech: form.partOfSpeech,
      phoneticUs: form.phoneticUs,
      phoneticUk: form.phoneticUk,
      translation: form.translation,
      contextSentence: form.contextSentence,
    );

    if (!mounted) return;
    res.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi cập nhật thẻ: ${failure.message}')),
      ),
      (_) {
        ref.invalidate(deckCardsProvider(widget.deckId));
        ref.invalidate(deckListProvider);
        ref.invalidate(leechCardsProvider);
        ref.invalidate(studyStatsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã cập nhật thẻ "${form.word}"!')),
        );
      },
    );
  }

  Future<void> _deleteCard(VocabCard card) async {
    final confirmed = await showPixelDeleteConfirmDialog(
      context,
      title: 'XÓA THẺ "${card.word.toUpperCase()}"?',
      message:
          'Thẻ này và toàn bộ lịch sử ôn tập (revlog) của nó sẽ bị xóa vĩnh viễn.',
    );
    if (!confirmed) return;

    final res = await sl<DeleteCardUseCase>()(card.id);
    if (!mounted) return;
    res.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi xóa thẻ: ${failure.message}')),
      ),
      (_) {
        ref.invalidate(deckCardsProvider(widget.deckId));
        ref.invalidate(deckListProvider);
        ref.invalidate(leechCardsProvider);
        ref.invalidate(studyStatsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xóa thẻ "${card.word}"!')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final cardsAsync = ref.watch(deckCardsProvider(widget.deckId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('QUẢN LÝ THẺ • SỬA / XÓA'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(deckCardsProvider(widget.deckId)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Tìm theo từ, POS (noun/verb/adj) hoặc nghĩa...',
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: cardsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: PixelCard(
                    backgroundColor: colorScheme.errorContainer,
                    child: Text('Error: $err'),
                  ),
                ),
                data: (cards) {
                  final filtered = _search.isEmpty
                      ? cards
                      : cards.where((c) {
                          return c.word.toLowerCase().contains(_search) ||
                              c.partOfSpeech.toLowerCase().contains(_search) ||
                              c.translation.toLowerCase().contains(_search);
                        }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: PixelCard(
                        backgroundColor: px.surfaceAlt,
                        child: Text(
                          cards.isEmpty
                              ? 'Bộ thẻ chưa có từ vựng nào.'
                              : 'Không tìm thấy thẻ khớp với "$_search".',
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final card = filtered[index];
                      return PixelCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        card.word,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      PixelBadge(
                                        label: card.partOfSpeech.toUpperCase(),
                                        backgroundColor:
                                            colorScheme.tertiaryContainer,
                                      ),
                                      if (card.effectivePhoneticUs.isNotEmpty)
                                        PixelBadge(
                                          icon: Icons.volume_up_rounded,
                                          label: 'US ${card.effectivePhoneticUs}',
                                          backgroundColor:
                                              colorScheme.primaryContainer,
                                          onTap: () =>
                                              sl<TtsCacheService>().speak(
                                            card.word,
                                            audioUrl: card.audioUrl,
                                            accent: 'en-US',
                                          ),
                                        ),
                                      if (card.phoneticUk.isNotEmpty)
                                        PixelBadge(
                                          icon: Icons.volume_up_rounded,
                                          label: 'UK ${card.phoneticUk}',
                                          backgroundColor:
                                              colorScheme.secondaryContainer,
                                          onTap: () =>
                                              sl<TtsCacheService>().speak(
                                            card.word,
                                            accent: 'en-GB',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Sửa thẻ & POS',
                                  icon: Icon(Icons.edit_rounded,
                                      color: px.primary),
                                  onPressed: () => _editCard(card),
                                ),
                                IconButton(
                                  tooltip: 'Xóa thẻ',
                                  icon: Icon(Icons.delete_outline_rounded,
                                      color: px.coral),
                                  onPressed: () => _deleteCard(card),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              card.translation,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (card.contextSentence.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '"${card.contextSentence}"',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: px.inkMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
