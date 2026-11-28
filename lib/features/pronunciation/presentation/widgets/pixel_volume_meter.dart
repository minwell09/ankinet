import 'package:flutter/material.dart';

import '../../../../core/config/app_theme.dart';
import '../../domain/entities/pronunciation_result.dart';

/// Live 8-bit segmented pixel volume meter inside a wooden trough,
/// matching the Cozy 16-bit Stardew Valley RPG aesthetic.
class PixelVolumeMeter extends StatelessWidget {
  final double level; // 0.0 .. 1.0
  final int segments;
  final String? statusLabel;

  const PixelVolumeMeter({
    super.key,
    required this.level,
    this.segments = 16,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final clamped = level.clamp(0.0, 1.0);
    final activeCount = (clamped * segments).round().clamp(1, segments);

    Color segmentColor(int index) {
      final ratio = (index + 1) / segments;
      if (ratio <= 0.58) return PronunciationColors.accurate;
      if (ratio <= 0.82) return PronunciationColors.close;
      return PronunciationColors.recordingCoral;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: px.surfaceAlt,
        border: Border.all(color: px.border, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: px.shadow.withValues(alpha: 0.4),
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: PronunciationColors.recordingCoral,
                  border: Border.all(color: px.border, width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'REC',
                style: TextStyle(
                  fontFamily: AppTheme.pixelDisplayFont,
                  fontFamilyFallback: AppTheme.fontFallback,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: PronunciationColors.recordingCoral,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusLabel ?? 'Đang ghi âm... Nhấn DỪNG GHI để chấm điểm',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: px.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 18,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: px.woodShadow,
              border: Border.all(color: px.border, width: 2),
            ),
            child: Row(
              children: List.generate(segments, (index) {
                final isLit = index < activeCount;
                final color = segmentColor(index);
                final highlight = Color.lerp(color, Colors.white, 0.35)!;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                      right: index == segments - 1 ? 0 : 2,
                    ),
                    decoration: BoxDecoration(
                      color: isLit ? color : px.canvas.withValues(alpha: 0.55),
                      border: isLit
                          ? Border(
                              top: BorderSide(color: highlight, width: 2),
                            )
                          : null,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
