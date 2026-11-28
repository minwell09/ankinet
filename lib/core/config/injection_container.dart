import 'package:get_it/get_it.dart';

import '../../features/decks/data/repositories/deck_repository_impl.dart';
import '../../features/decks/domain/repositories/deck_repository.dart';
import '../../features/decks/domain/usecases/get_decks_usecase.dart';
import '../../features/decks/domain/usecases/lookup_pronunciation_usecase.dart';
import '../../features/decks/domain/usecases/manage_cards_and_decks_usecase.dart';
import '../../features/decks/domain/usecases/manage_leech_cards_usecase.dart';
import '../../features/nlp_extractor/data/datasources/nlp_analyzer_datasource.dart';
import '../../features/nlp_extractor/data/repositories/nlp_extractor_repository_impl.dart';
import '../../features/nlp_extractor/domain/repositories/nlp_extractor_repository.dart';
import '../../features/nlp_extractor/domain/usecases/analyze_text_usecase.dart';
import '../../features/nlp_extractor/domain/usecases/create_cards_from_tokens_usecase.dart';
import '../../features/pronunciation/data/services/pronunciation_assessment_service.dart';
import '../../features/settings/data/services/backup_service.dart';
import '../../features/stats/data/repositories/stats_repository.dart';
import '../../features/stats/domain/repositories/i_stats_repository.dart';
import '../../features/stats/domain/usecases/get_study_stats_usecase.dart';
import '../../features/study_session/domain/usecases/study_session_usecases.dart';
import '../database/local_database.dart';
import '../database/offline_dictionary_database.dart';
import '../services/notification_service.dart';
import '../services/tts_cache_service.dart';
import '../settings/settings_repository.dart';
import '../srs/fsrs_scheduler.dart';
import '../srs/fsrs_weight_optimizer.dart';
import '../srs/sm2_scheduler.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Core Databases & Schedulers
  sl.registerLazySingleton<LocalDatabase>(() => LocalDatabase());
  sl.registerLazySingleton<OfflineDictionaryDatabase>(
    () => OfflineDictionaryDatabase(),
  );
  sl.registerLazySingleton<Sm2Scheduler>(() => Sm2Scheduler());
  sl.registerLazySingleton<FsrsScheduler>(() => const FsrsScheduler());
  sl.registerLazySingleton<FsrsWeightOptimizer>(() => FsrsWeightOptimizer());
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepository(sl()),
  );

  // Audio TTS Cache, Pronunciation Assessment & Notifications
  sl.registerLazySingleton<TtsCacheService>(() => TtsCacheService());
  sl.registerLazySingleton<PronunciationAssessmentService>(
    () => PronunciationAssessmentService(
      localDatabase: sl(),
      ttsCacheService: sl(),
    ),
  );
  sl.registerLazySingleton<NotificationService>(() => NotificationService());

  // Feature: NLP Text Extractor
  sl.registerLazySingleton<NlpAnalyzerDataSource>(
    () => HybridNlpAnalyzerDataSourceImpl(
      localDatabase: sl(),
      offlineDictionaryDatabase: sl(),
    ),
  );
  sl.registerLazySingleton<NlpExtractorRepository>(
    () => NlpExtractorRepositoryImpl(
      analyzerDataSource: sl(),
      localDatabase: sl(),
    ),
  );
  sl.registerLazySingleton(() => AnalyzeTextUseCase(sl()));
  sl.registerLazySingleton(() => CreateCardsFromTokensUseCase(sl()));

  // Feature: Decks & Study Session (Clean Architecture UseCases)
  sl.registerLazySingleton<DeckRepository>(
    () => DeckRepositoryImpl(
      localDatabase: sl(),
      fsrsScheduler: sl(),
      settingsRepository: sl(),
    ),
  );
  sl.registerLazySingleton(() => GetDecksUseCase(sl()));
  sl.registerLazySingleton(() => GetLeechCardsUseCase(sl()));
  sl.registerLazySingleton(() => ToggleSuspendCardUseCase(sl()));
  sl.registerLazySingleton(() => ResetLeechCardUseCase(sl()));
  sl.registerLazySingleton(() => LookupPronunciationUseCase(sl()));
  sl.registerLazySingleton(() => GetCardsByDeckUseCase(sl()));
  sl.registerLazySingleton(() => UpdateCardUseCase(sl()));
  sl.registerLazySingleton(() => DeleteCardUseCase(sl()));
  sl.registerLazySingleton(() => CreateDeckUseCase(sl()));
  sl.registerLazySingleton(() => UpdateDeckUseCase(sl()));
  sl.registerLazySingleton(() => DeleteDeckUseCase(sl()));
  sl.registerLazySingleton(() => GetDueCardsUseCase(sl()));
  sl.registerLazySingleton(() => SubmitReviewUseCase(sl()));
  sl.registerLazySingleton(() => GetRelatedWordsUseCase(sl()));

  // Feature: Statistics & Backup
  sl.registerLazySingleton<StatsRepository>(
    () => StatsRepository(
      localDatabase: sl(),
      fsrsScheduler: sl(),
    ),
  );
  sl.registerLazySingleton<IStatsRepository>(() => sl<StatsRepository>());
  sl.registerLazySingleton(() => GetStudyStatsUseCase(sl()));
  sl.registerLazySingleton<BackupService>(() => BackupService(sl()));
}
