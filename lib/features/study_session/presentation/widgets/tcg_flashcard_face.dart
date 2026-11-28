import 'package:flutter/material.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/srs/fsrs_scheduler.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../decks/domain/entities/related_word_suggestion.dart';
import '../../../decks/domain/entities/vocab_card.dart';
import '../../../pronunciation/presentation/widgets/flashcard_pronunciation_bar.dart';

/// 16-bit Pixel Art Trading Card Game (TCG / Yu-Gi-Oh! style) palette
/// harmonized with the warm Stardew Valley pixel RPG aesthetic.
class _TcgFramePalette {
  final Color frameBase;
  final Color frameTexture;
  final Color frameHighlight;
  final Color frameShadow;
  final String editionTag;

  const _TcgFramePalette({
    required this.frameBase,
    required this.frameTexture,
    required this.frameHighlight,
    required this.frameShadow,
    required this.editionTag,
  });

  static _TcgFramePalette forCard(VocabCard card) {
    // Mastered cards (stable review >= 21 days): Emerald / Teal TCG frame
    if (card.state == CardState.review && card.stability >= 21.0) {
      return const _TcgFramePalette(
        frameBase: Color(0xFF4F9D73),
        frameTexture: Color(0xFF3E835E),
        frameHighlight: Color(0xFF8CD1AA),
        frameShadow: Color(0xFF2B5E42),
        editionTag: 'MASTER',
      );
    }
    // New cards: Warm Parchment Cream TCG frame
    if (card.state == CardState.newCard) {
      return const _TcgFramePalette(
        frameBase: Color(0xFFE8D4B0),
        frameTexture: Color(0xFFD7BC90),
        frameHighlight: Color(0xFFFFF4DC),
        frameShadow: Color(0xFFA8895C),
        editionTag: 'NEW',
      );
    }
    // Active Review / Learning / Relearning: Classic Golden-Ochre Monster/Effect frame
    return const _TcgFramePalette(
      frameBase: Color(0xFFD99B38),
      frameTexture: Color(0xFFC47E2C),
      frameHighlight: Color(0xFFF6CE7A),
      frameShadow: Color(0xFF8E561B),
      editionTag: 'EFFECT',
    );
  }
}

/// 16-bit Pixel Art TCG / Yu-Gi-Oh!-style Flashcard Face (Front & Back).
///
/// Layout anatomy:
/// 1. Outer chunky double-beveled textured TCG card frame (#3B2214 dark outline)
/// 2. Top recessed title plate + top-right octagonal POS Attribute Orb
/// 3. Right-aligned 1..5 red/gold pixel Star Level Row (FSRS mastery tier)
/// 4. Center recessed viewport with metallic-slate/dark-wood bevel (#5C5866/#3B2214)
///    on warm #FFF5DC parchment
/// 5. Bottom double-bordered cream Lore/Effect Box (#F9EED7 + #B86B28 border)
///    with [CLOZE] / [NGỮ CẢNH] and ATK/DEF-style `STAB / DIFF` stat line
/// 6. Outer bottom-left serial code (`CARD 3/7`) & edition stamp
class TcgFlashcardFace extends StatelessWidget {
  final VocabCard card;
  final bool isBack;
  final int cardIndex; // 0-based
  final int totalCards;
  final String targetAccent;
  final bool showClozeContext;
  final List<RelatedWordSuggestion> relatedWords;
  final void Function(String accent) onSpeakAccent;
  final void Function(VocabCard relatedCard) onEnqueueRelated;

  const TcgFlashcardFace({
    super.key,
    required this.card,
    required this.isBack,
    required this.cardIndex,
    required this.totalCards,
    required this.targetAccent,
    required this.showClozeContext,
    required this.relatedWords,
    required this.onSpeakAccent,
    required this.onEnqueueRelated,
  });

  static const Color _darkOutline = Color(0xFF3B2214);
  static const Color _viewportParchment = Color(0xFFFFF5DC);
  static const Color _viewportSlate = Color(0xFF5C5866);
  static const Color _viewportSlateLight = Color(0xFF8B8699);
  static const Color _viewportSlateDark = Color(0xFF393642);
  static const Color _loreCream = Color(0xFFF9EED7);
  static const Color _loreBorder = Color(0xFFB86B28);

