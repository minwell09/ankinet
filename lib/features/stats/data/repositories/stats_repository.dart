import '../../../../core/database/local_database.dart';
import '../../../../core/srs/fsrs_scheduler.dart';
import '../../domain/entities/study_stats.dart';
import '../../domain/repositories/i_stats_repository.dart';

class StatsRepository implements IStatsRepository {
  final LocalDatabase localDatabase;
  final FsrsScheduler fsrsScheduler;

  const StatsRepository({
    required this.localDatabase,
    required this.fsrsScheduler,
  });

  static String formatDayKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Future<StudyStats> loadStudyStats() => getStudyStats();

  Future<StudyStats> getStudyStats() async {
    final db = await localDatabase.database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final thirtyDaysAgo =
        todayStart.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final heatmapStart =
        todayStart.subtract(const Duration(days: 140)).millisecondsSinceEpoch;

    // 1. Card counts by FSRS state
    final stateRows = await db.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN state = 0 THEN 1 ELSE 0 END) AS new_cnt,
        SUM(CASE WHEN state IN (1, 3) THEN 1 ELSE 0 END) AS learn_cnt,
        SUM(CASE WHEN state = 2 THEN 1 ELSE 0 END) AS rev_cnt,
        SUM(CASE WHEN is_leech = 1 THEN 1 ELSE 0 END) AS leech_cnt
      FROM cards
    ''');
    final sr = stateRows.first;
    final totalCards = (sr['total'] as int?) ?? 0;
    final newCnt = (sr['new_cnt'] as int?) ?? 0;
    final learnCnt = (sr['learn_cnt'] as int?) ?? 0;
    final revCnt = (sr['rev_cnt'] as int?) ?? 0;
    final leechCnt = (sr['leech_cnt'] as int?) ?? 0;

    // 2. Average FSRS Retrievability across active cards
    final activeRows = await db.query(
      'cards',
      columns: ['stability', 'last_review_at', 'state'],
      where: 'stability > 0 AND is_suspended = 0',
    );
    double sumR = 0.0;
    for (final row in activeRows) {
      final s = ((row['stability'] as num?) ?? 0.0).toDouble();
      final lastMs = row['last_review_at'] as int?;
      final elapsed = lastMs != null
          ? now
                  .difference(DateTime.fromMillisecondsSinceEpoch(lastMs))
                  .inHours /
              24.0
          : 0.0;
      sumR += fsrsScheduler.retrievability(
        elapsedDays: elapsed,
        stability: s,
      );
    }
    final avgR = activeRows.isEmpty ? 1.0 : (sumR / activeRows.length);

    // 3. 30-day True Retention (pass rate where grade >= 2 on review/learning cards)
    final retRows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS total_rev,
        SUM(CASE WHEN grade >= 2 THEN 1 ELSE 0 END) AS passed_rev
      FROM revlog
      WHERE reviewed_at >= ?
      ''',
      [thirtyDaysAgo],
    );
    final totalRev30d = (retRows.first['total_rev'] as int?) ?? 0;
    final passedRev30d = (retRows.first['passed_rev'] as int?) ?? 0;
    final retention30d =
        totalRev30d > 0 ? (passedRev30d / totalRev30d) : 1.0;

    // 4. Daily review counts for Heatmap & Streak (last 140 days)
    final logRows = await db.query(
      'revlog',
      columns: ['reviewed_at'],
      where: 'reviewed_at >= ?',
      whereArgs: [heatmapStart],
    );
    final dailyCounts = <String, int>{};
    for (final r in logRows) {
      final ms = r['reviewed_at'] as int;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final key = formatDayKey(dt);
      dailyCounts[key] = (dailyCounts[key] ?? 0) + 1;
    }

    final todayKey = formatDayKey(todayStart);
    final reviewsToday = dailyCounts[todayKey] ?? 0;

    // Calculate current daily streak
    int streak = 0;
    DateTime cursor = reviewsToday > 0
        ? todayStart
        : todayStart.subtract(const Duration(days: 1));
    while (true) {
      final k = formatDayKey(cursor);
      if ((dailyCounts[k] ?? 0) > 0) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    // 5. 14-day due forecast
    final horizonEnd =
        todayStart.add(const Duration(days: 14)).millisecondsSinceEpoch;
    final dueRows = await db.query(
      'cards',
      columns: ['next_review_at'],
      where: 'is_suspended = 0 AND state != 0 AND next_review_at < ?',
      whereArgs: [horizonEnd],
    );
    final upcoming = <int, int>{for (var i = 0; i < 14; i++) i: 0};
    for (final r in dueRows) {
      final dueMs = r['next_review_at'] as int;
      final dueDate = DateTime.fromMillisecondsSinceEpoch(dueMs);
      final diffDays = dueDate.difference(todayStart).inDays.clamp(0, 13);
      upcoming[diffDays] = (upcoming[diffDays] ?? 0) + 1;
    }

    return StudyStats(
      totalCards: totalCards,
      newCardsCount: newCnt,
      learningCardsCount: learnCnt,
      reviewCardsCount: revCnt,
      leechCardsCount: leechCnt,
      reviewsToday: reviewsToday,
      totalReviews30d: totalRev30d,
      trueRetention30d: retention30d,
      averageRetrievability: avgR,
      currentStreakDays: streak,
      dailyReviewCounts: dailyCounts,
      upcomingDueByDayOffset: upcoming,
    );
  }
}
