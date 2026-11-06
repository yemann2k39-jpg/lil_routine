import 'package:sqflite/sqflite.dart';

import 'entry_repository.dart';
import 'food_repository.dart';
import 'habit_repository.dart';
import 'models.dart';
import 'settings_repository.dart';

/// Debug-only helpers: seed sample data / wipe everything.
/// Wired into a screen that exists only in debug builds (kDebugMode).
class DebugDataService {
  DebugDataService(this.db);

  final Database db;

  Future<void> seedSampleData() async {
    final entries = EntryRepository(db);
    final foods = FoodRepository(db);
    final habits = HabitRepository(db);
    final settings = SettingsRepository(db);

    final now = DateTime.now();

    // Water: today 5 glasses, yesterday 7 glasses.
    for (var i = 0; i < 5; i++) {
      await entries.addWater(
        amountMl: 250,
        at: now.subtract(Duration(hours: 6 - i)),
      );
    }
    for (var i = 0; i < 7; i++) {
      await entries.addWater(
        amountMl: 250,
        at: now.subtract(Duration(hours: 24 + 6 - i)),
      );
    }

    // Personal foods (some favorited).
    await foods.upsertFromLog(name: 'Nasi goreng ayam', kcal: 743, protein: 24, carbs: 96, fat: 25);
    await foods.upsertFromLog(name: 'Telur dadar', kcal: 220, protein: 14, carbs: 2, fat: 17);
    await foods.upsertFromLog(name: 'Coca-Cola (can)', kcal: 139, carbs: 35);
    await foods.upsertFromLog(name: 'Pisang', kcal: 105, carbs: 27);
    final nasi = await foods.byName('Nasi goreng ayam');
    if (nasi != null) await foods.setFavorite(nasi.id!, true);
    final telur = await foods.byName('Telur dadar');
    if (telur != null) await foods.setFavorite(telur.id!, true);

    // Food entries today: breakfast + lunch + snack.
    await entries.addFood(
      name: 'Telur dadar',
      mealType: MealType.breakfast,
      kcal: 220,
      protein: 14,
      carbs: 2,
      fat: 17,
      at: now.subtract(const Duration(hours: 6)),
    );
    await entries.addFood(
      name: 'Nasi goreng ayam',
      mealType: MealType.lunch,
      kcal: 743,
      protein: 24,
      carbs: 96,
      fat: 25,
      at: now.subtract(const Duration(hours: 3)),
    );
    await entries.addFood(
      name: 'Pisang',
      mealType: MealType.snack,
      kcal: 105,
      carbs: 27,
      at: now.subtract(const Duration(hours: 1)),
    );

    // Starter habits (derived kinds computed in LIL-7).
    if (await habits.count() == 0) {
      await habits.addHabit(name: 'Hit water goal', kind: HabitKind.waterGoal);
      await habits.addHabit(name: 'Under calorie goal', kind: HabitKind.underKcalGoal);
      await habits.addHabit(name: 'No late-night eating', kind: HabitKind.noLateEating);
    }

    // Sensible default settings.
    if (await settings.waterGoalMl() == SettingsRepository.defaultWaterGoalMl) {
      await settings.setWaterGoalMl(SettingsRepository.defaultWaterGoalMl);
    }
    await settings.setKcalGoal(2000);
    await settings.setGlassSizeMl(250);
  }

  /// Wipes all user data but keeps the schema.
  Future<void> clearAllData() async {
    await db.delete('entries');
    await db.delete('foods');
    await db.delete('habit_logs');
    await db.delete('habits');
    await db.delete('settings');
  }

  Future<Map<String, int>> tableCounts() async {
    final tables = ['entries', 'foods', 'habits', 'habit_logs', 'settings'];
    final result = <String, int>{};
    for (final t in tables) {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
      result[t] = (rows.first['c'] as num).toInt();
    }
    return result;
  }
}
