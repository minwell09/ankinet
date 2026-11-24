import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/injection_container.dart';
import '../../../decks/presentation/providers/deck_provider.dart';
import '../../domain/entities/study_stats.dart';
import '../../domain/usecases/get_study_stats_usecase.dart';

final studyStatsProvider = FutureProvider.autoDispose<StudyStats>((ref) async {
  ref.watch(cardsRevisionProvider);
  return sl<GetStudyStatsUseCase>()();
});
