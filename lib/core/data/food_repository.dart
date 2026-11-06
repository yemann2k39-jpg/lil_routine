import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// The user's personal food database: powers recents and favorites.
/// Every logged food is upserted here automatically.
class FoodRepository {
  FoodRepository(this.db);

  final Database db;

  /// Called whenever a food is logged. Inserts the food if new, otherwise
  /// refreshes its nutrition data and bumps times_logged / last_used_at.
  Future<int> upsertFromLog({
    required String name,
    required double kcal,
    double protein = 0,
    double carbs = 0,
    double fat = 0,
    double fiber = 0,
    double sugar = 0,
    double sodium = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.rawInsert(
      'INSERT INTO foods (name, kcal, protein, carbs, fat, fiber, sugar, sodium, is_favorite, times_logged, last_used_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 1, ?) '
      'ON CONFLICT(name) DO UPDATE SET '
      '  kcal = excluded.kcal, '
      '  protein = excluded.protein, '
      '  carbs = excluded.carbs, '
      '  fat = excluded.fat, '
      '  fiber = excluded.fiber, '
      '  sugar = excluded.sugar, '
      '  sodium = excluded.sodium, '
      '  times_logged = times_logged + 1, '
      '  last_used_at = excluded.last_used_at',
      [name, kcal, protein, carbs, fat, fiber, sugar, sodium, now],
    );
  }

  Future<List<FoodItem>> recents({int limit = 20}) async {
    final rows = await db.query('foods',
        orderBy: 'last_used_at DESC', limit: limit);
    return rows.map(FoodItem.fromMap).toList();
  }

  Future<List<FoodItem>> favorites() async {
    final rows = await db.query('foods',
        where: 'is_favorite = 1', orderBy: 'name ASC');
    return rows.map(FoodItem.fromMap).toList();
  }

  Future<FoodItem?> byName(String name) async {
    final rows = await db.query('foods',
        where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
    return rows.isEmpty ? null : FoodItem.fromMap(rows.first);
  }

  Future<void> setFavorite(int id, bool favorite) async {
    await db.update(
      'foods',
      {'is_favorite': favorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleFavorite(int id) async {
    await db.rawUpdate(
      'UPDATE foods SET is_favorite = CASE is_favorite WHEN 1 THEN 0 ELSE 1 END '
      'WHERE id = ?',
      [id],
    );
  }

  Future<void> delete(int id) =>
      db.delete('foods', where: 'id = ?', whereArgs: [id]);

  Future<int> count() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM foods')) ??
      0;
}
