import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/injection_container.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/settings/settings_repository.dart';
import '../../../../core/settings/study_settings.dart';
import '../../../decks/domain/repositories/deck_repository.dart';

class StudySettingsNotifier extends AsyncNotifier<StudySettings> {
  @override
  Future<StudySettings> build() async {
    return sl<SettingsRepository>().loadSettings();
  }

  Future<void> updateSettings(StudySettings updated) async {
    state = AsyncData(updated);
    await sl<SettingsRepository>().saveSettings(updated);

    if (updated.dailyReminderEnabled) {
      final decksRes = await sl<DeckRepository>().getDecks();
      final totalDue = decksRes.fold(
        (_) => 0,
        (decks) => decks.fold<int>(0, (sum, d) => sum + d.dueCards),
      );
      await sl<NotificationService>().scheduleDailyReviewReminder(
        hour: updated.reminderHour,
        minute: updated.reminderMinute,
        dueCount: totalDue,
      );
    } else {
      await sl<NotificationService>().cancelDailyReminder();
    }
  }
}

final studySettingsProvider =
    AsyncNotifierProvider<StudySettingsNotifier, StudySettings>(
  StudySettingsNotifier.new,
);
