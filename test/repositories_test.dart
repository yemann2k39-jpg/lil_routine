import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lil_routine/core/data/debug_data_service.dart';
import 'package:lil_routine/core/data/drink_slot_repository.dart';
import 'package:lil_routine/core/data/entry_repository.dart';
import 'package:lil_routine/core/data/food_repository.dart';
import 'package:lil_routine/core/data/habit_repository.dart';
import 'package:lil_routine/core/data/models.dart';
import 'package:lil_routine/core/data/settings_repository.dart';
import 'package:lil_routine/core/db/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, version) => AppDatabase.createSchema(d),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('EntryRepository', () {
    test('water add + daily total', () async {
      final repo = EntryRepository(db);
      await repo.addWater(amountMl: 250);
      await repo.addWater(amountMl: 300);
      final today = dateKey(DateTime.now());
      expect(await repo.waterTotalForDate(today), 550);
    });

    test('kcal total respects portion multiplier', () async {
      final repo = EntryRepository(db);
      await repo.addFood(
          name: 'Nasi goreng', mealType: MealType.lunch, kcal: 700, portion: 1.5);
      await repo.addFood(
          name: 'Pisang', mealType: MealType.snack, kcal: 100, portion: 0.5);
      final today = dateKey(DateTime.now());
      final total = await repo.kcalTotalForDate(today);
      expect(total, closeTo(1100, 0.01));
    });

    test('entriesForDate returns only that day, ordered', () async {
      final repo = EntryRepository(db);
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      await repo.addWater(amountMl: 200, at: now);
      await repo.addWater(amountMl: 100, at: yesterday);
      final today = dateKey(now);
      final list = await repo.entriesForDate(today);
      expect(list.length, 1);
      expect(list.first.amountMl, 200);
    });

    test('waterEntriesBetween returns water in range, ordered', () async {
      final repo = EntryRepository(db);
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      await repo.addWater(amountMl: 100, at: yesterday);
      await repo.addFood(
          name: 'x', mealType: MealType.snack, kcal: 50, at: yesterday);
      await repo.addWater(amountMl: 250, at: now);
      final list =
          await repo.waterEntriesBetween(dateKey(yesterday), dateKey(now));
      expect(list.length, 2);
      expect(list.every((e) => e.isWater), isTrue);
      expect(list.first.amountMl, 100);
      expect(list.last.amountMl, 250);
    });

    test('foodEntriesBetween returns food in range, ordered', () async {
      final repo = EntryRepository(db);
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      await repo.addFood(
          name: 'older',
          mealType: MealType.breakfast,
          kcal: 300,
          at: yesterday);
      await repo.addWater(amountMl: 250, at: yesterday);
      await repo.addFood(
          name: 'newer', mealType: MealType.dinner, kcal: 700, at: now);
      final list =
          await repo.foodEntriesBetween(dateKey(yesterday), dateKey(now));
      expect(list.length, 2);
      expect(list.every((e) => e.isWater), isFalse);
      expect(list.first.name, 'older');
      expect(list.last.name, 'newer');
    });

    test('firstWaterDate returns earliest water date, null when empty',
        () async {
      final repo = EntryRepository(db);
      expect(await repo.firstWaterDate(), isNull);
      final now = DateTime.now();
      await repo.addWater(
          amountMl: 100, at: now.subtract(const Duration(days: 3)));
      await repo.addFood(
          name: 'x', mealType: MealType.snack, kcal: 50, at: now);
      await repo.addWater(amountMl: 200, at: now);
      expect(await repo.firstWaterDate(),
          dateKey(now.subtract(const Duration(days: 3))));
    });

    test('delete removes the entry and updates totals', () async {
      final repo = EntryRepository(db);
      final id = await repo.addWater(amountMl: 500);
      final today = dateKey(DateTime.now());
      expect(await repo.waterTotalForDate(today), 500);
      await repo.delete(id);
      expect(await repo.waterTotalForDate(today), 0);
    });

    test('latestWater returns the most recent water entry', () async {
      final repo = EntryRepository(db);
      await repo.addWater(amountMl: 200);
      await Future.delayed(const Duration(milliseconds: 25));
      await repo.addFood(name: 'x', mealType: MealType.snack, kcal: 10);
      await Future.delayed(const Duration(milliseconds: 25));
      await repo.addWater(amountMl: 150);
      final last = await repo.latestWater();
      expect(last, isNotNull);
      expect(last!.amountMl, 150);
    });

    test('latestWater is null when nothing logged', () async {
      final repo = EntryRepository(db);
      expect(await repo.latestWater(), isNull);
    });

    test('waterTotalsForRange groups by day within range', () async {
      final repo = EntryRepository(db);
      final now = DateTime.now();
      await repo.addWater(amountMl: 250, at: now); // today
      await repo.addWater(amountMl: 500,
          at: now.subtract(const Duration(days: 1)));
      await repo.addWater(amountMl: 999,
          at: now.subtract(const Duration(days: 9))); // outside 7-day range
      final start = dateKey(now.subtract(const Duration(days: 6)));
      final totals = await repo.waterTotalsForRange(
          start, dateKey(now));
      expect(totals.length, 2);
      expect(totals[dateKey(now)], 250);
      expect(totals[dateKey(now.subtract(const Duration(days: 1)))], 500);
    });

    test('extra macros persist: addFood, read back, quick-log from food DB',
        () async {
      final entries = EntryRepository(db);
      final foods = FoodRepository(db);
      await entries.addFood(
        name: 'oatmeal',
        mealType: MealType.breakfast,
        kcal: 320,
        protein: 12,
        carbs: 50,
        fat: 8,
        fiber: 6,
        sugar: 14,
        sodium: 180,
      );
      final today = dateKey(DateTime.now());
      final e = (await entries.entriesForDate(today)).single;
      expect(e.fiber, 6);
      expect(e.sugar, 14);
      expect(e.sodium, 180);

      // Personal food DB keeps them, one-tap re-log carries them.
      await foods.upsertFromLog(
        name: 'oatmeal',
        kcal: 320,
        protein: 12,
        carbs: 50,
        fat: 8,
        fiber: 6,
        sugar: 14,
        sodium: 180,
      );
      final item = (await foods.recents()).single;
      expect(item.fiber, 6);
      expect(item.sugar, 14);
      expect(item.sodium, 180);
    });

    test('updateFood edits an entry in place, date/time kept', () async {
      final repo = EntryRepository(db);
      final now = DateTime.now();
      final id = await repo.addFood(
        name: 'toast',
        mealType: MealType.breakfast,
        kcal: 200,
        portion: 1,
        at: now,
      );
      final original = (await repo.entriesForDate(dateKey(now))).single;
      await repo.updateFood(Entry(
        id: id,
        type: EntryType.food,
        name: 'toast + jam',
        mealType: MealType.snack,
        kcal: 260,
        protein: 7,
        carbs: 40,
        fat: 6,
        fiber: 2,
        sugar: 10,
        sodium: 220,
        portion: 1.5,
        createdAt: original.createdAt,
        date: original.date,
      ));
      final edited = (await repo.entriesForDate(dateKey(now))).single;
      expect(edited.id, id);
      expect(edited.name, 'toast + jam');
      expect(edited.mealType, MealType.snack);
      expect(edited.kcal, 260);
      expect(edited.effectiveKcal, 390); // 260 * 1.5
      expect(edited.fiber, 2);
      expect(edited.sugar, 10);
      expect(edited.sodium, 220);
      expect(edited.createdAt, original.createdAt);
      expect(edited.date, original.date);
    });

    test('macroTotalsForRange sums protein/carbs/fat per day, portion-scaled',
        () async {
      final repo = EntryRepository(db);
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      await repo.addFood(
        name: 'a',
        mealType: MealType.lunch,
        kcal: 500,
        protein: 30,
        carbs: 60,
        fat: 20,
        portion: 2,
        at: now,
      );
      await repo.addFood(
        name: 'b',
        mealType: MealType.dinner,
        kcal: 400,
        protein: 10,
        carbs: 40,
        fat: 15,
        at: now,
      );
      await repo.addFood(
        name: 'c',
        mealType: MealType.breakfast,
        kcal: 300,
        protein: 25,
        carbs: 30,
        fat: 10,
        at: yesterday,
      );
      final totals = await repo.macroTotalsForRange(
          dateKey(yesterday), dateKey(now));
      expect(totals.length, 2);
      expect(totals[dateKey(now)]!.protein, 70); // 30*2 + 10
      expect(totals[dateKey(now)]!.carbs, 160); // 60*2 + 40
      expect(totals[dateKey(now)]!.fat, 55); // 20*2 + 15
      expect(totals[dateKey(yesterday)]!.protein, 25);
    });
  });

  group('FoodRepository', () {
    test('upsertFromLog inserts then bumps times_logged', () async {
      final repo = FoodRepository(db);
      await repo.upsertFromLog(name: 'Telur dadar', kcal: 220);
      await repo.upsertFromLog(name: 'telur dadar', kcal: 230); // case-insensitive
      final food = await repo.byName('TELUR DADAR');
      expect(food, isNotNull);
      expect(food!.timesLogged, 2);
      expect(food.kcal, 230);
    });

    test('recents ordered by last_used_at desc', () async {
      final repo = FoodRepository(db);
      await repo.upsertFromLog(name: 'old', kcal: 100);
      await Future.delayed(const Duration(milliseconds: 30));
      await repo.upsertFromLog(name: 'new', kcal: 200);
      final recents = await repo.recents();
      expect(recents.first.name, 'new');
    });

    test('favorites toggle', () async {
      final repo = FoodRepository(db);
      await repo.upsertFromLog(name: 'Nasi goreng', kcal: 743);
      final food = await repo.byName('Nasi goreng');
      await repo.toggleFavorite(food!.id!);
      expect((await repo.favorites()).length, 1);
      await repo.toggleFavorite(food.id!);
      expect((await repo.favorites()).length, 0);
    });
  });

  group('HabitRepository', () {
    test('add, enable/disable, delete cascades logs', () async {
      final repo = HabitRepository(db);
      final id = await repo.addHabit(
          name: 'Hit water goal', kind: HabitKind.waterGoal);
      final today = dateKey(DateTime.now());
      await repo.setLog(habitId: id, date: today, done: true);
      expect((await repo.logsForDate(today)).length, 1);

      await repo.setEnabled(id, false);
      expect((await repo.listHabits(enabledOnly: true)).length, 0);

      await repo.deleteHabit(id);
      expect((await repo.logsForDate(today)).length, 0); // cascade
    });

    test('setLog upserts one row per habit per day', () async {
      final repo = HabitRepository(db);
      final id = await repo.addHabit(name: 'x', kind: HabitKind.manual);
      final today = dateKey(DateTime.now());
      await repo.setLog(habitId: id, date: today, done: true);
      await repo.setLog(habitId: id, date: today, done: false);
      final logs = await repo.logsForHabit(id);
      expect(logs.length, 1);
      expect(logs.first.done, false);
    });
  });

  group('SettingsRepository', () {
    test('defaults when unset, persisted once set', () async {
      final repo = SettingsRepository(db);
      expect(await repo.waterGoalMl(), 3000);
      expect(await repo.kcalGoal(), 2000);
      expect(await repo.glassSizeMl(), 250);
      await repo.setWaterGoalMl(2500);
      await repo.setGlassSizeMl(300);
      expect(await repo.waterGoalMl(), 2500);
      expect(await repo.glassSizeMl(), 300);
      expect(await repo.kcalGoal(), 2000);
    });

    test('reminder settings default off/60 and persist', () async {
      final repo = SettingsRepository(db);
      expect(await repo.reminderEnabled(),
          SettingsRepository.defaultReminderEnabled);
      expect(await repo.reminderMinutes(),
          SettingsRepository.defaultReminderMinutes);
      await repo.setReminderEnabled(true);
      await repo.setReminderMinutes(15);
      expect(await repo.reminderEnabled(), true);
      expect(await repo.reminderMinutes(), 15);
      await repo.setReminderEnabled(false);
      expect(await repo.reminderEnabled(), false);
      expect(await repo.reminderMinutes(), 15);
    });
  });

  group('DrinkSlotRepository', () {
    test('ensureDefault seeds one glass slot', () async {
      final repo = DrinkSlotRepository(db);
      await repo.ensureDefault();
      final slots = await repo.list();
      expect(slots.length, 1);
      expect(slots.first.name, 'glass');
      expect(slots.first.ml, 250);
      // Second call does not duplicate.
      await repo.ensureDefault();
      expect(await repo.count(), 1);
    });

    test('ensureDefault never re-seeds after the user removes every cup',
        () async {
      final repo = DrinkSlotRepository(db);
      await repo.ensureDefault(); // first run seeds + marks seeded
      await repo.remove((await repo.list()).first.id!);
      expect(await repo.count(), 0);

      // Reloads and app restarts must respect the empty state.
      await repo.ensureDefault();
      expect(await repo.count(), 0);
      await repo.ensureDefault();
      expect(await repo.count(), 0);

      // Clearing the marker (debug reset wipes settings) allows seeding
      // again, which restores the fresh-install default.
      await db.delete('settings', where: "key = 'slots_seeded'");
      await repo.ensureDefault();
      expect(await repo.count(), 1);
    });

    test('add and remove slots', () async {
      final repo = DrinkSlotRepository(db);
      await repo.add(name: 'bottle', ml: 500);
      await repo.add(name: 'mug', ml: 300);
      var slots = await repo.list();
      expect(slots.length, 2);
      expect(slots[1].name, 'mug'); // ordered by position

      await repo.remove(slots.first.id!);
      slots = await repo.list();
      expect(slots.length, 1);
      expect(slots.first.name, 'mug');
    });
  });

  group('DebugDataService', () {
    test('seed fills tables, clearAll empties them', () async {
      final debug = DebugDataService(db);
      await debug.seedSampleData();
      final counts = await debug.tableCounts();
      expect(counts['entries']! >= 12, true);
      expect(counts['foods']! >= 4, true);
      expect(counts['habits'], 3);
      expect(counts['settings']! >= 3, true);

      await debug.clearAllData();
      final after = await debug.tableCounts();
      for (final v in after.values) {
        expect(v, 0);
      }
    });
  });

  group('Migrations', () {
    test('v2 -> v3 adds the extra macro columns, data survives', () async {
      // Build a real v2 database by hand (pre-macro schema).
      final path =
          '${Directory.systemTemp.path}/lil_migration_test_${DateTime.now().microsecondsSinceEpoch}.db';
      final v2 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, version) async {
          await d.execute('''
            CREATE TABLE entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT NOT NULL,
              amount_ml INTEGER,
              name TEXT,
              meal_type TEXT,
              kcal REAL,
              protein REAL,
              carbs REAL,
              fat REAL,
              portion REAL NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              date TEXT NOT NULL
            )
          ''');
          await d.execute('''
            CREATE TABLE foods (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL COLLATE NOCASE UNIQUE,
              kcal REAL NOT NULL DEFAULT 0,
              protein REAL NOT NULL DEFAULT 0,
              carbs REAL NOT NULL DEFAULT 0,
              fat REAL NOT NULL DEFAULT 0,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              times_logged INTEGER NOT NULL DEFAULT 0,
              last_used_at INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await d.execute('''
            CREATE TABLE drink_slots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              ml INTEGER NOT NULL,
              position INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL DEFAULT 0
            )
          ''');
          },
        ),
      );
      final now = DateTime.now();
      await v2.insert('entries', {
        'type': 'food',
        'name': 'old toast',
        'meal_type': 'breakfast',
        'kcal': 200.0,
        'protein': 6.0,
        'carbs': 30.0,
        'fat': 5.0,
        'portion': 1.0,
        'created_at': now.millisecondsSinceEpoch,
        'date': dateKey(now),
      });
      await v2.insert('foods', {
        'name': 'old toast',
        'kcal': 200.0,
        'protein': 6.0,
        'carbs': 30.0,
        'fat': 5.0,
        'is_favorite': 1,
        'times_logged': 1,
        'last_used_at': now.millisecondsSinceEpoch,
      });
      await v2.close();

      // Re-open through AppDatabase.openAt -> onUpgrade runs to v3.
      final upgraded = await AppDatabase.openAt(path);
      addTearDown(upgraded.close);
      final columns = (await upgraded.rawQuery('PRAGMA table_info(entries)'))
          .map((r) => r['name'])
          .toSet();
      expect(columns, containsAll(['fiber', 'sugar', 'sodium']));

      // Pre-existing rows read fine (nulls) and new writes persist.
      final entries = EntryRepository(upgraded);
      final old = (await entries.entriesForDate(dateKey(now))).single;
      expect(old.name, 'old toast');
      expect(old.fiber, isNull);
      await entries.addFood(
          name: 'new meal', mealType: MealType.dinner, kcal: 100, fiber: 3);
      final newer =
          (await entries.entriesForDate(dateKey(now))).last;
      expect(newer.fiber, 3);

      final foods = FoodRepository(upgraded);
      final fav = (await foods.favorites()).single;
      expect(fav.name, 'old toast');
      expect(fav.fiber, 0);
      await foods.upsertFromLog(
          name: 'old toast', kcal: 210, fiber: 2, sugar: 4, sodium: 90);
      expect((await foods.byName('old toast'))!.sodium, 90);
    });
  });
}
