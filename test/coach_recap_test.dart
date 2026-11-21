import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lil_routine/core/ai/ai_key_store.dart';
import 'package:lil_routine/core/ai/gemini_provider.dart';
import 'package:lil_routine/core/data/entry_repository.dart';
import 'package:lil_routine/core/data/models.dart';
import 'package:lil_routine/core/data/settings_repository.dart';
import 'package:lil_routine/core/db/app_database.dart';
import 'package:lil_routine/core/insights/coach_recap.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openDb() => databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          onCreate: (d, _) => AppDatabase.createSchema(d),
        ),
      );

  test('weekKeyFor is Monday-based', () {
    // Wed Oct 28 2026 -> week starts Mon Oct 26.
    expect(CoachRecap.weekKeyFor(DateTime(2026, 10, 28)), '2026-10-26');
    // Monday itself.
    expect(CoachRecap.weekKeyFor(DateTime(2026, 10, 26)), '2026-10-26');
    // Sunday Oct 25 -> still the week of Mon Oct 19.
    expect(CoachRecap.weekKeyFor(DateTime(2026, 10, 25)), '2026-10-19');
  });

  test('isDue: never ran, malformed, or 7+ days -> true; fresh -> false',
      () {
    final now = DateTime(2026, 10, 30, 12);
    expect(CoachRecap.isDue(null, now), isTrue);
    expect(CoachRecap.isDue('not-a-date', now), isTrue);
    expect(
      CoachRecap.isDue(
        now.subtract(const Duration(days: 6, hours: 23)).toIso8601String(),
        now,
      ),
      isFalse,
    );
    expect(
      CoachRecap.isDue(
        now.subtract(const Duration(days: 7)).toIso8601String(),
        now,
      ),
      isTrue,
    );
  });

  test('CoachRecapData JSON roundtrip + rejects garbage', () {
    final data = CoachRecapData(
      weekKey: '2026-10-26',
      tips: const [
        WeeklyTip(title: 'salty days', body: 'Drink more on Thu.'),
      ],
      at: DateTime(2026, 10, 30, 18),
    );
    final parsed = CoachRecapData.fromJson(jsonEncode(data.toJson()));
    expect(parsed, isNotNull);
    expect(parsed!.weekKey, '2026-10-26');
    expect(parsed.tips.single.title, 'salty days');
    expect(parsed.tips.single.body, 'Drink more on Thu.');
    expect(parsed.at, DateTime(2026, 10, 30, 18));
    expect(CoachRecapData.fromJson('garbage'), isNull);
    expect(CoachRecapData.fromJson('{"tips": []}'), isNull);
  });

  test('maybeRun: no key -> null, nothing saved', () async {
    final db = await openDb();
    final ran = await CoachRecap.maybeRun(
      db: db,
      keyStore: InMemoryAiKeyStore(),
      now: DateTime(2026, 10, 30, 18),
    );
    expect(ran, isNull);
    expect(await SettingsRepository(db).lastCoachRecap(), isNull);
    await db.close();
  });

  test('maybeRun: not due -> null and cache untouched', () async {
    final db = await openDb();
    final settings = SettingsRepository(db);
    await settings.saveCoachRecap(
      weekKey: '2026-10-26',
      json: '{"tips":[{"title":"old","body":"recap"}]}',
      at: DateTime(2026, 10, 30, 18),
    );
    final ran = await CoachRecap.maybeRun(
      db: db,
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      now: DateTime(2026, 11, 2, 9), // < 7 days later
    );
    expect(ran, isNull);
    final cached = await settings.lastCoachRecap();
    final parsed = CoachRecapData.fromJson(cached!);
    expect(parsed!.tips.single.title, 'old');
    await db.close();
  });

  test('collectStats aggregates kcal/sodium/sugar/water for 7 days',
      () async {
    final db = await openDb();
    final entries = EntryRepository(db);
    final now = DateTime(2026, 10, 30, 18);
    final today = DateTime(2026, 10, 30, 13);
    final fourDaysAgo = DateTime(2026, 10, 26, 13);

    await entries.addFood(
      name: 'ramen',
      mealType: MealType.dinner,
      kcal: 700,
      protein: 20,
      carbs: 90,
      fat: 25,
      fiber: 4,
      sugar: 6,
      sodium: 1600,
      portion: 1.5,
      at: today,
    );
    await entries.addWater(amountMl: 1500, at: today);
    await entries.addWater(amountMl: 3100, at: fourDaysAgo);

    final stats = await CoachRecap.collectStats(
      db: db,
      now: now,
      kcalGoal: 2000,
      waterGoalMl: 3000,
    );
    expect(stats, hasLength(7));
    final todayStats = stats.last;
    expect(todayStats.label, contains('today'));
    expect(todayStats.kcal, 1050); // 700 * 1.5
    expect(todayStats.sodiumMg, 2400); // 1600 * 1.5
    expect(todayStats.sugarG, 9); // 6 * 1.5
    expect(todayStats.waterMl, 1500);
    expect(stats[2].waterMl, 3100); // Oct 26 = 4 days back
    await db.close();
  });

  test('settings recap storage: last pointer + per-week history', () async {
    final db = await openDb();
    final settings = SettingsRepository(db);
    await settings.saveCoachRecap(
      weekKey: '2026-10-19',
      json: '{"tips":[{"title":"w1","body":"one"}]}',
      at: DateTime(2026, 10, 23, 9),
    );
    await settings.saveCoachRecap(
      weekKey: '2026-10-26',
      json: '{"tips":[{"title":"w2","body":"two"}]}',
      at: DateTime(2026, 10, 30, 9),
    );
    final history = await settings.coachRecapHistory();
    expect(history.map((r) => r.$1).toList(), ['2026-10-26', '2026-10-19']);
    final cached = await settings.lastCoachRecap();
    final last = CoachRecapData.fromJson(cached!);
    expect(last!.tips.single.title, 'w2');
    expect(await settings.coachRecapAt(),
        DateTime(2026, 10, 30, 9).toIso8601String());
    await db.close();
  });
}
