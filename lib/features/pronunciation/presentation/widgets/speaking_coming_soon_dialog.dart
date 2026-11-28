import 'package:flutter/material.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/config/injection_container.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../decks/domain/entities/vocab_card.dart';

/// 16-bit Pixel Dialog displayed when tapping the Speaking / Mic button
/// while the AI pronunciation scoring model is still in training.
///
/// Includes built-in `🔊 US` and `🔊 UK` model audio buttons when opened
/// from a specific [card], plus a `ĐÃ RÕ` dismiss button.
Future<void> showSpeakingComingSoonDialog(
  BuildContext context, {
  VocabCard? card,
}) async {
  final px = PixelColors.of(context);
  final colorScheme = Theme.of(context).colorScheme;

  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: PixelCard(
          padding: const EdgeInsets.all(16),
          borderWidth: 2,
          shadowOffset: const Offset(0, 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PixelSectionHeader(
                title: 'LUYỆN NÓI AI',
                icon: Icons.mic_rounded,
                accentColor: px.primary,
                trailing: PixelBadge(
                  label: 'SOON',
                  backgroundColor: px.primary,
                  foregroundColor: px.ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tính năng chấm điểm phát âm AI theo từng âm vị IPA đang được huấn luyện và sẽ sớm mở khóa ở bản cập nhật tới.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              if (card != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  color: px.surfaceAlt,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nghe giọng mẫu cho "${card.word}":',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: px.ink,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          PixelButton(
                            label: card.effectivePhoneticUs.isNotEmpty
                                ? 'US ${card.effectivePhoneticUs}'
                                : 'US',
                            icon: Icons.volume_up_rounded,
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: px.ink,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            onPressed: () => sl<TtsCacheService>().speak(
                              card.word,
                              audioUrl: card.audioUrl,
                              accent: 'en-US',
                            ),
                          ),
                          PixelButton(
                            label: card.phoneticUk.isNotEmpty
                                ? 'UK ${card.phoneticUk}'
                                : 'UK',
                            icon: Icons.volume_up_rounded,
                            backgroundColor: colorScheme.secondaryContainer,
                            foregroundColor: px.ink,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            onPressed: () => sl<TtsCacheService>().speak(
                              card.word,
                              accent: 'en-GB',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              PixelButton(
                expand: true,
                label: 'ĐÃ RÕ',
                backgroundColor: px.primary,
                foregroundColor: px.ink,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
