import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Habits + their per-day done state. Derived habits (water goal, calorie
/// goal, no late eating) are computed from entries by the habit engine in
/// LIL-7; this repository stores definitions and manual/override logs.
class HabitRepository {
  HabitRepository(this.db);

  final Database db;

  Future<int> addHabit({
    required String name,
    required HabitKind kind,
  }) {
    final habit = Habit(name: name, kind: kind, createdAt: DateTime.now());
    return db.insert('habits', habit.toMap());
  }

  Future<List<Habit>> listHabits({bool enabledOnly = false}) async {
    final rows = await db.query('habits',
        where: enabledOnly ? 'enabled = 1' : null,
        orderBy: 'created_at ASC');
    return rows.map(Habit.fromMap).toList();
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await db.update('habits', {'enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes the habit; its logs disappear via ON DELETE CASCADE.
  Future<void> deleteHabit(int id) =>
      db.delete('habits', where: 'id = ?', whereArgs: [id]);

  /// Sets (upserts) the done state for one habit on one day.
  Future<void> setLog({
    required int habitId,
    required String date,
    required bool done,
  }) async {
    await db.rawInsert(
      'INSERT INTO habit_logs (habit_id, date, done) VALUES (?, ?, ?) '
      'ON CONFLICT(habit_id, date) DO UPDATE SET done = excluded.done',
      [habitId, date, done ? 1 : 0],
    );
  }

  Future<List<HabitLog>> logsForDate(String date) async {
    final rows = await db.query('habit_logs',
        where: 'date = ?', whereArgs: [date]);
    return rows.map(HabitLog.fromMap).toList();
  }

  Future<List<HabitLog>> logsForHabit(int habitId,
      {String? startDate, String? endDate}) async {
    final rows = await db.query(
      'habit_logs',
      where: startDate != null && endDate != null
          ? 'habit_id = ? AND date BETWEEN ? AND ?'
          : 'habit_id = ?',
      whereArgs: startDate != null && endDate != null
          ? [habitId, startDate, endDate]
          : [habitId],
      orderBy: 'date ASC',
    );
    return rows.map(HabitLog.fromMap).toList();
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM habits')) ??
      0;
}
