import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../ai/ai_key_store.dart';
import '../ai/gemini_provider.dart';
import '../data/entry_repository.dart';
import '../data/models.dart';
import '../data/settings_repository.dart';

/// One cached weekly recap, ready to render.
class CoachRecapData {
  const CoachRecapData({
    required this.weekKey,
    required this.tips,
    required this.at,
  });

  final String weekKey; // Monday date key of the recap's week
  final List<WeeklyTip> tips;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'weekKey': weekKey,
        'at': at.toIso8601String(),
        'tips': [for (final t in tips) t.toJson()],
      };

  static CoachRecapData? fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final list = decoded['tips'];
      if (list is! List) return null;
      final tips = <WeeklyTip>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) tips.add(WeeklyTip.fromJson(item));
      }
      if (tips.isEmpty) return null;
      return CoachRecapData(
        weekKey: decoded['weekKey'] as String? ?? '',
        tips: tips,
        at: DateTime.tryParse(decoded['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } on Object {
      return null;
    }
  }
}

/// Weekly AI coach recap (LIL-22).
///
/// Cadence: automatic, at most once per 7 days — runs on the first
/// meals-dashboard load whose [isDue] says a week has passed AND a key
/// is configured. Everything else (AI off, no key, no network) leaves
/// the app exactly as before: rule-based insights only.
abstract final class CoachRecap {
  /// Monday-based week key: the week a recap belongs to.
  static String weekKeyFor(DateTime now) {
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return dateKey(DateTime(monday.year, monday.month, monday.day));
  }

  /// A new recap is due when the last one is 7+ days old (or never ran).
  static bool isDue(String? lastAtIso, DateTime now) {
    if (lastAtIso == null) return true;
    final last = DateTime.tryParse(lastAtIso);
    if (last == null) return true;
    return now.difference(last) >= const Duration(days: 7);
  }

  /// Aggregates the last 7 days (numbers only) from the DB.
  static Future<List<RecapDayStats>> collectStats({
    required Database db,
    required DateTime now,
    required int kcalGoal,
    required int waterGoalMl,
  }) async {
    final entries = EntryRepository(db);
    final todayKey = dateKey(now);
    final startKey = dateKey(now.subtract(const Duration(days: 6)));
    final kcal = await entries.kcalTotalsForRange(startKey, todayKey);
    final macros = await entries.macroTotalsForRange(startKey, todayKey);
    final micros = await entries.microTotalsForRange(startKey, todayKey);
    final water = await entries.waterTotalsForRange(startKey, todayKey);

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final stats = <RecapDayStats>[];
    for (var i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = dateKey(date);
      final m = macros[key] ?? MacroTotals.zero();
      final mi = micros[key] ?? MicroTotals.zero();
      stats.add(RecapDayStats(
        label:
            '${weekdays[date.weekday - 1]} ${months[date.month - 1]} '
            '${date.day}${i == 0 ? ' (today)' : ''}',
        kcal: (kcal[key] ?? 0).round(),
        proteinG: m.protein.round(),
        carbsG: m.carbs.round(),
        fatG: m.fat.round(),
        sodiumMg: mi.sodiumMg.round(),
        sugarG: mi.sugarG.round(),
        waterMl: water[key] ?? 0,
      ));
    }
    return stats;
  }

  /// Runs the whole recap flow when due. Returns the fresh data on
  /// success; null when not due, AI off, or anything failed (silent —
  /// rule-based insights keep the dashboard useful).
  static Future<CoachRecapData?> maybeRun({
    required Database db,
    required AiKeyStore keyStore,
    required DateTime now,
  }) async {
    final settings = SettingsRepository(db);
    if (!await AiGate(keyStore).isConfigured()) return null;
    if (!isDue(await settings.coachRecapAt(), now)) return null;

    final kcalGoal = await settings.kcalGoal();
    final waterGoal = await settings.waterGoalMl();
    final stats =
        await collectStats(db: db, now: now, kcalGoal: kcalGoal, waterGoalMl: waterGoal);

    final provider = GeminiProvider(keyStore: keyStore);
    final result = await provider.weeklyRecap(
      days: stats,
      kcalGoal: kcalGoal,
      waterGoalMl: waterGoal,
    );
    if (!result.ok || result.tips == null) return null;

    final data = CoachRecapData(
      weekKey: weekKeyFor(now),
      tips: result.tips!,
      at: now,
    );
    await settings.saveCoachRecap(
      weekKey: data.weekKey,
      json: jsonEncode(data.toJson()),
      at: now,
    );
    return data;
  }
}
