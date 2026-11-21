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

  // --- AI coach recap (LIL-22) -----------------------------------------

  /// Saves one week's recap: json under its week key (history), plus a
  /// "last" pointer and timestamp used for the 7-day auto cadence.
  Future<void> saveCoachRecap({
    required String weekKey,
    required String json,
    required DateTime at,
  }) async {
    await set('coach_recap_week_$weekKey', json);
    await set('coach_recap_last', json);
    await set('coach_recap_at', at.toIso8601String());
  }

  /// ISO8601 time of the last recap, or null when none ran yet.
  Future<String?> coachRecapAt() => _get('coach_recap_at');

  /// Latest recap JSON (tips list), or null.
  Future<String?> lastCoachRecap() => _get('coach_recap_last');

  /// All stored recaps, newest week first: (weekKey, json).
  Future<List<(String, String)>> coachRecapHistory() async {
    final rows = await db.query('settings',
        where: "key LIKE 'coach_recap_week_%'",
        orderBy: 'key DESC');
    return [
      for (final r in rows)
        (
          (r['key'] as String).substring('coach_recap_week_'.length),
          r['value'] as String,
        ),
    ];
  }
}
