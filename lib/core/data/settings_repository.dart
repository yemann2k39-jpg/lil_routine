import 'package:sqflite/sqflite.dart';

/// Key-value settings, stored in SQLite so they persist like everything else.
class SettingsRepository {
  SettingsRepository(this.db);

  final Database db;

  // Defaults (cozy starter values; user changes them in Settings, LIL-11).
  static const int defaultWaterGoalMl = 3000;
  static const int defaultKcalGoal = 2000;
  static const int defaultGlassSizeMl = 250;
  static const bool defaultReminderEnabled = false;
  static const int defaultReminderMinutes = 60;

  Future<String?> _get(String key) async {
    final rows = await db.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> set(String key, Object value) async {
    await db.rawInsert(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value.toString()],
    );
  }

  Future<int> waterGoalMl() async =>
      int.tryParse(await _get('water_goal_ml') ?? '') ??
      defaultWaterGoalMl;

  Future<void> setWaterGoalMl(int value) =>
      set('water_goal_ml', value);

  Future<int> kcalGoal() async =>
      int.tryParse(await _get('kcal_goal') ?? '') ?? defaultKcalGoal;

  Future<void> setKcalGoal(int value) => set('kcal_goal', value);

  Future<int> glassSizeMl() async =>
      int.tryParse(await _get('glass_size_ml') ?? '') ??
      defaultGlassSizeMl;

  Future<void> setGlassSizeMl(int value) => set('glass_size_ml', value);

  /// Water reminder on/off. Stored as '1'/'0'.
  Future<bool> reminderEnabled() async =>
      (await _get('reminder_enabled')) == '1';

  Future<void> setReminderEnabled(bool value) =>
      set('reminder_enabled', value ? 1 : 0);

  /// Reminder interval in minutes (user's free choice, >= 1).
  Future<int> reminderMinutes() async =>
      int.tryParse(await _get('reminder_minutes') ?? '') ??
      defaultReminderMinutes;

  Future<void> setReminderMinutes(int value) =>
      set('reminder_minutes', value);
}
