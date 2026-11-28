import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../pronunciation/domain/entities/pronunciation_result.dart';
import '../../data/repositories/stats_repository.dart';
import '../../domain/entities/study_stats.dart';
import '../providers/stats_provider.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(studyStatsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('THỐNG KÊ'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(studyStatsProvider),
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: PixelCard(
            margin: const EdgeInsets.all(20),
            child: Text('Error: $err'),
          ),
        ),
        data: (stats) => _StatsContent(stats: stats),
      ),
    );
  }
}

class _StatsContent extends StatelessWidget {
  final StudyStats stats;

  const _StatsContent({required this.stats});

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final retentionPct = (stats.trueRetention30d * 100).toStringAsFixed(1);
    final retrievabilityPct =
        (stats.averageRetrievability * 100).toStringAsFixed(1);
    final avgPron = stats.averagePronunciationScore;
    final avgPronDisplay = avgPron != null
        ? '${avgPron.round()}% • ${PronunciationResult.rankForScore(avgPron)}'
        : '—';
    final avgPronAccent = avgPron != null
        ? PronunciationColors.forScore(avgPron)
        : px.emerald;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        // Row 1: 2-Column Compact HUD Cards
        Row(
          children: [
            Expanded(
              child: _CompactHudCard(
                emoji: '🎯',
                title: 'TỈ LỆ NHỚ (30D)',
                value: '$retentionPct%',
                subtitle: '(${stats.totalReviews30d} lượt)',
                valueColor: px.emerald,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CompactHudCard(
                emoji: '🔥',
                title: 'STREAK',
                value: '${stats.currentStreakDays} NGÀY',
                subtitle: 'Hôm nay: ${stats.reviewsToday} lượt',
                valueColor: px.gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 2: Full-width Retrievability Strip
        PixelCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              const Text('📈', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'RETRIEVABILITY TRUNG BÌNH',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 12.5,
                        letterSpacing: 0.3,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$retrievabilityPct%',
                style: TextStyle(
                  fontFamily: AppTheme.monoFont,
                  fontFamilyFallback: AppTheme.fontFallback,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: px.cyan,
                ),
              ),
            ],
          ),
        ),

        // Row 3: Crop Tiles Heatmap ("Vườn ôn tập") immediately in primary viewport
        PixelCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🌱', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'VƯỜN ÔN TẬP (20 TUẦN)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _HeatmapLegend(px: px),
                ],
              ),
              const SizedBox(height: 10),
              _ReviewHeatmapGrid(dailyCounts: stats.dailyReviewCounts),
            ],
          ),
        ),

        // Below the fold: Pronunciation & Weak Phonemes
        PixelCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelSectionHeader(
                title: 'PHÁT ÂM & ÂM CẦN LUYỆN',
                icon: Icons.record_voice_over_rounded,
                accentColor: avgPronAccent,
                trailing: PixelBadge(
                  label: avgPronDisplay,
                  backgroundColor: colorScheme.primaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              _WeakPhonemesSection(weakPhonemes: stats.weakPhonemes),
            ],
          ),
        ),

        // Card State Distribution
        PixelCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelSectionHeader(
                title: 'PHÂN BỐ THẺ (TỔNG ${stats.totalCards})',
                icon: Icons.bar_chart_rounded,
                accentColor: px.primary,
              ),
              const SizedBox(height: 12),
              _StateBarRow(
                label: 'Thẻ mới (Chưa học)',
                count: stats.newCardsCount,
                total: stats.totalCards,
                color: px.primary,
              ),
              _StateBarRow(
                label: 'Đang học / Học lại',
                count: stats.learningCardsCount,
                total: stats.totalCards,
                color: px.gold,
              ),
              _StateBarRow(
                label: 'Đã vào lịch FSRS (Review)',
                count: stats.reviewCardsCount,
                total: stats.totalCards,
                color: px.emerald,
              ),
              _StateBarRow(
                label: 'Thẻ Leech (Hay quên)',
                count: stats.leechCardsCount,
                total: stats.totalCards,
                color: px.coral,
              ),
            ],
          ),
        ),

        // 14-day Forecast
        PixelCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelSectionHeader(
                title: 'DỰ BÁO ĐẾN HẠN (14 NGÀY)',
                icon: Icons.calendar_today_rounded,
                accentColor: px.cyan,
              ),
              const SizedBox(height: 12),
              _ForecastChart(upcoming: stats.upcomingDueByDayOffset),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactHudCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String value;
  final String subtitle;
  final Color valueColor;

  const _CompactHudCard({
    required this.emoji,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    return PixelCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.pixelDisplayFont,
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    color: px.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.monoFont,
              fontFamilyFallback: AppTheme.fontFallback,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: px.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatmapLegend extends StatelessWidget {
  final PixelColors px;

  const _HeatmapLegend({required this.px});

  @override
  Widget build(BuildContext context) {
    final colors = [
      px.cropEmpty,
      const Color(0xFFB4D38B),
      const Color(0xFF7FC05A),
      px.cropLush,
      const Color(0xFF2F7A27),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ít',
          style: TextStyle(fontSize: 10.5, color: px.inkMuted),
        ),
        const SizedBox(width: 4),
        for (final c in colors)
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: c,
              border: Border.all(
                color: px.border.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
          ),
        const SizedBox(width: 4),
        Text(
          'Nhiều',
          style: TextStyle(fontSize: 10.5, color: px.inkMuted),
        ),
      ],
    );
  }
}

