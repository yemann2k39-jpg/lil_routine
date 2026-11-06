import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lil_routine/core/data/models.dart';
import 'package:lil_routine/core/widgets/pixel_widgets.dart';
import 'package:lil_routine/features/food/calorie_ring.dart';
import 'package:lil_routine/features/food/food_history_screen.dart';
import 'package:lil_routine/features/food/log_food_sheet.dart';
import 'package:lil_routine/features/home/home_screen.dart';
import 'package:lil_routine/features/settings/settings_screen.dart';
import 'package:lil_routine/features/water/water_history_screen.dart';
import 'package:lil_routine/features/water/water_ring.dart';
import 'package:lil_routine/features/mascot/animated_mascot.dart';
import 'package:lil_routine/features/mascot/mascot_expression.dart';

void main() {
  /// Water page test pump: Scaffold body is bounded, matching the app.
  Future<void> pumpWaterPage(
    WidgetTester tester, {
    required int waterTotalMl,
    required int goalMl,
    required List<DrinkSlot> slots,
    required bool canUndo,
    List<Entry> drinkEntries = const [],
    ValueChanged<Entry>? onDeleteDrink,
    bool showUndoChip = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaterPageView(
            userName: 'Niko',
            waterTotalMl: waterTotalMl,
            goalMl: goalMl,
            slots: slots,
            maxSlots: 4,
            canUndo: canUndo,
            drinkEntries: drinkEntries,
            onDeleteDrink: onDeleteDrink,
            showUndoChip: showUndoChip,
            onLogSlot: (_) {},
            onAddSlot: () {},
            onRemoveSlot: (_) {},
            onUndo: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A water entry logged at a fixed time today's-page tests can assert.
  Entry waterEntry({int ml = 250, required int hour, int minute = 0}) =>
      Entry(
        type: EntryType.water,
        amountMl: ml,
        createdAt: DateTime(2026, 10, 30, hour, minute),
        date: '2026-10-30',
      );

  testWidgets('water page renders greeting, ring, stats and cup slots',
      (WidgetTester tester) async {
    await pumpWaterPage(
      tester,
      waterTotalMl: 1250,
      goalMl: 3000,
      canUndo: true,
      showUndoChip: true, // retired chip still renders when flagged on
      slots: const [
        DrinkSlot(name: 'glass', ml: 250),
        DrinkSlot(name: 'bottle', ml: 500),
      ],
    );
    // Greeting with the user's name
    expect(find.textContaining('Niko'), findsOneWidget);
    // Ring with mascot inside (ring itself, stats below).
    // The mascot placeholder label depends on the machine time (mood
    // engine), so only assert the animated mascot widget is present.
    expect(find.byType(WaterRing), findsOneWidget);
    expect(find.byType(AnimatedMascot), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('1250 / 3000 ml'), findsOneWidget);
    expect(find.text('1750 ml to go'), findsOneWidget);
    // Cup slots: both cups + the add square (capitalized labels)
    expect(find.text('Glass'), findsOneWidget);
    expect(find.text('Bottle'), findsOneWidget);
    expect(find.text('Add cup'), findsOneWidget);
    // Retired-but-flagged undo chip
    expect(find.text('Undo last'), findsOneWidget);
    // Hint is 'Hold to remove' only — no '+ adds a cup' tail
    expect(find.text('Hold to remove'), findsOneWidget);
    expect(find.textContaining('adds a cup'), findsNothing);
    // No goal edit bar
    expect(find.text('goal 3000 ml · glass 250 ml'), findsNothing);
    expect(find.textContaining('glass 250 ml ·'), findsNothing);
  });

  testWidgets('water page shows empty drinks state and hides undo by default',
      (WidgetTester tester) async {
    await pumpWaterPage(
      tester,
      waterTotalMl: 0,
      goalMl: 3000,
      canUndo: false,
      slots: const [DrinkSlot(name: 'glass', ml: 250)],
    );

    expect(find.text("today's drinks"), findsOneWidget);
    expect(find.text('nothing logged yet — tap a cup above!'),
        findsOneWidget);
    // Retired chip stays off unless explicitly flagged on.
    expect(find.text('Undo last'), findsNothing);
  });

  testWidgets("water page lists today's drinks newest first with delete",
      (WidgetTester tester) async {
    // The view is pure: it renders entries in the given order. Sorting
    // (newest first) happens in HomeScreen._reload, so feed it sorted.
    final drinks = [
      waterEntry(ml: 300, hour: 20, minute: 45), // newest
      waterEntry(ml: 500, hour: 14, minute: 5),
      waterEntry(ml: 250, hour: 9, minute: 15), // oldest
    ];
    Entry? deleted;
    await pumpWaterPage(
      tester,
      waterTotalMl: 1050,
      goalMl: 3000,
      canUndo: true,
      slots: const [],
      drinkEntries: drinks,
      onDeleteDrink: (e) => deleted = e,
    );

    expect(find.text('250 ml'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    expect(find.text('300 ml'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
    expect(find.text('14:05'), findsOneWidget);
    expect(find.text('20:45'), findsOneWidget);

    // Newest first: the 20:45 (300 ml) card sits above the 09:15 (250 ml).
    // Scroll the newest card's delete button into view first (timed
    // pump — the mascot bob means the page never settles).
    await tester.ensureVisible(find.byIcon(Icons.delete_outline).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    expect(deleted?.amountMl, 300);
    expect(
      tester.getTopLeft(find.text('300 ml')).dy,
      lessThan(tester.getTopLeft(find.text('250 ml')).dy),
    );
  });

  testWidgets('water page hides add square at slot limit',
      (WidgetTester tester) async {
    await pumpWaterPage(
      tester,
      waterTotalMl: 0,
      goalMl: 3000,
      canUndo: false,
      slots: const [
        DrinkSlot(name: 'a', ml: 100),
        DrinkSlot(name: 'b', ml: 200),
        DrinkSlot(name: 'c', ml: 300),
        DrinkSlot(name: 'd', ml: 400),
      ],
    );

    expect(find.text('Add cup'), findsNothing);
    expect(find.text('D'), findsOneWidget);
  });

  testWidgets('water page with zero cups shows only the centered plus',
      (WidgetTester tester) async {
    await pumpWaterPage(
      tester,
      waterTotalMl: 0,
      goalMl: 3000,
      canUndo: false,
      slots: const [],
    );

    // No cup squares, just the add square alone (centered by the row).
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Add cup'), findsOneWidget);
    expect(find.text('Glass'), findsNothing);
  });

  testWidgets('water page shows goal reached when total meets goal',
      (WidgetTester tester) async {
    await pumpWaterPage(
      tester,
      waterTotalMl: 3000,
      goalMl: 3000,
      canUndo: false,
      slots: const [DrinkSlot(name: 'glass', ml: 250)],
    );

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Daily goal reached!'), findsOneWidget);
    expect(find.text('0 ml to go'), findsNothing);
  });

  Entry foodEntry(
          {String name = 'Nasi goreng',
          double kcal = 700,
          double portion = 1.5}) =>
      Entry(
        type: EntryType.food,
        name: name,
        mealType: MealType.lunch,
        kcal: kcal,
        portion: portion,
        createdAt: DateTime(2026, 10, 30, 13, 5),
        date: '2026-10-30',
      );

  Future<void> pumpFood(WidgetTester tester,
      {List<Entry> entries = const []}) async {
    // Scaffold body is bounded, matching the app (same as pumpWaterPage).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodPageView(
            kcalTotal: 1250,
            kcalGoal: 2000,
            onLogFood: () {},
            onAiLogFood: () {},
            onMealTap: (_) {},
            foodEntries: entries,
            onDeleteFood: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'water dashboard: stat squares, week chart, toggle, hit line',
      (WidgetTester tester) async {
    WaterDay? tapped;
    var view = HistoryChartView.week;
    final days = List<WaterDay>.generate(7, (i) {
      final daysAgo = 6 - i;
      return WaterDay(
        date: '2026-10-${(24 + i).toString().padLeft(2, '0')}',
        total: daysAgo == 0 ? 1500 : (i * 200),
        label: daysAgo == 0 ? 'today' : 'd$daysAgo',
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => WaterHistoryView(
                days: days,
                goalMl: 2000,
                view: view,
                hourToday: const [
                  0, 0, 0, 0, 0, 0, 0, 250, 0, 0, 0, 0,
                  300, 0, 0, 0, 0, 0, 500, 0, 0, 0, 0, 0,
                ],
                hourAvg: const [
                  0, 0, 0, 0, 0, 0, 0, 50, 0, 0, 0, 0,
                  80, 0, 0, 0, 0, 0, 120, 0, 0, 0, 0, 0,
                ],
                streakDays: 3,
                heartsLeft: 2,
                onViewChange: (v) => setState(() => view = v),
                onDayTap: (d) => tapped = d,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Stat squares: Total / Daily Avg / Streak (hearts in streak square)
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('4,500'), findsOneWidget);
    expect(find.text('ml'), findsOneWidget);
    expect(find.text('Daily Avg'), findsOneWidget);
    expect(find.text('643'), findsOneWidget);
    expect(find.text('ml/day'), findsOneWidget);
    expect(find.text('Streak'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('days'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNWidgets(2));
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    // Week chart: ml label on each logged bar, none on empty days
    expect(find.text('1,500'), findsOneWidget);
    expect(find.text('600'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    // Goal line carries its value
    expect(find.text('Goal - 2,000 ml'), findsOneWidget);

    // Toggle, hint and goal-hit line
    expect(find.text('7 Days'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Tap a day to view drink history'), findsOneWidget);
    expect(find.text("You've hit your daily goal on 0 out of 7 days."),
        findsOneWidget);
    expect(find.text('Today is well on track!'), findsOneWidget);

    // Tap a day bar -> day callback fires
    await tester.tap(find.text('600'));
    expect(tapped, isNotNull);
    expect(tapped!.total, 600);

    // Switch to the Daily pattern chart (line chart)
    await tester.tap(find.text('Daily'));
    await tester.pump();
    expect(view, HistoryChartView.daily);
    expect(find.text('Sky = Today · Peach = Week Avg'), findsOneWidget);
    expect(find.text('Tap a day to view drink history'), findsNothing);
    expect(find.text('12p'), findsOneWidget);
    expect(find.text('6p'), findsOneWidget);
    // The pattern lines are painted by a CustomPainter
    expect(find.byType(CustomPaint), findsWidgets);
    // Week chart is gone
    expect(find.text('1,500'), findsNothing);
  });

  testWidgets(
      'meals dashboard: squares, kcal page, swipe left to macro page',
      (WidgetTester tester) async {
    // Week: 1500, 2500 (over), 0, 2100 (over), 2000 (at budget), 900,
    // 1250 (today). Sum 10250 -> week avg 1464.28 -> 1,464.
    MealDay day(int daysAgo, double total, {bool today = false}) {
      final date = DateTime(2026, 10, 30).subtract(Duration(days: daysAgo));
      return MealDay(
        date: date
            .toIso8601String()
            .substring(0, 10),
        total: total,
        label: today ? 'Today' : 'd$daysAgo',
      );
    }

    final weekDays = [
      day(6, 1500),
      day(5, 2500),
      day(4, 0),
      day(3, 2100),
      day(2, 2000),
      day(1, 900),
      day(0, 1250, today: true),
    ];

    // Two days carry macros; the rest count as zero in the averages:
    // protein (60+80)/7=20, fat (50+60)/7=15.7->16, carbs (150+200)/7=50.
    final macros = <String, MacroTotals>{
      weekDays[0].date: const MacroTotals(
          protein: 60, carbs: 150, fat: 50),
      weekDays[1].date: const MacroTotals(
          protein: 80, carbs: 200, fat: 60),
    };

    MealDay? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MealsHistoryView(
              weekDays: weekDays,
              goalKcal: 2000,
              macros: macros,
              onDayTap: (d) => tapped = d,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Row 1: Week Avg + Week Left (sum 10,250 of 14,000 -> 3,750 left).
    expect(find.text('Week Avg'), findsOneWidget);
    expect(find.text('1,464'), findsOneWidget); // kcal/day
    expect(find.text('Week Left'), findsOneWidget);
    expect(find.text('3,750'), findsOneWidget);
    expect(find.text('kcal left'), findsOneWidget);
    // Row 2: avg protein/fat/carbs across the 7 shown days.
    expect(find.text('Protein'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('Fat'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('Carbs'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('g/day'), findsNWidgets(3));
    // Page 1 is the classic kcal chart (no Month/7 Days toggle anymore).
    expect(find.text('Month'), findsNothing);
    expect(find.text('7 Days'), findsNothing);
    expect(find.text('Goal - 2,000 kcal'), findsOneWidget);
    expect(find.text('1,250'), findsOneWidget); // inside today's bar
    // Macro page is not built until swiped to.
    expect(find.text('60g'), findsNothing);
    expect(find.text('protein'), findsNothing);
    // Goal status lines
    expect(find.text('You stayed under goal on 5 of 7 days.'),
        findsOneWidget);
    expect(find.text('Plenty of goal left — eat well!'), findsOneWidget);
    expect(
        find.text('Tap a day to view meal history · swipe left for macros'),
        findsOneWidget);

    // Tap a day bar -> day callback fires (2500 kcal over-goal day)
    await tester.tap(find.text('2,500'));
    expect(tapped, isNotNull);
    expect(tapped!.total, 2500);

    // Swipe left -> macro page: legend + grams inside colored segments
    // (day[0]: P60 C150 F50, day[1]: P80 C200 F60).
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 400);
    await tester.pumpAndSettle();
    expect(find.text('protein'), findsOneWidget); // legend chip
    expect(find.text('carbs'), findsOneWidget);
    expect(find.text('fat'), findsOneWidget);
    expect(find.text('60g'), findsNWidgets(2)); // P on day6, F on day5
    expect(find.text('150g'), findsOneWidget);
    expect(find.text('50g'), findsOneWidget);
    expect(find.text('80g'), findsOneWidget);
    expect(find.text('200g'), findsOneWidget);
    // Day tap still works on the macro page.
    tapped = null;
    await tester.tap(find.text('200g'));
    expect(tapped, isNotNull);
    expect(tapped!.total, 2500);
  });

  test('mostLoggedMeal: counts, ties, and empty input', () {
    Entry food(MealType t) => Entry(
          type: EntryType.food,
          name: 'x',
          mealType: t,
          kcal: 100,
          portion: 1,
          createdAt: DateTime(2026, 10, 30, 12),
          date: '2026-10-30',
        );

    expect(mostLoggedMeal(const []), isNull);
    expect(mostLoggedMeal([food(MealType.snack)]), MealType.snack);
    expect(
      mostLoggedMeal(
          [food(MealType.lunch), food(MealType.lunch), food(MealType.dinner)]),
      MealType.lunch,
    );
    // Tie -> first in enum order wins (breakfast before dinner).
    expect(
      mostLoggedMeal([food(MealType.dinner), food(MealType.breakfast)]),
      MealType.breakfast,
    );
  });

  testWidgets('settings: reminder toggle fires callback, preview flips',
      (WidgetTester tester) async {
    var enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => SettingsView(
                reminderEnabled: enabled,
                reminderMinutes: 60,
                onToggleReminders: (v) => setState(() => enabled = v),
                onMinutesChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Water Reminders'), findsOneWidget);
    expect(find.text('Reminders are off'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(enabled, true);
    expect(find.text('A cozy nudge every 60 minutes'), findsOneWidget);
  });

  testWidgets('settings: quick chip + typed minutes fire callback',
      (WidgetTester tester) async {
    int? minutes;
    int tests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsView(
              reminderEnabled: false,
              reminderMinutes: 60,
              onToggleReminders: (_) {},
              onMinutesChanged: (m) => minutes = m,
              onTestReminder: () => tests++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Quick option chip applies instantly and shows the saved state
    await tester.tap(find.text('15 Min'));
    await tester.pump();
    expect(minutes, 15);
    expect(find.text('Saved ✓'), findsOneWidget);

    // Typed value commits via the Save button
    minutes = null;
    final minutesCard = find.widgetWithText(PixelCard, 'Every (minutes)');
    await tester.enterText(
        find.widgetWithText(TextField, 'Minutes between reminders'), '45');
    await tester.tap(find.descendant(of: minutesCard, matching: find.text('SAVE')));
    await tester.pump();
    expect(minutes, 45);
    expect(find.text('Saved ✓'), findsOneWidget);

    // Invalid input shows the error, no callback, no saved state
    minutes = null;
    await tester.enterText(
        find.widgetWithText(TextField, 'Minutes between reminders'), 'abc');
    await tester.tap(find.descendant(of: minutesCard, matching: find.text('SAVE')));
    await tester.pump();
    expect(minutes, isNull);
    expect(find.text('Enter 1 - 720 minutes'), findsOneWidget);
    expect(find.text('Saved ✓'), findsNothing);

    // Test-now button fires its callback
    await tester.tap(find.text('Test now'));
    await tester.pump();
    expect(tests, 1);

    // Singular wording for 1-minute intervals
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsView(
              reminderEnabled: true,
              reminderMinutes: 1,
              onToggleReminders: (_) {},
              onMinutesChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('A cozy nudge every 1 minute'), findsOneWidget);
  });

  group('computeStreakAndHearts', () {
    // 2026-11-01 is a Sunday; the week is Mon 2026-11-02 .. Sun 2026-11-08.
    // Goal 3000 -> the 80% threshold is 2400.
    const goal = 3000;
    final base = {
      '2026-11-01': 2500,
      '2026-11-02': 2500,
      '2026-11-03': 2500,
      '2026-11-04': 2500,
      '2026-11-05': 2500,
      '2026-11-06': 2500,
      '2026-11-07': 2500,
      '2026-11-08': 2500, // today, already over the threshold
    };

    test('good week: full streak and full hearts', () {
      final r = computeStreakAndHearts(
        totalsByDate: base,
        firstDateKey: '2026-11-01',
        todayKey: '2026-11-08',
        goalMl: goal,
      );
      expect(r.days, 8);
      expect(r.heartsLeft, 3);
    });

    test('two misses cost two hearts but keep the streak', () {
      final totals = Map<String, int>.from(base)
        ..['2026-11-04'] = 1000
        ..['2026-11-05'] = 500;
      final r = computeStreakAndHearts(
        totalsByDate: totals,
        firstDateKey: '2026-11-01',
        todayKey: '2026-11-08',
        goalMl: goal,
      );
      expect(r.days, 6); // 6 good days; misses never count as streak days
      expect(r.heartsLeft, 1);
    });

    test('third miss burns the last heart and resets the streak', () {
      final totals = Map<String, int>.from(base)
        ..['2026-11-02'] = 1000
        ..['2026-11-03'] = 500
        ..['2026-11-04'] = 2000; // below 2400 -> third miss of the week
      final r = computeStreakAndHearts(
        totalsByDate: totals,
        firstDateKey: '2026-11-01',
        todayKey: '2026-11-08',
        goalMl: goal,
      );
      // Good days after the reset: 11-05..11-08 -> streak rebuilds to 4.
      expect(r.days, 4);
      expect(r.heartsLeft, 0);
    });

    test('today is pending: below threshold costs nothing', () {
      final totals = Map<String, int>.from(base)
        ..['2026-11-08'] = 500; // today below the threshold
      final r = computeStreakAndHearts(
        totalsByDate: totals,
        firstDateKey: '2026-11-01',
        todayKey: '2026-11-08',
        goalMl: goal,
      );
      expect(r.days, 7); // counts through yesterday only
      expect(r.heartsLeft, 3); // today never costs a heart
    });

    test('no history at all', () {
      final r = computeStreakAndHearts(
        totalsByDate: const {},
        firstDateKey: '2026-11-08',
        todayKey: '2026-11-08',
        goalMl: goal,
      );
      expect(r.days, 0);
      expect(r.heartsLeft, 3);
    });
  });

  testWidgets('meals page shows calorie ring, log button and meal list',
      (WidgetTester tester) async {
    await pumpFood(tester, entries: [foodEntry()]);

    // Greeting with the user's name (machine-time independent check)
    expect(find.textContaining('Niko'), findsOneWidget);
    expect(find.byType(CalorieRing), findsOneWidget);
    expect(find.byType(AnimatedMascot), findsOneWidget);
    expect(find.text('63%'), findsOneWidget);
    expect(find.text('1250 / 2000 kcal'), findsOneWidget);
    expect(find.text('750 kcal left'), findsOneWidget);
    expect(find.text('LOG FOOD'), findsOneWidget);
    expect(find.text('today\'s meals'), findsOneWidget);
    expect(find.text('Nasi goreng'), findsOneWidget);
    expect(find.text('lunch · 1050 kcal (1.5x)'), findsOneWidget);
  });

  testWidgets('meals page shows empty state without entries',
      (WidgetTester tester) async {
    await pumpFood(tester);

    expect(find.text('nothing logged yet — tap log food above!'),
        findsOneWidget);
  });

  testWidgets('calorie ring shows over-budget state',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodPageView(
            kcalTotal: 2300,
            kcalGoal: 2000,
            onLogFood: () {},
            onAiLogFood: () {},
            onMealTap: (_) {},
            foodEntries: const [],
            onDeleteFood: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('2300 / 2000 kcal'), findsOneWidget);
    expect(find.text('+300 kcal over'), findsOneWidget);
    expect(find.text('750 kcal left'), findsNothing);
  });

  testWidgets('food log form: portion multiplier updates live and save fires',
      (WidgetTester tester) async {
    ({String name, MealType mealType, double kcal, double portion})? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FoodLogForm(
              defaultMealType: MealType.dinner,
              onSave: ({required name, required mealType, required kcal,
                  required protein, required carbs, required fat,
                  required fiber, required sugar, required sodium,
                  required portion}) {
                saved = (
                  name: name,
                  mealType: mealType,
                  kcal: kcal,
                  portion: portion,
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('dinner'), findsOneWidget); // default meal selected
    expect(find.text('logs as: 0 kcal'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'what did you eat?'), 'Nasi goreng');
    await tester.enterText(
        find.widgetWithText(TextField, 'calories (kcal)'), '700');
    await tester.pump();

    // Select 1.5x portion -> live preview updates
    await tester.tap(find.text('1.5x'));
    await tester.pump();
    expect(find.text('logs as: 1050 kcal'), findsOneWidget);

    await tester.tap(find.text('SAVE MEAL'));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.name, 'Nasi goreng');
    expect(saved!.kcal, 700);
    expect(saved!.portion, 1.5);
  });

  testWidgets('food log form blocks save without name/kcal',
      (WidgetTester tester) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FoodLogForm(
              defaultMealType: MealType.breakfast,
              onSave: ({required name, required mealType, required kcal,
                  required protein, required carbs, required fat,
                  required fiber, required sugar, required sodium,
                  required portion}) {
                saved = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('SAVE MEAL'));
    await tester.pump();

    expect(saved, false);
    expect(find.text('food name and calories are needed'), findsOneWidget);
  });

  test('guessMealType maps hours to meals', () {
    DateTime mk(int h) => DateTime(2026, 10, 30, h, 0);
    expect(guessMealType(mk(7)), MealType.breakfast);
    expect(guessMealType(mk(10)), MealType.breakfast);
    expect(guessMealType(mk(11)), MealType.lunch);
    expect(guessMealType(mk(14)), MealType.lunch);
    expect(guessMealType(mk(15)), MealType.dinner);
    expect(guessMealType(mk(20)), MealType.dinner);
    expect(guessMealType(mk(21)), MealType.snack);
    expect(guessMealType(mk(2)), MealType.snack);
  });

  testWidgets('animated mascot squish-fades when the expression changes',
      (WidgetTester tester) async {
    MascotExpression expression = MascotExpression.idle;

    Future<void> pumpMascot() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnimatedMascot(
                size: 80,
                expression: expression,
                moodBuilder: (context, e) =>
                    MascotPlaceholder(expression: e, size: 80),
              ),
            ),
          ),
        ),
      );
    }

    await pumpMascot();
    await tester.pump();
    expect(find.text('Idle'), findsOneWidget);

    // Swap idle -> excited: mid-transition BOTH visuals exist (old fades
    // out in the Stack while the new one squishes in).
    expression = MascotExpression.excited;
    await pumpMascot();
    await tester.pump();
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Excited'), findsOneWidget);

    // Transition (340ms) completes cleanly, old visual fully gone.
    // Timed pumps, not pumpAndSettle: the breathing-bob controller runs
    // forever by design, so there is never a "settled" moment.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Excited'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
  });
}
