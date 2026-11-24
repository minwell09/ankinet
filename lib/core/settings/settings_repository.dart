import 'package:sqflite/sqflite.dart';

import '../database/local_database.dart';
import 'study_settings.dart';

class SettingsRepository {
  final LocalDatabase localDatabase;

  const SettingsRepository(this.localDatabase);

  Future<StudySettings> loadSettings() async {
    final db = await localDatabase.database;
    final rows = await db.query('app_settings');
    final map = <String, String>{};
    for (final row in rows) {
      map[row['key'] as String] = row['value'] as String;
    }
    return StudySettings.fromMap(map);
  }

  Future<void> saveSettings(StudySettings settings) async {
    final db = await localDatabase.database;
    final map = settings.toMap();
    final batch = db.batch();
    for (final entry in map.entries) {
      batch.insert(
        'app_settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
