import 'package:equatable/equatable.dart';

import '../srs/fsrs_scheduler.dart';

class StudySettings extends Equatable {
  final int newCardsPerDay;
  final int maxReviewsPerDay;
  final List<int> learningStepsMinutes;
  final List<int> relearningStepsMinutes;
  final double desiredRetention;
  final int leechThreshold;
  final bool suspendLeeches;
  final bool showClozeContext;
  final bool autoPlayTts;
  final bool enableOnlineLookup;
  final bool dailyReminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final int backupReminderDays;
  final int? lastBackupEpochMs;
  final String geminiApiKey;
  final List<double>? customFsrsWeights;

  const StudySettings({
    this.newCardsPerDay = 20,
    this.maxReviewsPerDay = 200,
    this.learningStepsMinutes = const [1, 10],
    this.relearningStepsMinutes = const [10],
    this.desiredRetention = 0.90,
    this.leechThreshold = 6,
    this.suspendLeeches = false,
    this.showClozeContext = true,
    this.autoPlayTts = true,
    this.enableOnlineLookup = true,
    this.dailyReminderEnabled = false,
    this.reminderHour = 20,
    this.reminderMinute = 0,
    this.backupReminderDays = 3,
    this.lastBackupEpochMs,
    this.geminiApiKey = '',
    this.customFsrsWeights,
  });

  /// Returns personalized 17 FSRS weights if configured, otherwise [FsrsScheduler.defaultWeights].
  List<double> get effectiveFsrsWeights {
    if (customFsrsWeights != null && customFsrsWeights!.length == 17) {
      return customFsrsWeights!;
    }
    return FsrsScheduler.defaultWeights;
  }

  bool get hasCustomFsrsWeights =>
      customFsrsWeights != null && customFsrsWeights!.length == 17;

  /// Returns true when the user should be reminded to export a JSON backup
  /// (especially critical on Web where IndexedDB can be cleared by the browser).
  bool shouldRemindBackup({required bool isWeb, int? nowEpochMs}) {
    if (lastBackupEpochMs == null || lastBackupEpochMs! <= 0) {
      return isWeb;
    }
    final now = nowEpochMs != null
        ? DateTime.fromMillisecondsSinceEpoch(nowEpochMs)
        : DateTime.now();
    final last = DateTime.fromMillisecondsSinceEpoch(lastBackupEpochMs!);
    return now.difference(last).inDays >= backupReminderDays;
  }

  StudySettings copyWith({
    int? newCardsPerDay,
    int? maxReviewsPerDay,
    List<int>? learningStepsMinutes,
    List<int>? relearningStepsMinutes,
    double? desiredRetention,
    int? leechThreshold,
    bool? suspendLeeches,
    bool? showClozeContext,
    bool? autoPlayTts,
    bool? enableOnlineLookup,
    bool? dailyReminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    int? backupReminderDays,
    int? lastBackupEpochMs,
    String? geminiApiKey,
    List<double>? customFsrsWeights,
    bool clearCustomFsrsWeights = false,
  }) {
    return StudySettings(
      newCardsPerDay: newCardsPerDay ?? this.newCardsPerDay,
      maxReviewsPerDay: maxReviewsPerDay ?? this.maxReviewsPerDay,
      learningStepsMinutes: learningStepsMinutes ?? this.learningStepsMinutes,
      relearningStepsMinutes:
          relearningStepsMinutes ?? this.relearningStepsMinutes,
      desiredRetention: desiredRetention ?? this.desiredRetention,
      leechThreshold: leechThreshold ?? this.leechThreshold,
      suspendLeeches: suspendLeeches ?? this.suspendLeeches,
      showClozeContext: showClozeContext ?? this.showClozeContext,
      autoPlayTts: autoPlayTts ?? this.autoPlayTts,
      enableOnlineLookup: enableOnlineLookup ?? this.enableOnlineLookup,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      backupReminderDays: backupReminderDays ?? this.backupReminderDays,
      lastBackupEpochMs: lastBackupEpochMs ?? this.lastBackupEpochMs,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      customFsrsWeights: clearCustomFsrsWeights
          ? null
          : (customFsrsWeights ?? this.customFsrsWeights),
    );
  }