  /// Maps FSRS repetitions & stability into a 1..5 TCG Star Level.
  static int starLevelForCard(VocabCard card) {
    if (card.state == CardState.newCard && card.repetitions == 0) return 1;
    if (card.stability >= 30.0 || card.repetitions >= 8) return 5;
    if (card.stability >= 14.0 || card.repetitions >= 5) return 4;
    if (card.stability >= 5.0 || card.repetitions >= 3) return 3;
    if (card.stability >= 1.0 || card.repetitions >= 1) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final palette = _TcgFramePalette.forCard(card);
    final starCount = starLevelForCard(card);
    final serialCode = 'CARD ${cardIndex + 1}/$totalCards';

    return Container(
      decoration: BoxDecoration(
        color: _darkOutline,
        border: Border.all(color: _darkOutline, width: 3),
      ),
      child: CustomPaint(
        painter: _TcgTexturedFramePainter(
          baseColor: palette.frameBase,
          textureColor: palette.frameTexture,
          highlightColor: palette.frameHighlight,
          shadowColor: palette.frameShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 2. Top Header Bar (Title Plate + Attribute Orb)
              _buildHeaderBar(context, px),
              const SizedBox(height: 5),

              // 3. Star Level Row (Right-Aligned 1..5 FSRS Mastery Stars)
              _buildStarLevelRow(starCount, px),
              const SizedBox(height: 6),

              // 4. Center Recessed Viewport (Main Study Content)
              Expanded(
                flex: 11,
                child: _buildCenterViewport(context, px),
              ),
              const SizedBox(height: 8),

              // 5. Bottom Lore / Effect Box + STAB / DIFF Stat Line
              Expanded(
                flex: 6,
                child: _buildLoreEffectBox(context, px),
              ),
              const SizedBox(height: 4),

              // 6. Outer Bottom Serial Code & Edition Stamp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    serialCode,
                    style: const TextStyle(
                      fontFamily: AppTheme.pixelDisplayFont,
                      fontFamilyFallback: AppTheme.fontFallback,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _darkOutline,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (card.isLeech) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: px.coral,
                            border: Border.all(color: _darkOutline, width: 1.5),
                          ),
                          child: const Text(
                            'LEECH',
                            style: TextStyle(
                              fontFamily: AppTheme.pixelDisplayFont,
                              fontFamilyFallback: AppTheme.fontFallback,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        'FSRS-4.5 • ${palette.editionTag}',
                        style: const TextStyle(
                          fontFamily: AppTheme.pixelDisplayFont,
                          fontFamilyFallback: AppTheme.fontFallback,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: _darkOutline,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBar(BuildContext context, PixelColors px) {
    final faceTag = isBack ? 'BACK • ĐÁP ÁN' : 'FRONT • CÂU HỎI';
    final hasDistinctLemma = card.lemma.isNotEmpty &&
        card.lemma.toLowerCase() != card.word.toLowerCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _loreCream,
        border: Border.all(color: _darkOutline, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x553B2214),
            offset: Offset(1.5, 1.5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasDistinctLemma ? '$faceTag • ${card.lemma}' : faceTag,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.pixelDisplayFont,
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isBack ? px.emerald : px.inkMuted,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  card.word,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.pixelDisplayFont,
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontSize: 17,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: _darkOutline,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PosAttributeOrb(partOfSpeech: card.partOfSpeech),
        ],
      ),
    );
  }

  Widget _buildStarLevelRow(int starCount, PixelColors px) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Subtle flip affordance badge on the left
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _loreCream.withValues(alpha: 0.85),
            border: Border.all(color: _darkOutline, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isBack ? Icons.flip_rounded : Icons.swipe_rounded,
                size: 11,
                color: _darkOutline,
              ),
              const SizedBox(width: 4),
              Text(
                isBack ? 'LẬT LẠI' : 'CHẠM / VUỐT',
                style: const TextStyle(
                  fontFamily: AppTheme.pixelDisplayFont,
                  fontFamilyFallback: AppTheme.fontFallback,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _darkOutline,
                ),
              ),
            ],
          ),
        ),
        // Right-aligned 1..5 red/gold pixel star orbs
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            starCount,
            (idx) => const Padding(
              padding: EdgeInsets.only(left: 4),
              child: _PixelLevelStarOrb(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCenterViewport(BuildContext context, PixelColors px) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: _darkOutline,
        border: Border.all(color: _darkOutline, width: 2.5),
      ),
      padding: const EdgeInsets.all(3),
      child: Container(
        decoration: const BoxDecoration(
          color: _viewportSlate,
          border: Border(
            top: BorderSide(color: _viewportSlateLight, width: 2.5),
            left: BorderSide(color: _viewportSlateLight, width: 2.5),
            right: BorderSide(color: _viewportSlateDark, width: 2.5),
            bottom: BorderSide(color: _viewportSlateDark, width: 2.5),
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(
            color: _viewportParchment,
            border: Border.all(color: _darkOutline, width: 2),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 24).clamp(0.0, 9999.0),
                    minWidth: double.infinity,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: isBack
                        ? _buildBackViewportContent(context, px, colorScheme)
                        : _buildFrontViewportContent(context, px),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFrontViewportContent(
    BuildContext context,
    PixelColors px,
  ) {
    return [
      Text(
        card.word,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: 32,
              color: _darkOutline,
              letterSpacing: 0.6,
            ),
      ),
      const SizedBox(height: 12),
      FlashcardPronunciationBar(
        card: card,
        targetAccent: targetAccent,
        onSpeakAccent: onSpeakAccent,
        showMic: false,
      ),
    ];
  }

  List<Widget> _buildBackViewportContent(
    BuildContext context,
    PixelColors px,
    ColorScheme colorScheme,
  ) {
    return [
      Text(
        card.translation,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFFB35E14),
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
      ),
      const SizedBox(height: 10),
      FlashcardPronunciationBar(
        card: card,
        targetAccent: targetAccent,
        onSpeakAccent: onSpeakAccent,
        showMic: true,
        comingSoon: true,
      ),
      if (relatedWords.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: px.surfaceAlt,
            border: Border.all(color: _darkOutline, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TỪ CÙNG GỐC TỪ (NHẤN ĐỂ ÔN KÈM):',
                style: TextStyle(
                  fontFamily: AppTheme.pixelDisplayFont,
                  fontFamilyFallback: AppTheme.fontFallback,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: px.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: relatedWords.map((rel) {
                  return PixelBadge(
                    icon: Icons.add_circle_outline,
                    label:
                        '${rel.card.word} (${rel.sharedRadicals.join(', ')})',
                    backgroundColor: colorScheme.tertiaryContainer,
                    onTap: () => onEnqueueRelated(rel.card),
                  );
                }).toList(growable: false),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _buildLoreEffectBox(BuildContext context, PixelColors px) {
    final String loreHeading = isBack ? '[NGỮ CẢNH]' : '[CLOZE]';
    final String loreBody;
    if (!showClozeContext) {
      loreBody = isBack
          ? (card.contextSentence.isNotEmpty
              ? card.contextSentence
              : 'Chưa có câu ví dụ ngữ cảnh cho thẻ này.')
          : 'Chế độ ẩn câu điền khuyết đang bật trong Cài đặt.';
    } else if (isBack) {
      loreBody = card.contextSentence.isNotEmpty
          ? card.contextSentence
          : 'Chưa có câu ví dụ ngữ cảnh cho thẻ này.';
    } else {
      loreBody = card.effectiveClozeSentence.isNotEmpty
          ? card.effectiveClozeSentence
          : 'Chạm hoặc vuốt thẻ để lật xem nghĩa Tiếng Việt.';
    }

    final stabText = '${card.stability.toStringAsFixed(1)}d';
    final diffText = card.difficulty.toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color: _darkOutline,
        border: Border.all(color: _darkOutline, width: 2),
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          color: _loreCream,
          border: Border.all(color: _loreBorder, width: 2.5),
        ),
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loreHeading,
                      style: const TextStyle(
                        fontFamily: AppTheme.pixelDisplayFont,
                        fontFamilyFallback: AppTheme.fontFallback,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: _loreBorder,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loreBody,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 12.5,
                            height: 1.32,
                            fontStyle: FontStyle.italic,
                            color: _darkOutline,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Crisp 1.5px ATK/DEF-style horizontal pixel divider
            Container(
              height: 1.5,
              color: _darkOutline.withValues(alpha: 0.75),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'STAB / $stabText   DIFF / $diffText',
                  style: const TextStyle(
                    fontFamily: AppTheme.pixelDisplayFont,
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _darkOutline,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-right elemental RPG Attribute Orb displaying the word's POS.
class _PosAttributeOrb extends StatelessWidget {
  final String partOfSpeech;

  const _PosAttributeOrb({required this.partOfSpeech});

  @override
  Widget build(BuildContext context) {
    final normalized = partOfSpeech.trim().toUpperCase();
    final shortLabel = normalized.isEmpty
        ? 'VOCAB'
        : (normalized.length > 6 ? normalized.substring(0, 6) : normalized);

    final (Color orbColor, Color orbLight) = switch (normalized) {
      'ADJ' || 'ADJECTIVE' => (
          const Color(0xFF3E8E35),
          const Color(0xFF81D177),
        ),
      'NOUN' => (
          const Color(0xFFD9822B),
          const Color(0xFFF7C572),
        ),
      'VERB' => (
          const Color(0xFFD94E4E),
          const Color(0xFFF49595),
        ),
      'ADV' || 'ADVERB' => (
          const Color(0xFF3E8EC4),
          const Color(0xFF8FD0FA),
        ),
      _ => (
          const Color(0xFF7B579A),
          const Color(0xFFC3A3DF),
        ),
    };

    return CustomPaint(
      painter: _PixelOctagonOrbPainter(
        fillColor: orbColor,
        highlightColor: orbLight,
        borderColor: const Color(0xFF3B2214),
      ),
      child: Container(
        constraints: const BoxConstraints(minWidth: 46, minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        alignment: Alignment.center,
        child: Text(
          shortLabel,
          style: const TextStyle(
            fontFamily: AppTheme.pixelDisplayFont,
            fontFamilyFallback: AppTheme.fontFallback,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
            shadows: [
              Shadow(
                color: Color(0xFF3B2214),
                offset: Offset(1, 1),
                blurRadius: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixelOctagonOrbPainter extends CustomPainter {
  final Color fillColor;
  final Color highlightColor;
  final Color borderColor;

  const _PixelOctagonOrbPainter({
    required this.fillColor,
    required this.highlightColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cut = 5.0;
    final path = Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height - cut)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..lineTo(0, cut)
      ..close();

    canvas.drawPath(path, Paint()..color = fillColor);

    // Top-left specular pixel gleam
    canvas.drawRect(
      Rect.fromLTWH(cut + 1, 3, size.width - (cut * 2) - 4, 3),
      Paint()..color = highlightColor.withValues(alpha: 0.85),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _PixelOctagonOrbPainter oldDelegate) =>
      fillColor != oldDelegate.fillColor;
}

/// 16-bit Pixel Art Red/Gold Star Orb (Yu-Gi-Oh! level star style).
class _PixelLevelStarOrb extends StatelessWidget {
  const _PixelLevelStarOrb();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 18),
      painter: _PixelLevelStarPainter(),
    );
  }
}

class _PixelLevelStarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Crimson orb fill
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFFC93B3B),
    );
    // Specular pixel dot top-left
    canvas.drawRect(
      Rect.fromLTWH(center.dx - 4, center.dy - 5, 2.5, 2.5),
      Paint()..color = const Color(0xFFF69999),
    );
    // Dark espresso outline
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF3B2214)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // Pixel gold 5-point star (chunky 16-bit cross + core)
    final starPaint = Paint()..color = const Color(0xFFFFD95A);
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 9, height: 3),
      starPaint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 3, height: 9),
      starPaint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 5, height: 5),
      starPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Textured 16-bit TCG card outer frame painter with inner pixel bevels and subtle dithering.
class _TcgTexturedFramePainter extends CustomPainter {
  final Color baseColor;
  final Color textureColor;
  final Color highlightColor;
  final Color shadowColor;

  const _TcgTexturedFramePainter({
    required this.baseColor,
    required this.textureColor,
    required this.highlightColor,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = baseColor);

    // Subtle 16-bit parchment/ochre pixel dither texture
    final texPaint = Paint()..color = textureColor.withValues(alpha: 0.35);
    const step = 12.0;
    for (double y = 4; y < size.height - 4; y += step) {
      final rowOffset = ((y ~/ step).isEven) ? 0.0 : step / 2;
      for (double x = 4 + rowOffset; x < size.width - 4; x += step) {
        canvas.drawRect(Rect.fromLTWH(x, y, 3, 3), texPaint);
      }
    }

    // Inner top-left bright bevel
    final hl = Paint()..color = highlightColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 3), hl);
    canvas.drawRect(Rect.fromLTWH(0, 0, 3, size.height), hl);

    // Inner bottom-right shadow bevel
    final sh = Paint()..color = shadowColor;
    canvas.drawRect(Rect.fromLTWH(0, size.height - 3, size.width, 3), sh);
    canvas.drawRect(Rect.fromLTWH(size.width - 3, 0, 3, size.height), sh);
  }

  @override
  bool shouldRepaint(covariant _TcgTexturedFramePainter oldDelegate) =>
      baseColor != oldDelegate.baseColor ||
      textureColor != oldDelegate.textureColor;
}
