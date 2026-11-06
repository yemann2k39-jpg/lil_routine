import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Drink quick-slots shown as cups on the water page.
class DrinkSlotRepository {
  DrinkSlotRepository(this.db);

  final Database db;

  static const int maxSlots = 4;

  Future<List<DrinkSlot>> list() async {
    final rows =
        await db.query('drink_slots', orderBy: 'position ASC, id ASC');
    return rows.map(DrinkSlot.fromMap).toList();
  }

  Future<int> add({required String name, required int ml}) async {
    final count =
        Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) AS c FROM drink_slots')) ??
            0;
    return db.insert('drink_slots', {
      'name': name,
      'ml': ml,
      'position': count,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> remove(int id) =>
      db.delete('drink_slots', where: 'id = ?', whereArgs: [id]);

  Future<int> count() async =>
      Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM drink_slots')) ??
      0;

  /// Seeds the default glass slot on first run only.
  ///
  /// A `slots_seeded` marker in the settings table records that first-run
  /// seeding happened, so a user who removed every cup stays empty — the
  /// glass must not come back on the next reload or app start.
  Future<void> ensureDefault() async {
    final seeded = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) AS c FROM settings WHERE key = 'slots_seeded'")) ??
        0;
    if (seeded == 1) return;
    if (await count() == 0) {
      await add(name: 'glass', ml: 250);
    }
    await db.insert(
      'settings',
      {'key': 'slots_seeded', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