  Map<String, String> toMap() {
    return {
      'new_cards_per_day': newCardsPerDay.toString(),
      'max_reviews_per_day': maxReviewsPerDay.toString(),
      'learning_steps': learningStepsMinutes.join(','),
      'relearning_steps': relearningStepsMinutes.join(','),
      'desired_retention': desiredRetention.toStringAsFixed(2),
      'leech_threshold': leechThreshold.toString(),
      'suspend_leeches': suspendLeeches ? '1' : '0',
      'show_cloze_context': showClozeContext ? '1' : '0',
      'auto_play_tts': autoPlayTts ? '1' : '0',
      'enable_online_lookup': enableOnlineLookup ? '1' : '0',
      'daily_reminder_enabled': dailyReminderEnabled ? '1' : '0',
      'reminder_hour': reminderHour.toString(),
      'reminder_minute': reminderMinute.toString(),
      'backup_reminder_days': backupReminderDays.toString(),
      if (lastBackupEpochMs != null)
        'last_backup_epoch_ms': lastBackupEpochMs.toString(),
      'gemini_api_key': geminiApiKey,
      'custom_fsrs_weights': hasCustomFsrsWeights
          ? customFsrsWeights!.map((w) => w.toStringAsFixed(4)).join(',')
          : '',
    };
  }

  factory StudySettings.fromMap(Map<String, String> map) {
    List<int> parseSteps(String? raw, List<int> fallback) {
      if (raw == null || raw.trim().isEmpty) return fallback;
      final parsed = raw
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .where((v) => v > 0)
          .toList();
      return parsed.isEmpty ? fallback : parsed;
    }

    List<double>? parseWeights(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      final parts = raw
          .split(',')
          .map((s) => double.tryParse(s.trim()))
          .whereType<double>()
          .toList();
      return parts.length == 17 ? parts : null;
    }

    return StudySettings(
      newCardsPerDay: int.tryParse(map['new_cards_per_day'] ?? '') ?? 20,
      maxReviewsPerDay: int.tryParse(map['max_reviews_per_day'] ?? '') ?? 200,
      learningStepsMinutes: parseSteps(map['learning_steps'], const [1, 10]),
      relearningStepsMinutes: parseSteps(map['relearning_steps'], const [10]),
      desiredRetention:
          (double.tryParse(map['desired_retention'] ?? '') ?? 0.90)
              .clamp(0.75, 0.97),
      leechThreshold: int.tryParse(map['leech_threshold'] ?? '') ?? 6,
      suspendLeeches: map['suspend_leeches'] == '1',
      showClozeContext: (map['show_cloze_context'] ?? '1') == '1',
      autoPlayTts: (map['auto_play_tts'] ?? '1') == '1',
      enableOnlineLookup: (map['enable_online_lookup'] ?? '1') == '1',
      dailyReminderEnabled: map['daily_reminder_enabled'] == '1',
      reminderHour: int.tryParse(map['reminder_hour'] ?? '') ?? 20,
      reminderMinute: int.tryParse(map['reminder_minute'] ?? '') ?? 0,
      backupReminderDays:
          (int.tryParse(map['backup_reminder_days'] ?? '') ?? 3).clamp(1, 30),
      lastBackupEpochMs: int.tryParse(map['last_backup_epoch_ms'] ?? ''),
      geminiApiKey: (map['gemini_api_key'] ?? '').trim(),
      customFsrsWeights: parseWeights(map['custom_fsrs_weights']),
    );
  }

  @override
  List<Object?> get props => [
        newCardsPerDay,
        maxReviewsPerDay,
        learningStepsMinutes,
        relearningStepsMinutes,
        desiredRetention,
        leechThreshold,
        suspendLeeches,
        showClozeContext,
        autoPlayTts,
        enableOnlineLookup,
        dailyReminderEnabled,
        reminderHour,
        reminderMinute,
        backupReminderDays,
        lastBackupEpochMs,
        geminiApiKey,
        customFsrsWeights,
      ];
}
