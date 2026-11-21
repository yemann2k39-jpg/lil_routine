import '../data/models.dart';

/// Rule-based, deterministic insights for the dashboards.
///
/// Niko's ground rules:
/// - Accuracy first: every rule is plain math over the user's own logs —
///   no AI here (AI only powers the weekly recap).
/// - Water and food are connected: cross-domain rules (salty day ->
///   extra water, sweet afternoon -> water, heavy dinner -> morning
///   water) live in the same engine.
/// - Local-first: everything computes from entries already on the phone.
///
/// The engine is a pure function: [InsightEngineInput] in, insights out.
/// UI layers filter by [Insight.scope] and cap how many they show.
enum InsightKind {
  /// Time-sensitive action for today (nudges).
  nudge,

  /// Water <-> food connection (Niko's cross-domain rules).
  link,

  /// Positive reinforcement for streaks/consistency.
  celebrate,

  /// Neutral pattern observation.
  pattern,

  /// Gentle goal suggestion (never auto-applied).
  goal,
}

/// Which dashboard an insight belongs on.
enum InsightScope { water, food, both }

class Insight {
  const Insight({
    required this.id,
    required this.kind,
    required this.scope,
    required this.title,
    required this.message,
  });

  final String id;
  final InsightKind kind;
  final InsightScope scope;
  final String title;
  final String message;
}

/// Everything the engine needs: raw entries for the last 7 days
/// (including today) plus the current goals.
class InsightEngineInput {
  const InsightEngineInput({
    required this.foodEntries,
    required this.waterEntries,
    required this.goalKcal,
    required this.goalMl,
    required this.now,
  });

  final List<Entry> foodEntries;
  final List<Entry> waterEntries;
  final int goalKcal;
  final int goalMl;
  final DateTime now;
}

/// WHO daily sodium reference used for the salty-day rule (mg).
const int kSodiumDailyLimitMg = 2300;

class InsightEngine {
  InsightEngine._();

  /// Priority order: today's actions first, then links, celebrations,
  /// patterns, goal suggestions.
  static const _priority = {
    InsightKind.nudge: 0,
    InsightKind.link: 1,
    InsightKind.celebrate: 2,
    InsightKind.pattern: 3,
    InsightKind.goal: 4,
  };

