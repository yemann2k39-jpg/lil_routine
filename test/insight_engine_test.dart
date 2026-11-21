import 'package:flutter_test/flutter_test.dart';
import 'package:lil_routine/core/data/models.dart';
import 'package:lil_routine/core/insights/insight_engine.dart';

void main() {
  final now = DateTime(2026, 10, 30, 18); // Friday evening

  Entry food(
    DateTime at, {
    MealType meal = MealType.lunch,
    double kcal = 300,
    double protein = 10,
    double carbs = 30,
    double fat = 10,
    double sugar = 2,
    double sodium = 200,
    double portion = 1,
  }) =>
      Entry(
        type: EntryType.food,
        name: 'x',
        mealType: meal,
        kcal: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        sugar: sugar,
        sodium: sodium,
        portion: portion,
        createdAt: at,
        date: dateKey(at),
      );

  Entry water(DateTime at, int ml) => Entry(
        type: EntryType.water,
        amountMl: ml,
        createdAt: at,
        date: dateKey(at),
      );

  InsightEngineInput input({
    List<Entry> foodEntries = const [],
    List<Entry> waterEntries = const [],
    int goalKcal = 2000,
    int goalMl = 2000,
    DateTime? at,
  }) =>
      InsightEngineInput(
        foodEntries: foodEntries,
        waterEntries: waterEntries,
        goalKcal: goalKcal,
        goalMl: goalMl,
        now: at ?? now,
      );

  test('no data -> no insights', () {
    expect(InsightEngine.generate(input()), isEmpty);
  });

  test('eat-more nudge fires late in the day when well under goal',
      () {
    final today =
        food(DateTime(2026, 10, 30, 13), kcal: 800); // 40% of 2000
    final insights = InsightEngine.generate(input(foodEntries: [today]));
    final nudge = insights.firstWhere((i) => i.id == 'eat-more');
    expect(nudge.kind, InsightKind.nudge);
    expect(nudge.scope, InsightScope.food);

    // Too early -> no nudge.
    final early = InsightEngine.generate(
        input(foodEntries: [today], at: DateTime(2026, 10, 30, 15)));
    expect(early.where((i) => i.id == 'eat-more'), isEmpty);

    // Near goal -> no nudge.
    final full = food(DateTime(2026, 10, 30, 13), kcal: 1800);
    final done = InsightEngine.generate(input(foodEntries: [full]));
    expect(done.where((i) => i.id == 'eat-more'), isEmpty);
  });

  test('salty day suggests extra water (cross-domain)', () {
    final salty = food(DateTime(2026, 10, 30, 13),
        sodium: 1400, portion: 2); // 2800 mg today
    final drinks = [water(DateTime(2026, 10, 30, 9), 800)];
    final insights =
        InsightEngine.generate(input(foodEntries: [salty], waterEntries: drinks));
    final link = insights.firstWhere((i) => i.id == 'salty-day-water');
    expect(link.kind, InsightKind.link);
    expect(link.scope, InsightScope.both);

    // Water already high -> no need to nag.
    final hydrated = [
      water(DateTime(2026, 10, 30, 9), 800),
      water(DateTime(2026, 10, 30, 12), 800),
    ];
    final ok = InsightEngine.generate(
        input(foodEntries: [salty], waterEntries: hydrated));
    expect(ok.where((i) => i.id == 'salty-day-water'), isEmpty);
  });

  test('sweet afternoon suggests water (cross-domain)', () {
    final sweet = food(DateTime(2026, 10, 30, 15),
        meal: MealType.snack, sugar: 20);
    final insights = InsightEngine.generate(
        input(foodEntries: [sweet], waterEntries: [
      water(DateTime(2026, 10, 30, 9), 500),
    ]));
    expect(
        insights.any((i) => i.id == 'sweet-afternoon-water'), isTrue);
  });

  test('heavy dinner + low water yesterday -> morning water tip', () {
    final dinner =
        food(DateTime(2026, 10, 29, 20), meal: MealType.dinner, kcal: 800);
    final lunch = food(DateTime(2026, 10, 29, 12), kcal: 800);
    final insights = InsightEngine.generate(input(
      foodEntries: [dinner, lunch],
      waterEntries: [water(DateTime(2026, 10, 29, 10), 800)],
      at: DateTime(2026, 10, 30, 8),
    ));
    expect(insights.any((i) => i.id == 'morning-after-water'), isTrue);
  });

  test('water timing pattern: front loader and evening drinker', () {
    final drinks = <Entry>[
      // 3+ days, 80% of ml before 14:00
      water(DateTime(2026, 10, 28, 9), 600),
      water(DateTime(2026, 10, 28, 20), 100),
      water(DateTime(2026, 10, 29, 9), 600),
      water(DateTime(2026, 10, 29, 21), 100),
      water(DateTime(2026, 10, 30, 9), 600),
      water(DateTime(2026, 10, 30, 20), 100),
    ];
    final insights = InsightEngine.generate(input(waterEntries: drinks));
    expect(insights.any((i) => i.id == 'water-front-loader'), isTrue);
    expect(insights.any((i) => i.id == 'water-evening-drinker'), isFalse);

    // Flip the ratio -> evening drinker.
    final late = <Entry>[
      for (final day in [28, 29, 30]) ...[
        water(DateTime(2026, 10, day, 9), 100),
        water(DateTime(2026, 10, day, 20), 600),
      ]
    ];
    final evening = InsightEngine.generate(input(waterEntries: late));
    expect(evening.any((i) => i.id == 'water-evening-drinker'), isTrue);
  });

  test('biggest meal pattern requires 40% dominance', () {
    final days = <Entry>[
      food(DateTime(2026, 10, 28, 12), meal: MealType.lunch, kcal: 400),
      food(DateTime(2026, 10, 28, 20), meal: MealType.dinner, kcal: 900),
      food(DateTime(2026, 10, 29, 12), meal: MealType.lunch, kcal: 300),
      food(DateTime(2026, 10, 29, 20), meal: MealType.dinner, kcal: 850),
      food(DateTime(2026, 10, 30, 12), meal: MealType.lunch, kcal: 350),
      food(DateTime(2026, 10, 30, 20), meal: MealType.dinner, kcal: 800),
    ];
    final insights = InsightEngine.generate(input(foodEntries: days));
    final biggest = insights.firstWhere((i) => i.id == 'biggest-meal');
    expect(biggest.title, 'dinner is your main meal');
    expect(biggest.message, contains('Dinner carries most'));
  });

  test('late-night snacking counts post-9pm snacks', () {
    final days = <Entry>[
      food(DateTime(2026, 10, 28, 22), meal: MealType.snack, kcal: 150),
      food(DateTime(2026, 10, 29, 23), meal: MealType.snack, kcal: 150),
      food(DateTime(2026, 10, 30, 21), meal: MealType.snack, kcal: 150),
      food(DateTime(2026, 10, 30, 12), meal: MealType.lunch, kcal: 400),
    ];
    final insights = InsightEngine.generate(input(foodEntries: days));
    expect(insights.any((i) => i.id == 'late-night-snacks'), isTrue);
  });

  test('weekday vs weekend protein contrast (both directions)', () {
    Entry day(DateTime d, double protein) =>
        food(DateTime(d.year, d.month, d.day, 12), protein: protein);

    final days = <Entry>[
      day(DateTime(2026, 10, 26), 40), // Mon
      day(DateTime(2026, 10, 27), 40), // Tue
      day(DateTime(2026, 10, 28), 40), // Wed
      day(DateTime(2026, 10, 24), 10), // Sat
      day(DateTime(2026, 10, 25), 10), // Sun
    ];
    final insights = InsightEngine.generate(input(foodEntries: days));
    expect(insights.any((i) => i.id == 'weekday-protein-dip'), isTrue);

    // Reverse: weekdays low, weekend high.
    final flipped = <Entry>[
      day(DateTime(2026, 10, 26), 10),
      day(DateTime(2026, 10, 27), 10),
      day(DateTime(2026, 10, 28), 10),
      day(DateTime(2026, 10, 24), 40),
      day(DateTime(2026, 10, 25), 40),
    ];
    final flippedInsights =
        InsightEngine.generate(input(foodEntries: flipped));
    expect(
        flippedInsights.any((i) => i.id == 'weekend-protein-dip'), isTrue);
  });

  test('kcal goal streak celebrates 4+ consecutive under days', () {
    final days = <Entry>[
      for (final d in [26, 27, 28, 29, 30])
        food(DateTime(2026, 10, d, 12), kcal: 1500),
    ];
    final insights = InsightEngine.generate(input(foodEntries: days));
    final streak = insights.firstWhere((i) => i.id == 'kcal-streak');
    expect(streak.title, contains('5-day'));
  });

  test('water goal streak counts consecutive goal hits', () {
    final drinks = <Entry>[
      for (final d in [27, 28, 29, 30])
        water(DateTime(2026, 10, d, 10), 2200),
    ];
    final insights = InsightEngine.generate(input(waterEntries: drinks));
    final streak = insights.firstWhere((i) => i.id == 'water-streak');
    expect(streak.title, contains('4-day'));
  });

  test('goal suggestions: roomy goal down, tight goal up', () {
    // Always ~1200 of 2000 -> suggest 1200.
    final lowDays = <Entry>[
      for (final d in [26, 27, 28, 29, 30])
        food(DateTime(2026, 10, d, 12), kcal: 1200),
    ];
    final down = InsightEngine.generate(input(foodEntries: lowDays));
    final lower = down.firstWhere((i) => i.id == 'goal-lower');
    expect(lower.message, contains('1200 kcal'));

    // Often over (1700 avg of 1800-1600s vs 2000? build over days):
    final overDays = <Entry>[
      for (final d in [26, 27, 28, 29])
        food(DateTime(2026, 10, d, 12), kcal: 2400),
      food(DateTime(2026, 10, 30, 12), kcal: 2200),
    ];
    final up = InsightEngine.generate(input(foodEntries: overDays));
    final higher = up.firstWhere((i) => i.id == 'goal-higher');
    expect(higher.message, contains('over your goal on 5'));
  });

  test('insights sorted: nudge first, goal suggestions last', () {
    final today = food(DateTime(2026, 10, 30, 13), kcal: 800);
    final week = <Entry>[
      today,
      for (final d in [26, 27, 28, 29])
        food(DateTime(2026, 10, d, 12), kcal: 1200),
    ];
    final insights = InsightEngine.generate(input(foodEntries: week));
    expect(insights.first.kind, InsightKind.nudge);
    expect(insights.last.kind, InsightKind.goal);
  });
}
