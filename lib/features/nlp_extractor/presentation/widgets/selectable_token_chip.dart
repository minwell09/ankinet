import 'package:flutter/material.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/config/injection_container.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../domain/entities/extracted_token.dart';

class SelectableTokenCard extends StatelessWidget {
  final ExtractedToken token;
  final bool isSelected;
  final VoidCallback onTap;

  const SelectableTokenCard({
    super.key,
    required this.token,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return PixelCard(
      margin: const EdgeInsets.only(bottom: 10),
      borderColor: isSelected ? px.primaryBorder : px.border,
      borderWidth: isSelected ? 3 : 2.5,
      shadowOffset: isSelected ? const Offset(4, 4) : const Offset(3, 3),
      backgroundColor: isSelected ? px.cardParchment : px.surface,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          token.surfaceWord,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (token.lemma.isNotEmpty &&
                            token.lemma != token.surfaceWord)
                          Text(
                            '→ ${token.lemma}',
                            style: TextStyle(
                              color: px.cyan,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        if (token.effectivePhoneticUs.isNotEmpty)
                          PixelBadge(
                            icon: Icons.volume_up_rounded,
                            label:
                                'US ${token.effectivePhoneticUs.startsWith('/') ? token.effectivePhoneticUs : '[${token.effectivePhoneticUs}]'}',
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
                            label:
                                'UK ${token.phoneticUk.startsWith('/') ? token.phoneticUk : '[${token.phoneticUk}]'}',
                            backgroundColor: colorScheme.secondaryContainer,
                            onTap: () => sl<TtsCacheService>().speak(
                              token.surfaceWord,
                              accent: 'en-GB',
                            ),
                          ),
                        if (token.effectivePhoneticUs.isEmpty &&
                            token.phoneticUk.isEmpty)
                          PixelBadge(
                            icon: Icons.volume_up_rounded,
                            label: 'TTS',
                            onTap: () => sl<TtsCacheService>().speak(
                              token.surfaceWord,
                              audioUrl: token.audioUrl,
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
                    Text(
                      token.translation,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (token.sourceSentence.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: px.surfaceAlt,
                          border: Border.all(color: px.border, width: 1.5),
                        ),
                        child: Text(
                          'CLOZE: "${token.clozeSentence.isNotEmpty ? token.clozeSentence : token.sourceSentence}"',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (token.radicals.isNotEmpty) ...[
            const Divider(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: token.radicals.map((radical) {
                return PixelBadge(
                  label: '${radical.symbol} (${radical.meaning})',
                  backgroundColor: colorScheme.tertiaryContainer,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