  static List<Insight> generate(InsightEngineInput input) {
    final insights = <Insight>[];
    final now = input.now;
    final todayKey = dateKey(now);
    final yesterdayKey = dateKey(now.subtract(const Duration(days: 1)));

    final foodByDate = <String, List<Entry>>{};
    for (final e in input.foodEntries) {
      foodByDate.putIfAbsent(e.date, () => []).add(e);
    }
    final waterByDate = <String, List<Entry>>{};
    for (final e in input.waterEntries) {
      waterByDate.putIfAbsent(e.date, () => []).add(e);
    }

    final todayFood = foodByDate[todayKey] ?? const [];
    final todayWaterMl = _ml(waterByDate[todayKey] ?? const []);
    final yesterdayFood = foodByDate[yesterdayKey] ?? const [];
    final yesterdayWaterMl = _ml(waterByDate[yesterdayKey] ?? const []);

    // --- Today-based rules (fire even with little history) -------------

    // Eat-more nudge: well under goal late in the day.
    final todayKcal = _kcal(todayFood);
    if (now.hour >= 17 &&
        todayKcal > 0 &&
        todayKcal < input.goalKcal * 0.6) {
      insights.add(const Insight(
        id: 'eat-more',
        kind: InsightKind.nudge,
        scope: InsightScope.food,
        title: 'plenty of room left',
        message:
            'You are well under your goal today — a cozy snack is okay!',
      ));
    }

    // Cross-domain: salty day -> extra water.
    final todaySodiumMg = _sodiumMg(todayFood);
    if (now.hour >= 12 &&
        todaySodiumMg > kSodiumDailyLimitMg &&
        todayWaterMl < input.goalMl * 0.7) {
      insights.add(Insight(
        id: 'salty-day-water',
        kind: InsightKind.link,
        scope: InsightScope.both,
        title: 'salty day today',
        message:
            'Your sodium is over ${formatMg(kSodiumDailyLimitMg)} mg — '
            'your body will want extra water. One more glass helps.',
      ));
    }

    // Cross-domain: sweet afternoon -> water.
    final afternoonSugarG = _sugarGInRange(todayFood, 12, 17);
    if (now.hour >= 14 &&
        afternoonSugarG >= 15 &&
        todayWaterMl < input.goalMl * 0.7) {
      insights.add(const Insight(
        id: 'sweet-afternoon-water',
        kind: InsightKind.link,
        scope: InsightScope.both,
        title: 'sweet afternoon',
        message:
            'Lots of sugar since lunch — sweet treats make you thirstier '
            'than you think. Time for some water.',
      ));
    }

    // Cross-domain: heavy dinner + low water yesterday -> morning water.
    final yesterdayKcal = _kcal(yesterdayFood);
    final yesterdayDinnerKcal = _kcalByMeal(yesterdayFood, MealType.dinner);
    if (now.hour <= 11 &&
        yesterdayWaterMl > 0 &&
        yesterdayWaterMl < input.goalMl * 0.6 &&
        yesterdayKcal >= 500 &&
        yesterdayDinnerKcal >= yesterdayKcal * 0.4) {
      insights.add(const Insight(
        id: 'morning-after-water',
        kind: InsightKind.link,
        scope: InsightScope.both,
        title: 'heavy dinner last night',
        message:
            'With a big dinner and less water yesterday, start today '
            'with a big glass of water.',
      ));
    }

    // --- Pattern rules (need >= 3 days of history to be fair) ----------

    final foodDayCount = foodByDate.length;
    final waterDayCount = waterByDate.length;

    if (waterDayCount >= 3) {
      // Water timing: morning (before 14:00) vs rest of the day.
      var morningMl = 0;
      var totalMl = 0;
      for (final e in input.waterEntries) {
        totalMl += e.amountMl ?? 0;
        if (e.createdAt.hour < 14) morningMl += e.amountMl ?? 0;
      }
      if (totalMl > 0) {
        final share = morningMl / totalMl;
        if (share >= 0.7) {
          insights.add(const Insight(
            id: 'water-front-loader',
            kind: InsightKind.pattern,
            scope: InsightScope.water,
            title: 'morning drinker',
            message:
                'Most of your water lands before 2pm — nice early habit. '
                'A small glass in the evening keeps nights comfy.',
          ));
        } else if (share <= 0.3) {
          insights.add(const Insight(
            id: 'water-evening-drinker',
            kind: InsightKind.pattern,
            scope: InsightScope.water,
            title: 'evening drinker',
            message:
                'Most of your water comes late in the day. One glass '
                'with breakfast would spread it out nicely.',
          ));
        }
      }
    }

    if (foodDayCount >= 3) {
      // Biggest meal of the day.
      final mealTotals = <MealType, double>{};
      for (final e in input.foodEntries) {
        if (e.mealType != null) {
          mealTotals[e.mealType!] =
              (mealTotals[e.mealType!] ?? 0) + (e.effectiveKcal ?? 0);
        }
      }
      if (mealTotals.isNotEmpty) {
        final entries = mealTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top = entries.first;
        if (top.value >= 0.4 * mealTotals.values.fold(0, (a, b) => a + b)) {
          insights.add(Insight(
            id: 'biggest-meal',
            kind: InsightKind.pattern,
            scope: InsightScope.food,
            title: '${top.key.name} is your main meal',
            message:
                '${_cap(top.key.name)} carries most of your calories '
                'this week — planning it well goes a long way.',
          ));
        }
      }

      // Late-night snacking.
      final lateCount = input.foodEntries
          .where((e) =>
              e.mealType == MealType.snack &&
              (e.createdAt.hour >= 21 || e.createdAt.hour < 5))
          .length;
      if (lateCount >= 3) {
        insights.add(Insight(
          id: 'late-night-snacks',
          kind: InsightKind.pattern,
          scope: InsightScope.food,
          title: 'late-night snacking',
          message:
              'You logged $lateCount snacks after 9pm this week. Moving '
              'them earlier usually feels better the next morning.',
        ));
      }

      // Weekday vs weekend protein contrast.
      final weekdayProtein = _avgMacroFor(input.foodEntries, (d) => d.weekday <= 5,
          (e) => e.protein ?? 0);
      final weekendProtein = _avgMacroFor(input.foodEntries, (d) => d.weekday >= 6,
          (e) => e.protein ?? 0);
      if (weekdayProtein >= 0 &&
          weekendProtein >= 0 &&
          weekdayProtein - weekendProtein >= 15) {
        insights.add(Insight(
          id: 'weekday-protein-dip',
          kind: InsightKind.pattern,
          scope: InsightScope.food,
          title: 'protein dips on weekends',
          message:
              'Your weekends average ${weekendProtein.round()} g protein '
              'vs ${weekdayProtein.round()} g on weekdays — eggs or '
              'yogurt at brunch closes the gap.',
        ));
      } else if (weekendProtein - weekdayProtein >= 15) {
        insights.add(Insight(
          id: 'weekend-protein-dip',
          kind: InsightKind.pattern,
          scope: InsightScope.food,
          title: 'protein dips on weekdays',
          message:
              'Weekdays average ${weekdayProtein.round()} g protein vs '
              '${weekendProtein.round()} g on weekends — a protein-y '
              'breakfast fixes weekday slumps.',
        ));
      }

      // Realistic goal suggestion: consistently far under, no over days.
      final loggedDays = foodByDate.values
          .map(_kcal)
          .where((k) => k > 0)
          .toList(growable: false);
      if (loggedDays.length >= 5) {
        final avg = loggedDays.fold(0.0, (a, b) => a + b) / loggedDays.length;
        final overDays = loggedDays.where((k) => k > input.goalKcal).length;
        if (overDays == 0 && avg <= input.goalKcal * 0.75) {
          final suggested =
              ((avg / 50).round() * 50).clamp(1200, input.goalKcal).round();
          if (suggested < input.goalKcal) {
            insights.add(Insight(
              id: 'goal-lower',
              kind: InsightKind.goal,
              scope: InsightScope.food,
              title: 'goal might be roomy',
              message:
                  'You usually land around ${formatKcal(avg)} kcal — a '
                  '$suggested kcal goal might fit your week better. '
                  'You can change it in settings.',
            ));
          }
        } else if (overDays >= 4) {
          final avgOver = loggedDays.fold(0.0, (a, b) => a + b) /
              loggedDays.length;
          final suggested =
              ((avgOver / 50).ceil() * 50).clamp(input.goalKcal, 5000).round();
          if (suggested > input.goalKcal) {
            insights.add(Insight(
              id: 'goal-higher',
              kind: InsightKind.goal,
              scope: InsightScope.food,
              title: 'goal feels tight',
              message:
                  'You went over your goal on $overDays of the last days. '
                  'A gentler $suggested kcal target might be easier to '
                  'keep — adjust in settings if you like.',
            ));
          }
        }
      }
    }

    // Goal streaks: consecutive days ending today/yesterday. These run
    // outside the food-history gate so water-only streaks still count.
    final underStreak = _streakEndingNow(
      (key) => _kcal(foodByDate[key] ?? const []) > 0,
      (key) => _kcal(foodByDate[key] ?? const []) <= input.goalKcal,
      todayKey,
      now,
    );
    final waterStreak = _streakEndingNow(
      (key) => _ml(waterByDate[key] ?? const []) >= input.goalMl,
      (key) => true,
      todayKey,
      now,
    );
    if (underStreak >= 4) {
      insights.add(Insight(
        id: 'kcal-streak',
        kind: InsightKind.celebrate,
        scope: InsightScope.food,
        title: '$underStreak-day goal streak',
        message:
            '$underStreak days in a row under your calorie goal — '
            'steady and strong. Keep being kind to yourself.',
      ));
    }
    if (waterStreak >= 4) {
      insights.add(Insight(
        id: 'water-streak',
        kind: InsightKind.celebrate,
        scope: InsightScope.water,
        title: '$waterStreak-day water streak',
        message:
            '$waterStreak days in a row hitting your water goal — '
            'your body says thank you!',
      ));
    }

    insights.sort((a, b) {
      final p = (_priority[a.kind]! - _priority[b.kind]!);
      if (p != 0) return p;
      return a.id.compareTo(b.id);
    });
    return insights;
  }

