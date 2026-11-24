import 'package:flutter/material.dart';

/// Cozy 16-bit Pixel Art RPG Palette inspired by Stardew Valley:
/// Warm wood frames, parchment surfaces, espresso ink, and vibrant harvest accents.
@immutable
class PixelColors extends ThemeExtension<PixelColors> {
  final Color canvas; // Deep warm wood / soil brown (#2B1D14)
  final Color canvasAlt; // Subtle plank stripe (#3A2518)
  final Color wood; // Medium oak wood (#8C5230)
  final Color woodLight; // Oak highlight (#A8653B)
  final Color woodHighlight; // Inner bevel top/left (#E8C391)
  final Color woodShadow; // Inner bevel bottom/right (#6B3E21)
  final Color surface; // Warm parchment (#F6E6C9)
  final Color cardParchment; // Lighter quest parchment (#FFF3D6)
  final Color surfaceAlt; // Recessed parchment / soil slot (#E8D5B5)
  final Color border; // Outer dark espresso outline (#2A160C)
  final Color shadow; // Hard drop shadow (#1A0D06)
  final Color ink; // Primary espresso text on parchment (#3B2214)
  final Color inkMuted; // Secondary chestnut text / IPA (#6E4730)
  final Color inkOnWood; // Warm cream text on dark wood (#FFF8E7)
  final Color primary; // Golden harvest amber (#F2A93B)
  final Color primaryBorder; // Amber dark border (#7A4419)
  final Color emerald; // Stardew leaf green (#56A84B)
  final Color gold; // Warm honey orange / HARD (#E88D38)
  final Color coral; // Retro coral red / AGAIN (#D94E4E)
  final Color cyan; // Sky blue / EASY (#4B9CD3)
  final Color cropEmpty; // Empty tilled soil (#D9C3A3)
  final Color cropLush; // Lush crop green (#4E9A3E)

  const PixelColors({
    required this.canvas,
    required this.canvasAlt,
    required this.wood,
    required this.woodLight,
    required this.woodHighlight,
    required this.woodShadow,
    required this.surface,
    required this.cardParchment,
    required this.surfaceAlt,
    required this.border,
    required this.shadow,
    required this.ink,
    required this.inkMuted,
    required this.inkOnWood,
    required this.primary,
    required this.primaryBorder,
    required this.emerald,
    required this.gold,
    required this.coral,
    required this.cyan,
    required this.cropEmpty,
    required this.cropLush,
  });

  static const stardew = PixelColors(
    canvas: Color(0xFF2B1D14),
    canvasAlt: Color(0xFF3A2518),
    wood: Color(0xFF8C5230),
    woodLight: Color(0xFFA8653B),
    woodHighlight: Color(0xFFE8C391),
    woodShadow: Color(0xFF6B3E21),
    surface: Color(0xFFF6E6C9),
    cardParchment: Color(0xFFFFF3D6),
    surfaceAlt: Color(0xFFE8D5B5),
    border: Color(0xFF2A160C),
    shadow: Color(0xFF1A0D06),
    ink: Color(0xFF3B2214),
    inkMuted: Color(0xFF6E4730),
    inkOnWood: Color(0xFFFFF8E7),
    primary: Color(0xFFF2A93B),
    primaryBorder: Color(0xFF7A4419),
    emerald: Color(0xFF56A84B),
    gold: Color(0xFFE88D38),
    coral: Color(0xFFD94E4E),
    cyan: Color(0xFF4B9CD3),
    cropEmpty: Color(0xFFD9C3A3),
    cropLush: Color(0xFF4E9A3E),
  );

  static PixelColors of(BuildContext context) {
    return Theme.of(context).extension<PixelColors>() ?? stardew;
  }

