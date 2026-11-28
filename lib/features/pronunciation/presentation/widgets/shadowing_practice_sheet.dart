import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/config/injection_container.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../decks/domain/entities/vocab_card.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/pronunciation_result.dart';
import '../providers/pronunciation_provider.dart';
import 'pixel_volume_meter.dart';

/// Displays enlarged IPA transcription with the primary stressed syllable (`ˈ...`)
/// visually bolded and highlighted so learners immediately spot word stress.
class StressedIpaText extends StatelessWidget {
  final String ipa;
  final double fontSize;

  const StressedIpaText({
    super.key,
    required this.ipa,
    this.fontSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final raw = ipa.trim();
    if (raw.isEmpty) return const SizedBox.shrink();

    final spans = <TextSpan>[];
    final stressIdx = raw.indexOf('ˈ');
    if (stressIdx == -1) {
      spans.add(TextSpan(text: raw));
    } else {
      if (stressIdx > 0) {
        spans.add(TextSpan(text: raw.substring(0, stressIdx)));
      }
      // Highlight from ˈ up to the next syllable boundary (., ˌ, /, space, -)
      int endIdx = stressIdx + 1;
      while (endIdx < raw.length &&
          !const {'.', 'ˌ', '/', ' ', '-', ']'}.contains(raw[endIdx])) {
        endIdx++;
      }
      spans.add(
        TextSpan(
          text: raw.substring(stressIdx, endIdx),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: px.primaryBorder,
            backgroundColor: px.primary.withValues(alpha: 0.28),
          ),
        ),
      );
      if (endIdx < raw.length) {
        spans.add(TextSpan(text: raw.substring(endIdx)));
      }
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
          fontFamily: AppTheme.monoFont,
          fontFamilyFallback: AppTheme.fontFallback,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: px.ink,
          letterSpacing: 0.6,
        ),
        children: spans,
      ),
    );
  }
}

/// Shadowing / A-B Self-Comparison Practice Sheet.
///
/// Supports both:
/// - Single-card shadowing (triggered from the compact Mic button on Flashcard Back)
/// - Focused multi-card deck shadowing session (triggered from DeckCardsPage)
class ShadowingPracticeSheet extends ConsumerStatefulWidget {
  final List<VocabCard> cards;
  final int initialIndex;

  const ShadowingPracticeSheet({
    super.key,
    required this.cards,
    this.initialIndex = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required List<VocabCard> cards,
    int initialIndex = 0,
  }) async {
    if (cards.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShadowingPracticeSheet(
        cards: cards,
        initialIndex: initialIndex,
      ),
    );
  }

  @override
  ConsumerState<ShadowingPracticeSheet> createState() =>
      _ShadowingPracticeSheetState();
}

class _ShadowingPracticeSheetState
    extends ConsumerState<ShadowingPracticeSheet> {
  late int _index;
  int _passedCount = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.cards.length - 1);
  }

  void _nextOrClose() {
    if (_index + 1 < widget.cards.length) {
      setState(() => _index++);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final card = widget.cards[_index];
    final targetAccent =
        ref.watch(studySettingsProvider).valueOrNull?.targetAccent ?? 'en-US';
    final state = ref.watch(pronunciationSessionProvider(card.id));
    final notifier = ref.read(pronunciationSessionProvider(card.id).notifier);
    final hasRecorded = state.lastResult != null;
    final displayIpa = targetAccent == 'en-GB' && card.phoneticUk.isNotEmpty
        ? card.phoneticUk
        : card.effectivePhoneticUs;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: PixelCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  PixelSectionHeader(
                    title: widget.cards.length > 1
                        ? 'LUYỆN NÓI SHADOWING (${_index + 1}/${widget.cards.length})'
                        : 'LUYỆN NÓI SHADOWING',
                    icon: Icons.mic_rounded,
                    accentColor: px.primary,
                  )._wrappedExpanded(),
                  IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (widget.cards.length > 1) ...[
                const SizedBox(height: 6),
                PixelProgressBar(
                  progress: (_index + 1) / widget.cards.length,
                  fillColor: px.emerald,
                  height: 10,
                ),
              ],
              const SizedBox(height: 14),

              // Word + Enlarged Stressed IPA
              Text(
                card.word,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 28,
                      color: px.ink,
                    ),
              ),
              const SizedBox(height: 6),
              if (displayIpa.isNotEmpty)
                StressedIpaText(ipa: displayIpa, fontSize: 22),
              const SizedBox(height: 4),
              Text(
                card.translation,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),

              // A-B Comparison Row: Model US / Model UK / Replay Your Voice
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  PixelButton(
                    label: 'GIỌNG MẪU US',
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
                    label: 'GIỌNG MẪU UK',
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
                  if (hasRecorded && !state.isRecording)
                    PixelButton(
                      label: state.isPlayingUserAudio
                          ? 'ĐANG PHÁT...'
                          : 'NGHE LẠI GIỌNG BẠN',
                      icon: state.isPlayingUserAudio
                          ? Icons.graphic_eq_rounded
                          : Icons.play_arrow_rounded,
                      backgroundColor: px.cyan,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      onPressed: state.isPlayingUserAudio
                          ? null
                          : () => notifier.playUserRecording(),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Live Pixel Volume Meter while recording
              if (state.isRecording) ...[
                PixelVolumeMeter(level: state.volumeLevel),
                const SizedBox(height: 12),
              ],

              // Primary Record / Stop Button
              PixelButton(
                expand: true,
                label: state.isRecording
                    ? 'DỪNG GHI ÂM'
                    : (hasRecorded ? 'GHI ÂM LẠI' : 'NHẤN ĐỂ GHI ÂM'),
                icon: state.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                backgroundColor: state.isRecording
                    ? PronunciationColors.recordingCoral
                    : px.primary,
                foregroundColor: state.isRecording ? Colors.white : px.ink,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onPressed: state.isScoring
                    ? null
                    : () => notifier.toggleRecording(
                          card: card,
                          accent: targetAccent,
                        ),
              ),

              // Quick Self-Evaluation Buttons after recording: [✓ Đọc ổn] & [↻ Luyện lại]
              if (hasRecorded && !state.isRecording) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: PixelButton(
                        expand: true,
                        label: 'LUYỆN LẠI',
                        icon: Icons.replay_rounded,
                        backgroundColor: px.surfaceAlt,
                        foregroundColor: px.ink,
                        onPressed: () => notifier.toggleRecording(
                          card: card,
                          accent: targetAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PixelButton(
                        expand: true,
                        label: widget.cards.length > 1 ? 'ĐỌC ỔN →' : 'ĐỌC ỔN',
                        icon: Icons.check_rounded,
                        backgroundColor: px.emerald,
                        foregroundColor: Colors.white,
                        onPressed: () {
                          _passedCount++;
                          _nextOrClose();
                        },
                      ),
                    ),
                  ],
                ),
                if (widget.cards.length > 1 && _passedCount > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Đã hoàn thành $_passedCount/${widget.cards.length} từ trong phiên luyện nói.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension on Widget {
  Widget _wrappedExpanded() => Expanded(child: this);
}
