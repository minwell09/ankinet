import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../decks/domain/entities/vocab_card.dart';
import '../../domain/entities/pronunciation_result.dart';
import '../providers/pronunciation_provider.dart';
import 'pixel_volume_meter.dart';
import 'pronunciation_breakdown_dialog.dart';
import 'speaking_coming_soon_dialog.dart';

/// Minimal, non-intrusive Pronunciation Assessment integration for the Flashcard:
/// - Keeps [US] and [UK] audio badges side-by-side with optional compact Mic button
/// - Placed on Flashcard Back (`showMic: true`) so FSRS grading flow is never blocked
class FlashcardPronunciationBar extends ConsumerWidget {
  final VocabCard card;
  final String targetAccent;
  final void Function(String accent) onSpeakAccent;
  final bool showMic;
  final bool comingSoon;

  const FlashcardPronunciationBar({
    super.key,
    required this.card,
    required this.targetAccent,
    required this.onSpeakAccent,
    this.showMic = true,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final state = ref.watch(pronunciationSessionProvider(card.id));
    final notifier = ref.read(pronunciationSessionProvider(card.id).notifier);
    final result = state.lastResult;

    final hasUs = card.effectivePhoneticUs.isNotEmpty;
    final hasUk = card.phoneticUk.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (hasUs)
              PixelBadge(
                icon: Icons.volume_up_rounded,
                label: 'US ${card.effectivePhoneticUs}',
                backgroundColor: colorScheme.primaryContainer,
                onTap: () => onSpeakAccent('en-US'),
              ),
            if (hasUk)
              PixelBadge(
                icon: Icons.volume_up_rounded,
                label: 'UK ${card.phoneticUk}',
                backgroundColor: colorScheme.secondaryContainer,
                onTap: () => onSpeakAccent('en-GB'),
              ),
            if (!hasUs && !hasUk)
              PixelBadge(
                icon: Icons.volume_up_rounded,
                label: 'PHÁT ÂM',
                onTap: () => onSpeakAccent(targetAccent),
              ),
            // Optional non-blocking Mic button (shown on Flashcard Back)
            if (showMic && comingSoon)
              GestureDetector(
                onTap: () => showSpeakingComingSoonDialog(context, card: card),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: px.surfaceAlt,
                      border: Border.all(
                        color: px.border.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mic_rounded, size: 15, color: px.ink),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          color: px.primary,
                          child: Text(
                            'SOON',
                            style: TextStyle(
                              fontFamily: AppTheme.monoFont,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: px.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (showMic) ...[
              PixelButton(
                label: state.isScoring
                    ? 'ĐANG CHẤM...'
                    : (state.isRecording ? 'DỪNG GHI' : 'LUYỆN NÓI'),
                icon: state.isRecording
                    ? Icons.stop_rounded
                    : Icons.mic_rounded,
                backgroundColor: state.isRecording
                    ? PronunciationColors.recordingCoral
                    : px.primary,
                foregroundColor: state.isRecording ? Colors.white : px.ink,
                borderColor: state.isRecording ? px.border : px.primaryBorder,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onPressed: state.isScoring
                    ? null
                    : () => notifier.toggleRecording(
                          card: card,
                          accent: targetAccent,
                        ),
              ),
            ],
            // Compact RPG Rank Badge (tapping opens Parchment Breakdown Modal)
            if (result != null && !state.isRecording)
              _RankScoreBadge(
                result: result,
                onTap: () => showPronunciationBreakdownDialog(
                  context,
                  card: card,
                  accent: targetAccent,
                ),
              ),
          ],
        ),
        // Live 8-bit segmented pixel volume meter underneath IPA row
        if (state.isRecording) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: PixelVolumeMeter(level: state.volumeLevel),
          ),
        ],
        // Inline Phoneme Heatmap directly on the card once scored
        if (result != null && !state.isRecording) ...[
          const SizedBox(height: 10),
          _InlinePhonemeHeatmap(
            result: result,
            onTap: () => showPronunciationBreakdownDialog(
              context,
              card: card,
              accent: targetAccent,
            ),
          ),
        ],
      ],
    );
  }
}

class _RankScoreBadge extends StatelessWidget {
  final PronunciationResult result;
  final VoidCallback onTap;

  const _RankScoreBadge({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final badgeBg = PronunciationColors.forScore(result.overallScore);
    final highlight = Color.lerp(badgeBg, Colors.white, 0.3)!;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: badgeBg,
            border: Border.all(color: px.border, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: px.shadow.withValues(alpha: 0.55),
                offset: const Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: highlight,
                  border: Border.all(color: px.border, width: 1),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                result.compactBadgeLabel,
                style: const TextStyle(
                  fontFamily: AppTheme.pixelDisplayFont,
                  fontFamilyFallback: AppTheme.fontFallback,
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.open_in_new_rounded,
                size: 13,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlinePhonemeHeatmap extends StatelessWidget {
  final PronunciationResult result;
  final VoidCallback onTap;

  const _InlinePhonemeHeatmap({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final accentTag = result.accent == 'en-GB' ? 'UK' : 'US';

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: px.cardParchment,
            border: Border.all(color: px.woodShadow, width: 2),
            boxShadow: [
              BoxShadow(
                color: px.shadow.withValues(alpha: 0.28),
                offset: const Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$accentTag IPA: ',
                    style: TextStyle(
                      fontFamily: AppTheme.pixelDisplayFont,
                      fontFamilyFallback: AppTheme.fontFallback,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: px.inkMuted,
                    ),
                  ),
                  Flexible(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                        children: result.phonemes.map((p) {
                          if (p.isDelimiter) {
                            return TextSpan(
                              text: p.targetIpa,
                              style: TextStyle(color: px.inkMuted),
                            );
                          }
                          final isMissed =
                              p.status == PhonemeAccuracyStatus.missed;
                          return TextSpan(
                            text: p.targetIpa,
                            style: TextStyle(
                              color: p.color,
                              decoration: isMissed
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: p.color,
                              decorationThickness: 2.2,
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${result.diagnosticTip} • Nhấn để xem chi tiết',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: px.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
