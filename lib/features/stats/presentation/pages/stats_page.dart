import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/ui/pixel_widgets.dart';
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
        title: const Text('THỐNG KÊ FSRS • HUD'),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              title: 'TỈ LỆ NHỚ (30D)',
              value: '$retentionPct%',
              subtitle: '${stats.totalReviews30d} lượt ôn tập',
              icon: Icons.psychology_alt_rounded,
              color: colorScheme.primaryContainer,
              accent: px.primary,
            ),
            _MetricCard(
              title: 'STREAK',
              value: '${stats.currentStreakDays} NGÀY',
              subtitle: 'Hôm nay: ${stats.reviewsToday} lượt ôn',
              icon: Icons.local_fire_department_rounded,
              color: colorScheme.tertiaryContainer,
              accent: px.gold,
            ),
            _MetricCard(
              title: 'RETRIEVABILITY',
              value: '$retrievabilityPct%',
              subtitle: 'Xác suất nhớ trung bình',
              icon: Icons.insights_rounded,
              color: colorScheme.secondaryContainer,
              accent: px.cyan,
            ),
          ],
        ),
        const SizedBox(height: 16),
        PixelCard(
          woodFrame: true,
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelSectionHeader(
                title: 'HEATMAP ÔN TẬP (20 TUẦN • CROP TILES)',
                icon: Icons.grid_on_rounded,
                accentColor: px.cropLush,
              ),
              const SizedBox(height: 6),
              Text(
                'Mỗi ô pixel = 1 mảnh đất • Càng ôn đều cây càng xanh tốt',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: px.inkMuted),
              ),
              const SizedBox(height: 12),
              _ReviewHeatmapGrid(dailyCounts: stats.dailyReviewCounts),
            ],
          ),
        ),
        PixelCard(
          woodFrame: true,
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelSectionHeader(
                title: 'PHÂN BỐ TRẠNG THÁI THẺ (TỔNG ${stats.totalCards})',
                icon: Icons.bar_chart_rounded,
                accentColor: px.primary,
              ),
              const SizedBox(height: 14),
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
        PixelCard(
          woodFrame: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelSectionHeader(
                title: 'DỰ BÁO THẺ ĐẾN HẠN (14 NGÀY)',
                icon: Icons.calendar_today_rounded,
                accentColor: px.cyan,
              ),
              const SizedBox(height: 14),
              _ForecastChart(upcoming: stats.upcomingDueByDayOffset),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color accent;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    return SizedBox(
      width: 220,
      child: PixelCard(
        woodFrame: true,
        showRivets: true,
        backgroundColor: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent,
                    border: Border.all(color: px.border, width: 2),
                  ),
                  child: Icon(icon, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: px.inkMuted, fontSize: 11.5),
            ),
          ],
        ),
      ),
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(weeks, (wIdx) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              children: List.generate(7, (dIdx) {
                final dayOffset = wIdx * 7 + dIdx;
                final dt = startDay.add(Duration(days: dayOffset));
                final key = StatsRepository.formatDayKey(dt);
                final cnt = dailyCounts[key] ?? 0;
                return Tooltip(
                  message: '$key: $cnt lượt ôn',
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: cellColor(cnt),
                      border: Border.all(
                        color: px.border.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
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