class _ReviewHeatmapGrid extends StatelessWidget {
  final Map<String, int> dailyCounts;

  const _ReviewHeatmapGrid({required this.dailyCounts});

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const int weeks = 20;
    const int totalDays = weeks * 7;
    final startDay = today.subtract(const Duration(days: totalDays - 1));

    Color cellColor(int count) {
      if (count <= 0) return px.cropEmpty;
      if (count < 5) return const Color(0xFFB4D38B);
      if (count < 15) return const Color(0xFF7FC05A);
      if (count < 30) return px.cropLush;
      return const Color(0xFF2F7A27);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        final rawCell = (constraints.maxWidth - gap * (weeks - 1)) / weeks;
        final cellSize = rawCell.clamp(10.0, 18.0);
        final gridWidth = weeks * cellSize + (weeks - 1) * gap;

        final grid = Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(weeks, (wIdx) {
            return Padding(
              padding: EdgeInsets.only(right: wIdx == weeks - 1 ? 0 : gap),
              child: Column(
                children: List.generate(7, (dIdx) {
                  final dayOffset = wIdx * 7 + dIdx;
                  final dt = startDay.add(Duration(days: dayOffset));
                  final key = StatsRepository.formatDayKey(dt);
                  final cnt = dailyCounts[key] ?? 0;
                  return Tooltip(
                    message: '$key: $cnt lượt ôn',
                    child: Container(
                      margin: EdgeInsets.only(bottom: dIdx == 6 ? 0 : gap),
                      width: cellSize,
                      height: cellSize,
                      decoration: BoxDecoration(
                        color: cellColor(cnt),
                        border: Border.all(
                          color: px.border.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        );

        if (gridWidth <= constraints.maxWidth + 0.5) {
          return Center(child: grid);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: grid,
        );
      },
    );
  }
}

class _StateBarRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _StateBarRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '$count thẻ (${(ratio * 100).toStringAsFixed(0)}%)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 5),
          PixelProgressBar(progress: ratio, fillColor: color),
        ],
      ),
    );
  }
}

class _ForecastChart extends StatelessWidget {
  final Map<int, int> upcoming;

  const _ForecastChart({required this.upcoming});

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final maxCount = upcoming.values.fold<int>(1, math.max);

    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(14, (day) {
          final cnt = upcoming[day] ?? 0;
          final barHeight = (cnt / maxCount) * 84.0;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (cnt > 0)
                  Text(
                    '$cnt',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  height: math.max(6, barHeight),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: cnt > 0 ? px.primary : px.surfaceAlt,
                    border: Border.all(color: px.border, width: 1.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  day == 0 ? 'Nay' : '+$day',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _WeakPhonemesSection extends StatelessWidget {
  final List<WeakPhonemeStat> weakPhonemes;

  const _WeakPhonemesSection({required this.weakPhonemes});

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    if (weakPhonemes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: px.surfaceAlt,
          border: Border.all(color: px.border, width: 2),
        ),
        child: Text(
          'Chưa có dữ liệu âm vị. Nhấn nút [LUYỆN NÓI] ngay trên Flashcard để hệ thống phân tích và tìm các âm yếu cần cải thiện!',
          style: TextStyle(
            color: px.inkMuted,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      );
    }

    return Column(
      children: weakPhonemes.map((wp) {
        final color = PronunciationColors.forScore(wp.averageScore);
        final ratio = (wp.averageScore / 100.0).clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: px.cardParchment,
            border: Border.all(color: px.border, width: 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: px.border, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: px.shadow.withValues(alpha: 0.45),
                      offset: const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  '/${wp.phoneme}/',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${wp.averageScore.round()}% chính xác',
                          style: TextStyle(
                            fontFamily: AppTheme.pixelDisplayFont,
                            fontFamilyFallback: AppTheme.fontFallback,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: color,
                          ),
                        ),
                        Text(
                          '${wp.attempts} lượt • ${wp.missCount} lỗi',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: px.inkMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    PixelProgressBar(
                      progress: ratio,
                      fillColor: color,
                      height: 14,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wp.tip,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: px.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }
}
