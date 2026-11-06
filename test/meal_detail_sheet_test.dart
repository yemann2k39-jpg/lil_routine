import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lil_routine/core/data/models.dart';
import 'package:lil_routine/features/food/meal_detail_sheet.dart';

typedef SaveAdapter = Future<void> Function({
  required String name,
  required MealType mealType,
  required double kcal,
  required double protein,
  required double carbs,
  required double fat,
  required double fiber,
  required double sugar,
  required double sodium,
  required double portion,
});

SaveAdapter noopSave = ({
  required name,
  required mealType,
  required kcal,
  required protein,
  required carbs,
  required fat,
  required fiber,
  required sugar,
  required sodium,
  required portion,
}) async {};

void main() {
  Entry entry({
    double fiber = 4,
    double sugar = 12,
    double sodium = 320,
    double portion = 1,
    String name = 'chicken rice',
    MealType mealType = MealType.lunch,
    double kcal = 550,
  }) =>
      Entry(
        id: 7,
        type: EntryType.food,
        name: name,
        mealType: mealType,
        kcal: kcal,
        protein: 30,
        carbs: 60,
        fat: 15,
        fiber: fiber,
        sugar: sugar,
        sodium: sodium,
        portion: portion,
        createdAt: DateTime(2026, 10, 30, 12, 45),
        date: '2026-10-30',
      );

  Future<void> pumpSheet(
    WidgetTester tester,
    Entry e, {
    required SaveAdapter onSave,
    required Future<void> Function() onDelete,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MealDetailSheet(entry: e, onSave: onSave, onDelete: onDelete),
      ),
    ));
    await tester.pump();
  }

  testWidgets('details view shows name, time, kcal x portion and macros',
      (tester) async {
    await pumpSheet(tester, entry(portion: 1.5),
        onSave: noopSave, onDelete: () async {});

    expect(find.text('chicken rice'), findsOneWidget);
    expect(find.text('lunch · 12:45'), findsOneWidget);
    expect(find.text('825 kcal logged (550 × 1.5 portion)'),
        findsOneWidget);
    expect(find.text('protein'), findsOneWidget);
    expect(find.text('30 g'), findsOneWidget);
    expect(find.text('fiber'), findsOneWidget);
    expect(find.text('4 g'), findsOneWidget);
    expect(find.text('sugar'), findsOneWidget);
    expect(find.text('12 g'), findsOneWidget);
    expect(find.text('sodium'), findsOneWidget);
    expect(find.text('320 mg'), findsOneWidget);
    expect(find.text('EDIT'), findsOneWidget);
    expect(find.text('DELETE'), findsOneWidget);
  });

  testWidgets('edit opens the prefilled form; saving fires with new values',
      (tester) async {
    Map<String, Object>? saved;
    await pumpSheet(
      tester,
      entry(),
      onSave: ({
        required name,
        required mealType,
        required kcal,
        required protein,
        required carbs,
        required fat,
        required fiber,
        required sugar,
        required sodium,
        required portion,
      }) async {
        saved = {
          'name': name,
          'kcal': kcal,
          'sugar': sugar,
          'portion': portion,
        };
      },
      onDelete: () async {},
    );
    await tester.tap(find.text('EDIT'));
    await tester.pump();

    // Form prefilled from the entry.
    expect(find.text('SAVE MEAL'), findsOneWidget);
    expect(find.text('chicken rice'), findsOneWidget);
    final nameField = tester
        .widget<TextField>(find.widgetWithText(TextField, 'what did you eat?'));
    expect(nameField.controller!.text, 'chicken rice');
    final kcalField = tester
        .widget<TextField>(find.widgetWithText(TextField, 'calories (kcal)'));
    expect(kcalField.controller!.text, '550');

    // Change calories and portion, save.
    await tester.enterText(
        find.widgetWithText(TextField, 'calories (kcal)'), '600');
    await tester.tap(find.text('1.5x'));
    await tester.pump();
    expect(find.text('logs as: 900 kcal'), findsOneWidget);
    await tester.tap(find.text('SAVE MEAL'));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!['name'], 'chicken rice');
    expect(saved!['kcal'], 600);
    expect(saved!['portion'], 1.5);
    expect(saved!['sugar'], 12);
  });

  testWidgets('delete fires the delete callback', (tester) async {
    var deleted = false;
    await pumpSheet(tester, entry(),
        onSave: noopSave, onDelete: () async => deleted = true);

    await tester.tap(find.text('DELETE'));
    await tester.pump();
    expect(deleted, true);
  });
}
