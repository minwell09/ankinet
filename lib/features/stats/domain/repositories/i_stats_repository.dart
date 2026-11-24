import '../entities/study_stats.dart';

abstract class IStatsRepository {
  Future<StudyStats> loadStudyStats();
}