  @override
  PixelColors copyWith({
    Color? canvas,
    Color? canvasAlt,
    Color? wood,
    Color? woodLight,
    Color? woodHighlight,
    Color? woodShadow,
    Color? surface,
    Color? cardParchment,
    Color? surfaceAlt,
    Color? border,
    Color? shadow,
    Color? ink,
    Color? inkMuted,
    Color? inkOnWood,
    Color? primary,
    Color? primaryBorder,
    Color? emerald,
    Color? gold,
    Color? coral,
    Color? cyan,
    Color? cropEmpty,
    Color? cropLush,
  }) {
    return PixelColors(
      canvas: canvas ?? this.canvas,
      canvasAlt: canvasAlt ?? this.canvasAlt,
      wood: wood ?? this.wood,
      woodLight: woodLight ?? this.woodLight,
      woodHighlight: woodHighlight ?? this.woodHighlight,
      woodShadow: woodShadow ?? this.woodShadow,
      surface: surface ?? this.surface,
      cardParchment: cardParchment ?? this.cardParchment,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      shadow: shadow ?? this.shadow,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkOnWood: inkOnWood ?? this.inkOnWood,
      primary: primary ?? this.primary,
      primaryBorder: primaryBorder ?? this.primaryBorder,
      emerald: emerald ?? this.emerald,
      gold: gold ?? this.gold,
      coral: coral ?? this.coral,
      cyan: cyan ?? this.cyan,
      cropEmpty: cropEmpty ?? this.cropEmpty,
      cropLush: cropLush ?? this.cropLush,
    );
  }

  @override
  PixelColors lerp(ThemeExtension<PixelColors>? other, double t) {
    if (other is! PixelColors) return this;
    return PixelColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasAlt: Color.lerp(canvasAlt, other.canvasAlt, t)!,
      wood: Color.lerp(wood, other.wood, t)!,
      woodLight: Color.lerp(woodLight, other.woodLight, t)!,
      woodHighlight: Color.lerp(woodHighlight, other.woodHighlight, t)!,
      woodShadow: Color.lerp(woodShadow, other.woodShadow, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      cardParchment: Color.lerp(cardParchment, other.cardParchment, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkOnWood: Color.lerp(inkOnWood, other.inkOnWood, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryBorder: Color.lerp(primaryBorder, other.primaryBorder, t)!,
      emerald: Color.lerp(emerald, other.emerald, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      cropEmpty: Color.lerp(cropEmpty, other.cropEmpty, t)!,
      cropLush: Color.lerp(cropLush, other.cropLush, t)!,
    );
  }
}

/// Square 16-bit Pixel Slider Thumb for Stardew-style Settings controls.
class PixelSliderThumbShape extends SliderComponentShape {
  final double size;

  const PixelSliderThumbShape({this.size = 18});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(center: center, width: size, height: size);

    // Outer dark espresso outline
    canvas.drawRect(rect, Paint()..color = PixelColors.stardew.border);
    // Inner golden harvest fill
    final inner = rect.deflate(2);
    canvas.drawRect(inner, Paint()..color = PixelColors.stardew.primary);
    // Top-left bright bevel highlight
    final hlPaint = Paint()..color = PixelColors.stardew.woodHighlight;
    canvas.drawRect(
      Rect.fromLTWH(inner.left, inner.top, inner.width, 2),
      hlPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(inner.left, inner.top, 2, inner.height),
      hlPaint,
    );
    // Bottom-right shadow bevel
    final shPaint = Paint()..color = PixelColors.stardew.primaryBorder;
    canvas.drawRect(
      Rect.fromLTWH(inner.left, inner.bottom - 2, inner.width, 2),
      shPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(inner.right - 2, inner.top, 2, inner.height),
      shPaint,
    );
  }
}

class AppTheme {
  static const String pixelDisplayFont = 'Pixelify Sans';
  static const String bodyFont = 'Chakra Petch';
  static const List<String> fontFallback = [
    'JetBrains Mono',
    'Courier New',
    'monospace',
  ];

  static ThemeData get stardewTheme {
    const px = PixelColors.stardew;

    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: px.primary,
      onPrimary: px.ink,
      primaryContainer: const Color(0xFFFFE5A8),
      onPrimaryContainer: px.ink,
      secondary: px.cyan,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFD6EEF8),
      onSecondaryContainer: px.ink,
      tertiary: px.emerald,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFD9F0CE),
      onTertiaryContainer: px.ink,
      error: px.coral,
      onError: Colors.white,
      errorContainer: const Color(0xFFFAD3D3),
      onErrorContainer: px.ink,
      surface: px.surface,
      onSurface: px.ink,
      surfaceContainerHighest: px.surfaceAlt,
      onSurfaceVariant: px.inkMuted,
      outline: px.border,
    );

