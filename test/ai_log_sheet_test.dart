import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lil_routine/core/ai/gemini_provider.dart';
import 'package:lil_routine/core/data/models.dart';
import 'package:lil_routine/features/food/ai_log_sheet.dart';

/// Awaitable save-callback shape (mirrors AiFoodLogSaved).
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

/// Awaitable estimator shape (mirrors the sheet's estimate param).
typedef EstimateAdapter = Future<AiEstimateResult> Function({
  String? description,
  Uint8List? image,
  String imageMimeType,
});

EstimateAdapter okEstimate() => ({
      String? description,
      Uint8List? image,
      String imageMimeType = 'image/jpeg',
    }) async =>
        const AiEstimateResult.ok(AiFoodEstimate(
          name: 'scrambled eggs',
          mealType: MealType.breakfast,
          kcal: 320,
          protein: 21,
          carbs: 4,
          fat: 24,
          fiber: 1.5,
          sugar: 2,
          sodium: 380,
          portion: 1.0,
          note: 'rough guess',
        ));

SaveAdapter noopSave = ({required name, required mealType, required kcal,
    required protein, required carbs, required fat, required fiber,
    required sugar, required sodium, required portion}) async {};

const descriptionLabel = 'describe it (e.g. "2 scrambled eggs + toast")';

Future<void> pumpSheet(
  WidgetTester tester, {
  required SaveAdapter onSaveLog,
  EstimateAdapter? estimate,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AiLogSheet(
        onPickImage: (_) async => null,
        onSaveLog: onSaveLog,
        estimate: estimate ?? okEstimate(),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('input -> estimate -> editable card prefilled', (tester) async {
    await pumpSheet(tester, onSaveLog: noopSave);

    // Empty estimate is refused.
    await tester.ensureVisible(find.text('ESTIMATE WITH AI'));
    await tester.pump();
    await tester.tap(find.text('ESTIMATE WITH AI'));
    await tester.pump();
    expect(find.text('a photo or a description is needed'), findsOneWidget);

    // Describe, estimate -> confirmation card prefilled from the answer.
    await tester.enterText(find.widgetWithText(TextField, descriptionLabel),
        'two eggs');
    await tester.tap(find.text('ESTIMATE WITH AI'));
    await tester.pump();
    await tester.pump();
    expect(find.text('gemini says · check before saving'), findsOneWidget);
    expect(find.text('note: rough guess'), findsOneWidget);
    final nameField = find.widgetWithText(TextField, 'what did you eat?');
    expect(tester.widget<TextField>(nameField).controller!.text,
        'scrambled eggs');
    final kcalField = find.widgetWithText(TextField, 'calories (kcal)');
    expect(tester.widget<TextField>(kcalField).controller!.text, '320');
    // Extra macros prefilled from the estimate (sodium in mg).
    final sodiumField = find.widgetWithText(TextField, 'sodium mg');
    expect(tester.widget<TextField>(sodiumField).controller!.text, '380');
    expect(find.text('breakfast'), findsOneWidget); // meal chip present
    expect(find.text('logs as: 320 kcal'), findsOneWidget);
  });

  testWidgets('user edits the card, save goes through manual-log path',
      (tester) async {
    Map<String, Object>? saved;
    await pumpSheet(tester, onSaveLog: ({
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
        'mealType': mealType,
        'kcal': kcal,
        'protein': protein,
        'portion': portion,
      };
    });

    await tester.enterText(
        find.widgetWithText(TextField, descriptionLabel), 'eggs');
    await tester.tap(find.text('ESTIMATE WITH AI'));
    await tester.pump();
    await tester.pump();

    // Edit kcal to 400, pick portion 1.5 -> logs 600.
    await tester.enterText(
        find.widgetWithText(TextField, 'calories (kcal)'), '400');
    await tester.tap(find.text('1.5x'));
    await tester.pump();
    expect(find.text('logs as: 600 kcal'), findsOneWidget);

    await tester.ensureVisible(find.text('SAVE MEAL'));
    await tester.pump();
    await tester.tap(find.text('SAVE MEAL'));
    await tester.pump();
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!['name'], 'scrambled eggs');
    expect(saved!['kcal'], 400);
    expect(saved!['portion'], 1.5);
    expect(saved!['mealType'], MealType.breakfast);
    expect(saved!['protein'], 21);
  });

  testWidgets('failed estimate shows the reason and stays on input',
      (tester) async {
    await pumpSheet(
      tester,
      onSaveLog: noopSave,
      estimate: ({
        String? description,
        Uint8List? image,
        String imageMimeType = 'image/jpeg',
      }) async =>
          const AiEstimateResult.error(
              'Rate limit hit — try again in a minute.'),
    );

    await tester.enterText(
        find.widgetWithText(TextField, descriptionLabel), 'eggs');
    await tester.tap(find.text('ESTIMATE WITH AI'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Rate limit hit'), findsOneWidget);
    expect(find.text('gemini says · check before saving'), findsNothing);
    // Back on input stage.
    expect(find.text('ESTIMATE WITH AI'), findsOneWidget);
  });

  testWidgets('back button returns to input keeping the description',
      (tester) async {
    await pumpSheet(tester, onSaveLog: noopSave);

    await tester.enterText(
        find.widgetWithText(TextField, descriptionLabel), 'eggs');
    await tester.tap(find.text('ESTIMATE WITH AI'));
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text('BACK'));
    await tester.pump();
    await tester.tap(find.text('BACK'));
    await tester.pump();

    expect(find.text('ESTIMATE WITH AI'), findsOneWidget);
    final desc = find.widgetWithText(TextField, descriptionLabel);
    expect(tester.widget<TextField>(desc).controller!.text, 'eggs');
  });
}
