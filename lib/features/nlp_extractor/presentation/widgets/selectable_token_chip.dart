import 'package:flutter/material.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/config/injection_container.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../../core/utils/cloze_masker.dart';
import '../../domain/entities/extracted_token.dart';

/// Extracted vocabulary tile for Tab 2 (Tách từ NLP):
/// - Checkbox, lemma + surface form, US/UK IPA speaker badges
/// - Vietnamese meaning with `DB` / `AI` source badge & tap-to-edit inline
/// - Cloze example sentence (+ Vietnamese sentence translation when AI-translated)
class SelectableTokenCard extends StatelessWidget {
  final ExtractedToken token;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<String>? onEditTranslation;

  const SelectableTokenCard({
    super.key,
    required this.token,
    required this.isSelected,
    required this.onTap,
    this.onEditTranslation,
  });

  Future<void> _showEditTranslationDialog(BuildContext context) async {
    if (onEditTranslation == null) return;
    final px = PixelColors.of(context);
    final ctrl = TextEditingController(text: token.translation);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: PixelCard(
          padding: const EdgeInsets.all(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SỬA NGHĨA: ${token.surfaceWord.toUpperCase()}',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Nhập nghĩa tiếng Việt...',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PixelButton(
                      label: 'HỦY',
                      backgroundColor: px.surfaceAlt,
                      foregroundColor: px.ink,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    const SizedBox(width: 8),
                    PixelButton(
                      label: 'LƯU',
                      backgroundColor: px.emerald,
                      foregroundColor: Colors.white,
                      onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (saved != null && saved.trim().isNotEmpty) {
      onEditTranslation!(saved.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isAi = token.translationSource == 'AI';
    final hasLemmaDiff =
        token.lemma.isNotEmpty && token.lemma != token.surfaceWord;
    final displayTitle = hasLemmaDiff ? token.lemma : token.surfaceWord;

    return PixelCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      borderColor: isSelected ? px.primaryBorder : px.border,
      backgroundColor: isSelected ? px.cardParchment : px.surface,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onTap(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        Text(
                          displayTitle,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 16),
                        ),
                        if (hasLemmaDiff)
                          Text(
                            '(${token.surfaceWord})',
                            style: TextStyle(
                              fontSize: 12,
                              color: px.inkMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (token.effectivePhoneticUs.isNotEmpty)
                          PixelBadge(
                            icon: Icons.volume_up_rounded,
                            label: 'US ${token.effectivePhoneticUs}',
                            backgroundColor: colorScheme.primaryContainer,
                            onTap: () => sl<TtsCacheService>().speak(
                              token.surfaceWord,
                              audioUrl: token.audioUrl,
                              accent: 'en-US',
                            ),
                          ),
                        if (token.phoneticUk.isNotEmpty)
                          PixelBadge(
                            icon: Icons.volume_up_rounded,
                            label: 'UK ${token.phoneticUk}',
                            backgroundColor: colorScheme.secondaryContainer,
                            onTap: () => sl<TtsCacheService>().speak(
                              token.surfaceWord,
                              accent: 'en-GB',
                            ),
                          ),
                        if (token.isAlreadySaved)
                          PixelBadge(
                            label: 'ĐÃ LƯU',
                            backgroundColor: px.emerald,
                            foregroundColor: Colors.white,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Meaning row with DB / AI source badge + tap-to-edit inline
                    InkWell(
                      onTap: onEditTranslation != null
                          ? () => _showEditTranslationDialog(context)
                          : null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2, right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isAi ? px.emerald : px.surfaceAlt,
                              border: Border.all(
                                color: isAi
                                    ? px.emerald
                                    : px.border.withValues(alpha: 0.45),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              isAi ? 'AI' : 'DB',
                              style: TextStyle(
                                fontFamily: AppTheme.monoFont,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isAi ? Colors.white : px.inkMuted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              token.translation,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (onEditTranslation != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 4, top: 2),
                              child: Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: px.inkMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (token.sourceSentence.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        color: px.surfaceAlt,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '"${ClozeMasker.sanitizeSentence(token.clozeSentence.isNotEmpty ? token.clozeSentence : ClozeMasker.maskSentence(sentence: token.sourceSentence, word: token.surfaceWord, lemma: token.lemma))}"',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: px.ink,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                            if (token.sentenceTranslation.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                '↳ ${token.sentenceTranslation}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: px.emerald),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
