import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Create/read/update/delete for the unified daily log (water + food).
class EntryRepository {
  EntryRepository(this.db);

  final Database db;

  Future<int> addWater({required int amountMl, DateTime? at}) async {
    final now = at ?? DateTime.now();
    final entry = Entry(
      type: EntryType.water,
      amountMl: amountMl,
      createdAt: now,
      date: dateKey(now),
    );
    return db.insert('entries', entry.toMap());
  }

  Future<int> addFood({
    required String name,
    required MealType mealType,
    required double kcal,
    double protein = 0,
    double carbs = 0,
    double fat = 0,
    double fiber = 0,
    double sugar = 0,
    double sodium = 0,
    double portion = 1,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final entry = Entry(
      type: EntryType.food,
      name: name,
      mealType: mealType,
      kcal: kcal,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fiber,
      sugar: sugar,
      sodium: sodium,
      portion: portion,
      createdAt: now,
      date: dateKey(now),
    );
    return db.insert('entries', entry.toMap());
  }

  /// Updates an existing food entry in place (edit-after-log). Water
  /// entries are not editable.
  Future<void> updateFood(Entry entry) async {
    if (entry.id == null || entry.isWater) {
      throw ArgumentError('updateFood needs a persisted food entry');
    }
    await db.update(
      'entries',
      {
        'name': entry.name,
        'meal_type': entry.mealType?.name,
        'kcal': entry.kcal,
        'protein': entry.protein,
        'carbs': entry.carbs,
        'fat': entry.fat,
        'fiber': entry.fiber,
        'sugar': entry.sugar,
        'sodium': entry.sodium,
        'portion': entry.portion,
      },
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<int> delete(int id) =>
      db.delete('entries', where: 'id = ?', whereArgs: [id]);

  Future<List<Entry>> entriesForDate(String date) async {
    final rows = await db.query(
      'entries',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'created_at ASC',
    );
    return rows.map(Entry.fromMap).toList();
  }

  Future<Entry?> byId(int id) async {
    final rows = await db.query('entries',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Entry.fromMap(rows.first);
  }

  /// Sum of water amount_ml for [date]; null-safe: returns 0 when empty.
  Future<int> waterTotalForDate(String date) async {
    final rows = await db.rawQuery(
      "SELECT SUM(amount_ml) AS s FROM entries WHERE type = 'water' AND date = ?",
      [date],
    );
    return (rows.first['s'] as num?)?.toInt() ?? 0;
  }

  /// Sum of kcal * portion for [date].
  Future<double> kcalTotalForDate(String date) async {
    final rows = await db.rawQuery(
      'SELECT SUM(kcal * portion) AS s FROM entries WHERE type = ? AND date = ?',
      [EntryType.food.name, date],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
  }

  /// Water totals per date in [startDate, endDate] inclusive.
  Future<Map<String, int>> waterTotalsForRange(
      String startDate, String endDate) async {
    final rows = await db.rawQuery(
      "SELECT date, SUM(amount_ml) AS s FROM entries "
      "WHERE type = 'water' AND date BETWEEN ? AND ? GROUP BY date",
      [startDate, endDate],
    );
    return {
      for (final r in rows) r['date'] as String: (r['s'] as num).toInt(),
    };
  }

  /// Water entries (with timestamps) whose date is in
  /// [startDate, endDate] inclusive — used for hourly pattern charts.
  Future<List<Entry>> waterEntriesBetween(
      String startDate, String endDate) async {
    final rows = await db.query(
      'entries',
      where: "type = 'water' AND date BETWEEN ? AND ?",
      whereArgs: [startDate, endDate],
      orderBy: 'created_at ASC',
    );
    return rows.map(Entry.fromMap).toList();
  }

  /// Earliest date (yyyy-MM-dd) with a water entry, or null when the
  /// water log is empty. Used by the streak engine.
  Future<String?> firstWaterDate() async {
    final rows = await db
        .rawQuery("SELECT MIN(date) AS d FROM entries WHERE type = 'water'");
    return rows.first['d'] as String?;
  }

  /// kcal totals per date in [startDate, endDate] inclusive.
  Future<Map<String, double>> kcalTotalsForRange(
      String startDate, String endDate) async {
    final rows = await db.rawQuery(
      'SELECT date, SUM(kcal * portion) AS s FROM entries '
      'WHERE type = ? AND date BETWEEN ? AND ? GROUP BY date',
      [EntryType.food.name, startDate, endDate],
    );
    return {
      for (final r in rows)
        r['date'] as String: (r['s'] as num?)?.toDouble() ?? 0,
    };
  }

  /// Food entries whose date is in [startDate, endDate] inclusive —
  /// used by the meals history dashboard (top meal, day sheets).
  Future<List<Entry>> foodEntriesBetween(
      String startDate, String endDate) async {
    final rows = await db.query(
      'entries',
      where: "type = 'food' AND date BETWEEN ? AND ?",
      whereArgs: [startDate, endDate],
      orderBy: 'created_at ASC',
    );
    return rows.map(Entry.fromMap).toList();
  }

  /// Per-day macro totals (grams, portion-scaled) in
  /// [startDate, endDate] inclusive — meals history stat boxes.
  Future<Map<String, MacroTotals>> macroTotalsForRange(
      String startDate, String endDate) async {
    final rows = await db.rawQuery(
      'SELECT date, '
      'SUM(protein * portion) AS protein, '
      'SUM(carbs * portion) AS carbs, '
      'SUM(fat * portion) AS fat '
      'FROM entries '
      'WHERE type = ? AND date BETWEEN ? AND ? GROUP BY date',
      [EntryType.food.name, startDate, endDate],
    );
    return {
      for (final r in rows)
        r['date'] as String: MacroTotals(
          protein: (r['protein'] as num?)?.toDouble() ?? 0,
          carbs: (r['carbs'] as num?)?.toDouble() ?? 0,
          fat: (r['fat'] as num?)?.toDouble() ?? 0,
        ),
    };
  }

  /// Most recent entries of any type (used by the debug screen and recents).
  Future<List<Entry>> latest({int limit = 50}) async {
    final rows = await db.query('entries',
        orderBy: 'created_at DESC', limit: limit);
    return rows.map(Entry.fromMap).toList();
  }

  /// The most recent water entry (for undo).
  Future<Entry?> latestWater() async {
    final rows = await db.query(
      'entries',
      where: 'type = ?',
      whereArgs: [EntryType.water.name],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Entry.fromMap(rows.first);
  }
}