    final baseText = ThemeData.light().textTheme.apply(
          fontFamily: bodyFont,
          fontFamilyFallback: fontFallback,
          bodyColor: px.ink,
          displayColor: px.ink,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: px.canvas,
      fontFamily: bodyFont,
      fontFamilyFallback: fontFallback,
      textTheme: baseText.copyWith(
        headlineMedium: baseText.headlineMedium?.copyWith(
          fontFamily: pixelDisplayFont,
          fontFamilyFallback: fontFallback,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: px.ink,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontFamily: pixelDisplayFont,
          fontFamilyFallback: fontFallback,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: px.ink,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontFamily: pixelDisplayFont,
          fontFamilyFallback: fontFallback,
          fontWeight: FontWeight.w700,
          color: px.ink,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontFamily: pixelDisplayFont,
          fontFamilyFallback: fontFallback,
          fontWeight: FontWeight.w700,
          color: px.ink,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(
          color: px.ink,
          fontWeight: FontWeight.w500,
        ),
        bodySmall: baseText.bodySmall?.copyWith(
          color: px.inkMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      extensions: const [px],
      appBarTheme: AppBarTheme(
        backgroundColor: px.wood,
        foregroundColor: px.inkOnWood,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Color(0xFFFFF8E7)),
        titleTextStyle: const TextStyle(
          fontFamily: pixelDisplayFont,
          fontFamilyFallback: fontFallback,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFFF8E7),
          letterSpacing: 0.8,
        ),
        shape: Border(
          bottom: BorderSide(color: px.border, width: 3),
        ),
      ),
      cardTheme: CardThemeData(
        color: px.surface,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: px.border, width: 2.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: px.primary,
          foregroundColor: px.ink,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: px.primaryBorder, width: 2.5),
          ),
          textStyle: const TextStyle(
            fontFamily: pixelDisplayFont,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: px.ink,
          backgroundColor: px.cardParchment,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          side: BorderSide(color: px.border, width: 2.5),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontFamily: pixelDisplayFont,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: px.primaryBorder,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontFamily: pixelDisplayFont,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: px.surfaceAlt,
        selectedColor: px.primary,
        side: BorderSide(color: px.border, width: 2),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        labelStyle: TextStyle(
          fontFamily: pixelDisplayFont,
          fontFamilyFallback: fontFallback,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: px.ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: px.cardParchment,
        labelStyle: TextStyle(color: px.inkMuted, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: px.inkMuted.withValues(alpha: 0.8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: px.woodShadow, width: 2.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: px.woodShadow, width: 2.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: px.primaryBorder, width: 3),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return px.primary;
            return px.woodShadow;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return px.ink;
            return px.inkOnWood;
          }),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: px.border, width: 2),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: pixelDisplayFont,
              fontFamilyFallback: fontFallback,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return px.emerald;
          return px.cardParchment;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: BorderSide(color: px.border, width: 2.5),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return px.primary;
          return px.surfaceAlt;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return px.emerald;
          return px.woodShadow;
        }),
        trackOutlineColor: WidgetStatePropertyAll(px.border),
        trackOutlineWidth: const WidgetStatePropertyAll(2),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 10,
        activeTrackColor: px.emerald,
        inactiveTrackColor: px.woodShadow,
        thumbColor: px.primary,
        overlayColor: px.primary.withValues(alpha: 0.2),
        trackShape: const RectangularSliderTrackShape(),
        thumbShape: const PixelSliderThumbShape(size: 20),
        tickMarkShape: SliderTickMarkShape.noTickMark,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: px.wood,
        contentTextStyle: const TextStyle(
          fontFamily: bodyFont,
          fontFamilyFallback: fontFallback,
          color: Color(0xFFFFF8E7),
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: px.primary, width: 3),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(
        color: px.woodShadow.withValues(alpha: 0.45),
        thickness: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: px.primary,
        linearTrackColor: px.woodShadow,
      ),
    );
  }

  static ThemeData get lightTheme => stardewTheme;
  static ThemeData get darkTheme => stardewTheme;
}