  // --- helpers ---------------------------------------------------------

  static double _kcal(List<Entry> food) =>
      food.fold(0, (s, e) => s + (e.effectiveKcal ?? 0));

  static int _ml(List<Entry> water) =>
      water.fold(0, (s, e) => s + (e.amountMl ?? 0));

  static double _sodiumMg(List<Entry> food) => food.fold(
      0, (s, e) => s + (e.sodium ?? 0) * e.portion);

  static double _sugarGInRange(List<Entry> food, int fromHour, int toHour) =>
      food
          .where((e) =>
              e.createdAt.hour >= fromHour && e.createdAt.hour < toHour)
          .fold(0, (s, e) => s + (e.sugar ?? 0) * e.portion);

  static double _kcalByMeal(List<Entry> food, MealType meal) => food
      .where((e) => e.mealType == meal)
      .fold(0, (s, e) => s + (e.effectiveKcal ?? 0));

  /// Average of a per-entry macro over days matching [dayFilter]
  /// (days with at least one food entry). Returns -1 when the group has
  /// no days, so callers can require both groups to exist.
  static double _avgMacroFor(
    List<Entry> food,
    bool Function(DateTime) dayFilter,
    double Function(Entry) pick,
  ) {
    final byDate = <String, List<Entry>>{};
    for (final e in food) {
      byDate.putIfAbsent(e.date, () => []).add(e);
    }
    var sum = 0.0;
    var days = 0;
    for (final entry in byDate.entries) {
      final parts = entry.key.split('-');
      final d = DateTime(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      if (!dayFilter(d)) continue;
      sum += entry.value.fold(0.0, (s, e) => s + pick(e) * e.portion);
      days++;
    }
    if (days == 0) return -1;
    return sum / days;
  }

  /// Count of consecutive days ending today (or yesterday, when today
  /// has no data yet) that satisfy [ok]. Days with no data break it.
  static int _streakEndingNow(
    bool Function(String) hasLog,
    bool Function(String) ok,
    String todayKey,
    DateTime now,
  ) {
    var streak = 0;
    var cursor = now;
    // Today with no log yet doesn't break yesterday-based streaks.
    if (!hasLog(todayKey)) cursor = cursor.subtract(const Duration(days: 1));
    for (var i = 0; i < 30; i++) {
      final key = dateKey(cursor);
      if (!hasLog(key) || !ok(key)) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Thousands-separated kcal (kept in sync with the dashboard format).
  static String formatKcal(num kcal) {
    final s = kcal.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      b.write(s[i]);
      final remaining = s.length - 1 - i;
      if (remaining > 0 && remaining % 3 == 0) b.write(',');
    }
    return b.toString();
  }

  static String formatMg(num mg) => formatKcal(mg);
}
