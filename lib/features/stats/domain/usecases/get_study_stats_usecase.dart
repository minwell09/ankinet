import '../entities/study_stats.dart';
import '../repositories/i_stats_repository.dart';

class GetStudyStatsUseCase {
  final IStatsRepository repository;

  const GetStudyStatsUseCase(this.repository);

  Future<StudyStats> call() => repository.loadStudyStats();
}
