import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lil_routine/core/ai/gemini_provider.dart';
import 'package:lil_routine/core/insights/coach_recap.dart';
import 'package:lil_routine/core/insights/insight_engine.dart';
import 'package:lil_routine/features/food/food_history_screen.dart';
import 'package:lil_routine/features/insights/insight_card.dart';
import 'package:lil_routine/features/water/water_history_screen.dart';

void main() {

  Insight nudge() => const Insight(
        id: 'eat-more',
        kind: InsightKind.nudge,
        scope: InsightScope.food,
        title: 'plenty of room left',
        message: 'You are well under your goal today — a cozy snack is okay!',
      );

  Insight link() => const Insight(
        id: 'salty-day-water',
        kind: InsightKind.link,
        scope: InsightScope.both,
        title: 'salty day today',
        message: 'Your sodium is over 2,300 mg — drink an extra glass.',
      );

  Insight waterPattern() => const Insight(
        id: 'water-front-loader',
        kind: InsightKind.pattern,
        scope: InsightScope.water,
        title: 'morning drinker',
        message: 'Most of your water lands before 2pm.',
      );

  MealDay day(String date, String label, double kcal) =>
      MealDay(date: date, total: kcal, label: label);

  List<MealDay> week() => [
        day('2026-10-24', 'Sat', 1500),
        day('2026-10-25', 'Sun', 1600),
        day('2026-10-26', 'Mon', 1500),
        day('2026-10-27', 'Tue', 1500),
        day('2026-10-28', 'Wed', 1500),
        day('2026-10-29', 'Thu', 1500),
        day('2026-10-30', 'Today', 800),
      ];

  testWidgets('meals view shows food-scoped insight cards',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MealsHistoryView(
            weekDays: week(),
            goalKcal: 2000,
            macros: const {},
            insights: [nudge(), link()],
            onDayTap: (_) {},
          ),
        ),
      ),
    ));

    expect(find.text('little insights'), findsOneWidget);
    expect(find.text('plenty of room left'), findsOneWidget);
    expect(find.text('salty day today'), findsOneWidget);
    // Water-only insights are not passed in -> not shown.
    expect(find.text('morning drinker'), findsNothing);
  });

  testWidgets('meals view shows cozy empty state without insights',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MealsHistoryView(
            weekDays: week(),
            goalKcal: 2000,
            macros: const {},
            onDayTap: (_) {},
          ),
        ),
      ),
    ));

    expect(
      find.text('Log a few more days and I will start noticing things!'),
      findsOneWidget,
    );
    // Existing layout intact: stat squares + status lines still there.
    expect(find.text('Week Avg'), findsOneWidget);
    expect(find.text('Plenty of goal left — eat well!'), findsOneWidget);
  });

  testWidgets('water view shows water-scoped insight cards', (tester) async {
    final days = [
      for (final e in week())
        WaterDay(date: e.date, total: 2200, label: e.label),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WaterHistoryView(
            days: days,
            goalMl: 2000,
            view: HistoryChartView.week,
            hourToday: List<int>.filled(24, 0),
            hourAvg: List<double>.filled(24, 0),
            streakDays: 4,
            heartsLeft: 3,
            insights: [waterPattern(), link()],
            onViewChange: (_) {},
            onDayTap: (_) {},
          ),
        ),
      ),
    ));

    expect(find.text('little insights'), findsOneWidget);
    expect(find.text('morning drinker'), findsOneWidget);
    expect(find.text('salty day today'), findsOneWidget);
    // Existing water layout intact.
    expect(find.text('Streak'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
  });

  testWidgets('meals view shows coach recap section when AI is on',
      (tester) async {
    final recap = CoachRecapData(
      weekKey: '2026-10-26',
      tips: const [
        WeeklyTip(title: 'salty days', body: 'Add a glass of water on Thu.'),
        WeeklyTip(title: 'steady week', body: 'Water goal hit 4 times.'),
      ],
      at: DateTime(2026, 10, 30, 18),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MealsHistoryView(
            weekDays: week(),
            goalKcal: 2000,
            macros: const {},
            insights: [nudge()],
            recap: recap,
            onRecapHistory: () {},
            onDayTap: (_) {},
          ),
        ),
      ),
    ));

    expect(find.text('coach recap · week of Oct 26'), findsOneWidget);
    expect(find.text('salty days'), findsOneWidget);
    expect(find.text('Add a glass of water on Thu.'), findsOneWidget);
    expect(find.text('steady week'), findsOneWidget);
    // Rule-based insights still render below the recap.
    expect(find.text('plenty of room left'), findsOneWidget);
    // History affordance present.
    expect(find.byTooltip('past recaps'), findsOneWidget);
  });

  testWidgets('meals view hides recap section when null (AI off)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MealsHistoryView(
            weekDays: week(),
            goalKcal: 2000,
            macros: const {},
            onDayTap: (_) {},
          ),
        ),
      ),
    ));

    expect(find.textContaining('coach recap'), findsNothing);
    expect(find.byTooltip('past recaps'), findsNothing);
  });

  testWidgets('pickInsights rotates deterministically by day', (tester) async {
    final insights = [nudge(), link(), waterPattern()];
    final a = pickInsights(insights, 2, DateTime(2026, 10, 30));
    final b = pickInsights(insights, 2, DateTime(2026, 10, 30));
    final c = pickInsights(insights, 2, DateTime(2026, 10, 31));
    expect(a.length, 2);
    expect(a.map((i) => i.id), b.map((i) => i.id)); // same day -> same pick
    expect(a.map((i) => i.id).join(), isNot(c.map((i) => i.id).join()));
    // Never exceeds max, keeps all insights valid.
    expect(c.every(insights.contains), isTrue);
  });
}
