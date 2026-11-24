import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Subtle 16-bit wooden plank / pixel grid background for Stardew Valley atmosphere.
class WoodPlankBackground extends StatelessWidget {
  final Widget child;

  const WoodPlankBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    return CustomPaint(
      painter: _WoodPlankPainter(
        baseColor: px.canvas,
        plankColor: px.canvasAlt,
        seamColor: px.shadow,
      ),
      child: child,
    );
  }
}

class _WoodPlankPainter extends CustomPainter {
  final Color baseColor;
  final Color plankColor;
  final Color seamColor;

  const _WoodPlankPainter({
    required this.baseColor,
    required this.plankColor,
    required this.seamColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);

    const plankHeight = 28.0;
    final altPaint = Paint()..color = plankColor.withValues(alpha: 0.42);
    final seamPaint = Paint()
      ..color = seamColor.withValues(alpha: 0.45)
      ..strokeWidth = 2;

    for (double y = 0; y < size.height; y += plankHeight) {
      final row = (y ~/ plankHeight);
      if (row.isEven) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, plankHeight), altPaint);
      }
      canvas.drawLine(Offset(0, y), Offset(size.width, y), seamPaint);

      // Staggered vertical plank joints
      final offset = (row % 3) * 72.0 + 48.0;
      for (double x = offset; x < size.width; x += 180.0) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, y + plankHeight),
          seamPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WoodPlankPainter oldDelegate) => false;
}

/// Stardew Valley 9-slice style double-beveled pixel panel:
/// - Outer dark espresso outline (#2A160C)
/// - Inner top/left highlight bevel (#E8C391) & bottom/right shadow bevel (#6B3E21)
/// - Hard pixel drop shadow (blurRadius: 0)
class PixelCard extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderWidth;
  final Offset shadowOffset;
  final bool woodFrame;
  final bool showRivets;
  final VoidCallback? onTap;

  const PixelCard({
    super.key,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.borderWidth = 3.0,
    this.shadowOffset = const Offset(4, 4),
    this.woodFrame = false,
    this.showRivets = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final bg = backgroundColor ?? px.surface;
    final outerBorder = borderColor ?? px.border;

    Widget innerContent = Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: px.woodHighlight, width: 2.5),
          left: BorderSide(color: px.woodHighlight, width: 2.5),
          right: BorderSide(color: px.woodShadow, width: 2.5),
          bottom: BorderSide(color: px.woodShadow, width: 2.5),
        ),
      ),
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          if (showRivets) ...[
            Positioned(top: 5, left: 5, child: _PixelRivet(px: px)),
            Positioned(top: 5, right: 5, child: _PixelRivet(px: px)),
            Positioned(bottom: 5, left: 5, child: _PixelRivet(px: px)),
            Positioned(bottom: 5, right: 5, child: _PixelRivet(px: px)),
          ],
        ],
      ),
    );

    if (woodFrame) {
      innerContent = Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: px.wood,
          border: Border(
            top: BorderSide(color: px.woodLight, width: 2),
            left: BorderSide(color: px.woodLight, width: 2),
            right: BorderSide(color: px.woodShadow, width: 2),
            bottom: BorderSide(color: px.woodShadow, width: 2),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: px.border, width: 2),
          ),
          child: innerContent,
        ),
      );
    }

    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: outerBorder,
        border: Border.all(color: outerBorder, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: px.shadow,
            offset: shadowOffset,
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: innerContent,
    );

    if (onTap == null) return box;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: box),
    );
  }
}

class _PixelRivet extends StatelessWidget {
  final PixelColors px;

  const _PixelRivet({required this.px});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: px.primary,
        border: Border.all(color: px.border, width: 1.5),
      ),
    );
  }
}

/// Tactile 16-bit RPG Button with bright top bevel edge, dark bottom lip,
/// and physical press-down (`translateY(2px)`) feedback.
class PixelButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final bool expand;
  final EdgeInsetsGeometry padding;
  final String? sublabel;

  const PixelButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.expand = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.sublabel,
  });

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final enabled = widget.onPressed != null;
    final bg =
        enabled ? (widget.backgroundColor ?? px.primary) : px.surfaceAlt;
    final fg = enabled
        ? (widget.foregroundColor ??
            (bg == px.primary || bg == px.cardParchment || bg == px.surfaceAlt
                ? px.ink
                : Colors.white))
        : px.inkMuted;
    final outerBorder = widget.borderColor ?? px.border;

    final topHighlight = Color.lerp(bg, Colors.white, 0.35)!;
    final bottomLip = Color.lerp(bg, Colors.black, 0.32)!;
    final shiftY = _pressed && enabled ? 2.0 : 0.0;
    final shadowY = _pressed && enabled ? 1.0 : 3.0;

    final button = GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 55),
          transform: Matrix4.translationValues(0, shiftY, 0),
          decoration: BoxDecoration(
            color: outerBorder,
            border: Border.all(color: outerBorder, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: px.shadow,
                offset: Offset(0, shadowY),
                blurRadius: 0,
              ),
            ],
          ),
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                top: BorderSide(color: topHighlight, width: 2.5),
                left: BorderSide(color: topHighlight, width: 2),
                right: BorderSide(color: bottomLip, width: 2),
                bottom: BorderSide(
                  color: bottomLip,
                  width: _pressed && enabled ? 1.5 : 4.0,
                ),
              ),
            ),
            child: Row(
              mainAxisSize:
                  widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 17, color: fg),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.pixelDisplayFont,
                          fontFamilyFallback: AppTheme.fontFallback,
                          color: fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (widget.sublabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.sublabel!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.pixelDisplayFont,
                            fontFamilyFallback: AppTheme.fontFallback,
                            color: fg.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// Chunky pixel RPG trait/stat badge with beveled border.
class PixelBadge extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconData? icon;
  final VoidCallback? onTap;

  const PixelBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final bg = backgroundColor ?? px.surfaceAlt;
    final fg = foregroundColor ?? px.ink;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: px.border, width: 2),
        boxShadow: [
          BoxShadow(
            color: px.woodShadow.withValues(alpha: 0.45),
            offset: const Offset(1.5, 1.5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.pixelDisplayFont,
              fontFamilyFallback: AppTheme.fontFallback,
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: content),
    );
  }
}

