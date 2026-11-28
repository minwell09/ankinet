import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../decks/domain/entities/vocab_card.dart';
import '../../domain/entities/pronunciation_result.dart';
import '../providers/pronunciation_provider.dart';
import 'pixel_volume_meter.dart';

/// Opens the wooden-framed parchment RPG modal displaying the full
/// Pronunciation Assessment breakdown for [card].
Future<void> showPronunciationBreakdownDialog(
  BuildContext context, {
  required VocabCard card,
  required String accent,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => PronunciationBreakdownDialog(card: card, accent: accent),
  );
}

class PronunciationBreakdownDialog extends ConsumerWidget {
  final VocabCard card;
  final String accent;

  const PronunciationBreakdownDialog({
    super.key,
    required this.card,
    required this.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final px = PixelColors.of(context);
    final state = ref.watch(pronunciationSessionProvider(card.id));
    final notifier = ref.read(pronunciationSessionProvider(card.id).notifier);
    final result = state.lastResult;
    final hasSentence = card.contextSentence.trim().isNotEmpty;
    final accentLabel = accent == 'en-GB' ? 'UK (en-GB)' : 'US (en-US)';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: PixelCard(
          woodFrame: true,
          showRivets: true,
          backgroundColor: px.cardParchment,
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Header
                PixelSectionHeader(
                  title: 'CHẤM ĐIỂM PHÁT ÂM • ${card.word.toUpperCase()}',
                  icon: Icons.graphic_eq_rounded,
                  accentColor: px.primary,
                  trailing: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: px.surfaceAlt,
                          border: Border.all(color: px.border, width: 2),
                        ),
                        child: Icon(Icons.close_rounded, size: 17, color: px.ink),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Word / Full-Sentence Mode Toggle
                Row(
                  children: [
                    Expanded(
                      child: _PixelModeTab(
                        label: 'TỪ ĐƠN',
                        icon: Icons.short_text_rounded,
                        selected: state.mode == PronunciationPracticeMode.word,
                        onTap: () => notifier.setMode(PronunciationPracticeMode.word),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PixelModeTab(
                        label: 'CẢ CÂU (SHADOWING)',
                        icon: Icons.notes_rounded,
                        selected: state.mode == PronunciationPracticeMode.sentence,
                        enabled: hasSentence,
                        onTap: hasSentence
                            ? () => notifier
                                .setMode(PronunciationPracticeMode.sentence)
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (result != null) ...[
                  // Overall Score Bar & Rank Badge (S / A / B / C)
                  _OverallScorePanel(
                    result: result,
                    accentLabel: accentLabel,
                  ),
                  const SizedBox(height: 12),

                  // Concise Vietnamese Diagnostic Tip
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: px.surfaceAlt,
                      border: Border.all(color: px.border, width: 2),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: PronunciationColors.forScore(
                              result.overallScore,
                            ),
                            border: Border.all(color: px.border, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.tips_and_updates_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CHẨN ĐOÁN PHÁT ÂM',
                                style: TextStyle(
                                  fontFamily: AppTheme.pixelDisplayFont,
                                  fontFamilyFallback: AppTheme.fontFallback,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: px.inkMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                result.diagnosticTip,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: px.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Either Phoneme-by-Phoneme Pixel Tile Grid (Word Mode)
                  // or Full-Sentence Word-Level Highlighting (Sentence Mode)
                  if (state.mode == PronunciationPracticeMode.sentence &&
                      hasSentence) ...[
                    _SentenceHighlightingPanel(
                      wordScores: result.wordScores,
                      fallbackSentence: card.contextSentence,
                      onWordTap: (w) => notifier.playReference(
                        card: card,
                        accent: accent,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  Text(
                    'CHI TIẾT TỪNG ÂM VỊ (TARGET IPA ➔ DETECTED IPA)',
                    style: TextStyle(
                      fontFamily: AppTheme.pixelDisplayFont,
                      fontFamilyFallback: AppTheme.fontFallback,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: px.inkMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: result.scoredPhonemes
                        .map((p) => _PhonemePixelTile(phoneme: p))
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 10),
                  // Color Legend
                  const Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _LegendDot(
                        color: PronunciationColors.accurate,
                        label: '≥80% Chuẩn',
                      ),
                      _LegendDot(
                        color: PronunciationColors.close,
                        label: '60–79% Gần đúng',
                      ),
                      _LegendDot(
                        color: PronunciationColors.missed,
                        label: '<60% Thiếu / Sai âm',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: px.surfaceAlt,
                      border: Border.all(color: px.border, width: 2),
                    ),
                    child: Text(
                      'Nhấn nút LUYỆN NÓI bên dưới để ghi âm và xem phân tích chi tiết từng âm vị IPA.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: px.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Live 8-bit Volume Meter while re-recording inside dialog
                if (state.isRecording) ...[
                  PixelVolumeMeter(
                    level: state.volumeLevel,
                    statusLabel: state.mode == PronunciationPracticeMode.sentence
                        ? 'Đang thu âm cả câu... Nhấn DỪNG GHI'
                        : 'Đang thu âm từ "${card.word}"... Nhấn DỪNG GHI',
                  ),
                  const SizedBox(height: 12),
                ],

                // Side-by-Side Playback Buttons: [🔊 Nghe Mẫu] vs [🎧 Giọng Của Bạn]
                Row(
                  children: [
                    Expanded(
                      child: PixelButton(
                        expand: true,
                        label: 'Nghe Mẫu',
                        icon: Icons.volume_up_rounded,
                        backgroundColor: px.cyan,
                        foregroundColor: Colors.white,
                        onPressed: () => notifier.playReference(
                          card: card,
                          accent: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PixelButton(
                        expand: true,
                        label: state.isPlayingUserAudio
                            ? 'Đang phát ${(state.playbackProgress * 100).round()}%'
                            : 'Giọng Của Bạn',
                        icon: state.isPlayingUserAudio
                            ? Icons.graphic_eq_rounded
                            : Icons.headphones_rounded,
                        backgroundColor: px.primary,
                        foregroundColor: px.ink,
                        onPressed: result == null || state.isRecording
                            ? null
                            : notifier.playUserRecording,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Re-record / Practice Action Button
                PixelButton(
                  expand: true,
                  label: state.isScoring
                      ? 'ĐANG PHÂN TÍCH ÂM VỊ...'
                      : (state.isRecording
                          ? 'DỪNG GHI & CHẤM ĐIỂM'
                          : (state.mode == PronunciationPracticeMode.sentence
                              ? 'GHI ÂM LUYỆN CẢ CÂU'
                              : 'GHI ÂM LUYỆN LẠI TỪ NÀY')),
                  icon: state.isRecording
                      ? Icons.stop_rounded
                      : Icons.mic_rounded,
                  backgroundColor: state.isRecording
                      ? PronunciationColors.recordingCoral
                      : px.emerald,
                  foregroundColor: Colors.white,
                  onPressed: state.isScoring
                      ? null
                      : () => notifier.toggleRecording(
                            card: card,
                            accent: accent,
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverallScorePanel extends StatelessWidget {
  final PronunciationResult result;
  final String accentLabel;

  const _OverallScorePanel({
    required this.result,
    required this.accentLabel,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final scoreColor = PronunciationColors.forScore(result.overallScore);
    final scorePct = result.overallScore.round();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: px.surface,
        border: Border.all(color: px.border, width: 2.5),
      ),
      child: Row(
        children: [
          // Chunky RPG Rank Shield (S / A / B / C)
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: result.rank == 'S'
                  ? PronunciationColors.rankSGold
                  : scoreColor,
              border: Border.all(color: px.border, width: 3),
              boxShadow: [
                BoxShadow(
                  color: px.shadow,
                  offset: const Offset(3, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  result.rank,
                  style: TextStyle(
                    fontFamily: AppTheme.pixelDisplayFont,
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontSize: 26,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    color: result.rank == 'S' ? px.ink : Colors.white,
                  ),
                ),
                Text(
                  'RANK',
                  style: TextStyle(
                    fontFamily: AppTheme.pixelDisplayFont,
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: result.rank == 'S'
                        ? px.ink.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$scorePct% CHÍNH XÁC',
                      style: TextStyle(
                        fontFamily: AppTheme.pixelDisplayFont,
                        fontFamilyFallback: AppTheme.fontFallback,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: scoreColor,
                      ),
                    ),
                    PixelBadge(
                      label: accentLabel,
                      backgroundColor: px.surfaceAlt,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PixelProgressBar(
                  progress: (result.overallScore / 100.0).clamp(0.0, 1.0),
                  fillColor: scoreColor,
                  height: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhonemePixelTile extends StatelessWidget {
  final PhonemeScore phoneme;

  const _PhonemePixelTile({required this.phoneme});

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final accent = phoneme.color;
    final isDropped = phoneme.detectedIpa == '∅';

    return Container(
      width: 78,
      decoration: BoxDecoration(
        color: px.cardParchment,
        border: Border.all(color: px.border, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: px.shadow.withValues(alpha: 0.45),
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top colored score strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            color: accent,
            child: Text(
              '${phoneme.score.round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTheme.pixelDisplayFont,
                fontFamilyFallback: AppTheme.fontFallback,
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              children: [
                Text(
                  '/${phoneme.targetIpa}/',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '➔ ${isDropped ? '∅' : '/${phoneme.detectedIpa}/'}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDropped ? PronunciationColors.missed : px.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SentenceHighlightingPanel extends StatelessWidget {
  final List<WordPronunciationScore> wordScores;
  final String fallbackSentence;
  final ValueChanged<String> onWordTap;

  const _SentenceHighlightingPanel({
    required this.wordScores,
    required this.fallbackSentence,
    required this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: px.surface,
        border: Border.all(color: px.border, width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SHADOWING CẢ CÂU (CHẤM ĐIỂM TỪNG TỪ)',
            style: TextStyle(
              fontFamily: AppTheme.pixelDisplayFont,
              fontFamilyFallback: AppTheme.fontFallback,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: px.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (wordScores.isEmpty)
            Text(
              fallbackSentence,
              style: TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: px.ink,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: wordScores.map((ws) {
                final color = ws.color;
                return Tooltip(
                  message: '${ws.word}: ${ws.score.round()}%',
                  child: GestureDetector(
                    onTap: () => onWordTap(ws.word),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        border: Border.all(color: color, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ws.word,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${ws.score.round()}%',
                            style: TextStyle(
                              fontFamily: AppTheme.pixelDisplayFont,
                              fontFamilyFallback: AppTheme.fontFallback,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _PixelModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _PixelModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final bg = !enabled
        ? px.surfaceAlt.withValues(alpha: 0.55)
        : (selected ? px.primary : px.surfaceAlt);
    final fg = !enabled ? px.inkMuted : px.ink;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
              color: selected ? px.primaryBorder : px.border,
              width: 2.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: px.shadow.withValues(alpha: 0.5),
                      offset: const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.pixelDisplayFont,
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: px.border, width: 1.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: px.inkMuted,
          ),
        ),
      ],
    );
  }
}