/// Chunky Stardew RPG XP / Stamina / Health Bar inside a wooden trough.
class PixelProgressBar extends StatelessWidget {
  final double progress;
  final Color? fillColor;
  final int segments;
  final double height;

  const PixelProgressBar({
    super.key,
    required this.progress,
    this.fillColor,
    this.segments = 16,
    this.height = 18,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final clamped = progress.clamp(0.0, 1.0);
    final filledCount = (clamped * segments).round();
    final activeColor = fillColor ?? px.emerald;
    final activeHighlight = Color.lerp(activeColor, Colors.white, 0.35)!;

    return Container(
      height: height,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: px.woodShadow,
        border: Border.all(color: px.border, width: 2.5),
      ),
      child: Row(
        children: List.generate(segments, (index) {
          final isFilled = index < filledCount;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index == segments - 1 ? 0 : 2),
              decoration: BoxDecoration(
                color: isFilled ? activeColor : px.canvas.withValues(alpha: 0.6),
                border: isFilled
                    ? Border(
                        top: BorderSide(color: activeHighlight, width: 2),
                      )
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Retro RPG section header with a beveled pixel icon plaque.
class PixelSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? accentColor;
  final Widget? trailing;

  const PixelSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.accentColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final accent = accentColor ?? px.primary;
    final iconColor = accent == px.primary ? px.ink : Colors.white;

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent,
            border: Border.all(color: px.border, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: px.shadow.withValues(alpha: 0.45),
                offset: const Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Physical 3D double-sided Y-axis RPG Quest Card Flip widget:
/// - Ornate wooden/gold pixel frame with 4 corner rivets on parchment (#FFF3D6)
/// - Grounded 2D dynamic shadow outside the 3D Matrix4 (zero CanvasKit 90° blur glitch)
/// - Safe perspective depth & ±π/2 clamp for zero blank frames in both L→R and R→L flips
/// - Tap or interactive horizontal drag scrubbing (90° threshold + spring settle)
/// - Diagonal light sheen sweeping proportionally across 0° → 180°
class PixelFlipCard extends StatefulWidget {
  final Widget front;
  final Widget back;
  final bool isFlipped;
  final ValueChanged<bool>? onFlipChanged;
  final Duration duration;

  const PixelFlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.isFlipped,
    this.onFlipChanged,
    this.duration = const Duration(milliseconds: 440),
  });

  @override
  State<PixelFlipCard> createState() => _PixelFlipCardState();
}

class _PixelFlipCardState extends State<PixelFlipCard>
    with SingleTickerProviderStateMixin {
  static const Curve _flipCurve = Cubic(0.4, 0.0, 0.2, 1.0);

  late final AnimationController _flipCtrl;
  bool _isDragging = false;
  double _dragStartValue = 0.0;
  double _dragAccumulatedDx = 0.0;
  double _flipDirection = 1.0;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.isFlipped ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant PixelFlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && widget.isFlipped != oldWidget.isFlipped) {
      _animateToTarget(widget.isFlipped);
    }
  }

  void _animateToTarget(bool flipped, {Curve? curve}) {
    final target = flipped ? 1.0 : 0.0;
    _flipCtrl.animateTo(
      target,
      duration: widget.duration,
      curve: curve ?? _flipCurve,
    );
  }

  void _handleTap() {
    if (_isDragging) return;
    _flipDirection = 1.0;
    widget.onFlipChanged?.call(!widget.isFlipped);
  }

  void _handleDragStart(DragStartDetails details) {
    _isDragging = true;
    _flipCtrl.stop();
    _dragStartValue = _flipCtrl.value.clamp(0.0, 1.0);
    _dragAccumulatedDx = 0.0;
  }

  void _handleDragUpdate(DragUpdateDetails details, double cardWidth) {
    if (!_isDragging || cardWidth <= 0) return;
    _dragAccumulatedDx += details.delta.dx;

    if (_dragAccumulatedDx.abs() > 4) {
      if (_dragStartValue < 0.5) {
        _flipDirection = _dragAccumulatedDx < 0 ? 1.0 : -1.0;
        _flipCtrl.value =
            (_dragAccumulatedDx.abs() / (cardWidth * 0.55)).clamp(0.0, 1.0);
      } else {
        _flipDirection = _dragAccumulatedDx > 0 ? 1.0 : -1.0;
        _flipCtrl.value =
            (1.0 - (_dragAccumulatedDx.abs() / (cardWidth * 0.55)))
                .clamp(0.0, 1.0);
      }
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;

    final vx = details.velocity.pixelsPerSecond.dx;
    final current = _flipCtrl.value.clamp(0.0, 1.0);
    final bool shouldFlip =
        vx.abs() > 450 ? (_dragStartValue < 0.5) : (current >= 0.5);

    if (shouldFlip != widget.isFlipped) {
      widget.onFlipChanged?.call(shouldFlip);
    }
    _animateToTarget(shouldFlip, curve: _flipCurve);
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final perspectiveDepth = math.max(1600.0, cardWidth * 3.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onHorizontalDragStart: _handleDragStart,
          onHorizontalDragUpdate: (d) => _handleDragUpdate(d, cardWidth),
          onHorizontalDragEnd: _handleDragEnd,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedBuilder(
              animation: _flipCtrl,
              builder: (context, _) {
                final t = _flipCtrl.value.clamp(0.0, 1.0);
                final isBack = t >= 0.5;

                const halfPiSafe = (math.pi / 2) - 0.035;
                final double baseAngle = isBack
                    ? ((t - 1.0) * math.pi).clamp(-halfPiSafe, 0.0)
                    : (t * math.pi).clamp(0.0, halfPiSafe);
                final double faceAngle = baseAngle * _flipDirection;

                final lift = math.sin(t * math.pi).clamp(0.0, 1.0);
                final scale = 1.0 + 0.03 * lift;

                final shadowScaleX =
                    (math.cos(faceAngle).abs() * scale).clamp(0.06, 1.05);
                final shadowOffsetY = 6.0 + 10.0 * lift;

                final sheenProgress = _flipDirection > 0 ? t : (1.0 - t);
                final sheenOpacity = (0.16 * lift).clamp(0.0, 0.16);

                final matrix = Matrix4.identity()
                  ..setEntry(3, 2, 1.0 / perspectiveDepth)
                  ..scaleByDouble(scale, scale, 1.0, 1.0)
                  ..rotateY(faceAngle);

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Grounded 2D pixel drop shadow outside 3D Matrix4
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Transform.translate(
                          offset: Offset(4, shadowOffsetY),
                          child: Transform.scale(
                            scaleX: shadowScaleX,
                            scaleY: scale,
                            child: ColoredBox(
                              color: px.shadow.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Transform(
                      alignment: Alignment.center,
                      transform: matrix,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: px.wood,
                          border: Border.all(color: px.border, width: 3),
                        ),
                        padding: const EdgeInsets.all(5),
                        child: Container(
                          decoration: BoxDecoration(
                            color: px.cardParchment,
                            border: Border.all(
                              color: isBack ? px.primaryBorder : px.border,
                              width: 2.5,
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: px.woodHighlight,
                                  width: 2.5,
                                ),
                                left: BorderSide(
                                  color: px.woodHighlight,
                                  width: 2.5,
                                ),
                                right: BorderSide(
                                  color: px.woodShadow,
                                  width: 2.5,
                                ),
                                bottom: BorderSide(
                                  color: px.woodShadow,
                                  width: 2.5,
                                ),
                              ),
                            ),
                            child: CustomPaint(
                              foregroundPainter: sheenOpacity > 0.005
                                  ? _CardSheenPainter(
                                      progress: sheenProgress,
                                      opacity: sheenOpacity,
                                    )
                                  : null,
                              child: Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(22),
                                    child: IndexedStack(
                                      index: isBack ? 1 : 0,
                                      alignment: Alignment.center,
                                      sizing: StackFit.loose,
                                      children: [
                                        IgnorePointer(
                                          ignoring: isBack,
                                          child: widget.front,
                                        ),
                                        IgnorePointer(
                                          ignoring: !isBack,
                                          child: widget.back,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: _PixelRivet(px: px),
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: _PixelRivet(px: px),
                                  ),
                                  Positioned(
                                    bottom: 6,
                                    left: 6,
                                    child: _PixelRivet(px: px),
                                  ),
                                  Positioned(
                                    bottom: 6,
                                    right: 6,
                                    child: _PixelRivet(px: px),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _CardSheenPainter extends CustomPainter {
  final double progress;
  final double opacity;

  _CardSheenPainter({
    required this.progress,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sheenPos = -1.2 + 2.4 * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(sheenPos - 0.5, -1.0),
        end: Alignment(sheenPos + 0.5, 1.0),
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: opacity),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _CardSheenPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.opacity != opacity;
  }
}
