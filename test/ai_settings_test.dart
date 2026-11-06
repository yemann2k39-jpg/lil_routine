import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lil_routine/core/ai/gemini_provider.dart';
import 'package:lil_routine/core/theme/palette.dart';
import 'package:lil_routine/core/widgets/pixel_widgets.dart';
import 'package:lil_routine/features/settings/settings_screen.dart';

/// The key field is the only TextField labelled like this (the reminders
/// card has its own minutes field).
Finder keyField() => find.byWidgetPredicate((w) =>
    w is TextField &&
    w.decoration?.labelText == 'Paste your Gemini API key');

/// The AI card (scoped: the reminders card has its own Save button).
Finder aiCard() => find.widgetWithText(
    PixelCard, 'Gemini · ${'gemini-3.1-flash-lite'.substring(7)}');

Future<void> pumpAi(WidgetTester tester,
    {bool hasKey = false,
    Future<void> Function(String)? onSave,
    Future<AiResult> Function()? onTest,
    VoidCallback? onOpenAiStudio}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SettingsView(
            reminderEnabled: false,
            reminderMinutes: 60,
            onToggleReminders: (_) {},
            onMinutesChanged: (_) {},
            aiHasKey: hasKey,
            onAiSaveKey: onSave,
            onAiTestKey: onTest,
            onOpenAiStudio: onOpenAiStudio,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('locked state: explainer, link, key field, Save',
      (tester) async {
    String? saved;
    await pumpAi(tester, onSave: (k) async => saved = k);

    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('Paste the key, then tap Save.'), findsOneWidget);
    expect(keyField(), findsOneWidget);

    // Type a key and save.
    await tester.enterText(keyField(), 'my-secret-key');
    final aiSave = find.descendant(of: aiCard(), matching: find.text('SAVE'));
    await tester.ensureVisible(aiSave);
    await tester.pump();
    await tester.tap(aiSave);
    await tester.pump();
    expect(saved, 'my-secret-key');
    // Field collapses after saving (the header prop stays 'Not set' —
    // that only changes when the parent reloads its state).
    expect(keyField(), findsNothing);
    expect(find.text('Saved in secure storage ✓'), findsOneWidget);
  });

  testWidgets('saved state: edit key reveals field again, test runs',
      (tester) async {
    var tested = false;
    await pumpAi(
      tester,
      hasKey: true,
      onTest: () async {
        tested = true;
        return const AiResult(ok: true, detail: 'OK');
      },
    );

    expect(find.text('Saved ✓'), findsOneWidget);
    expect(keyField(), findsNothing);

    await tester.ensureVisible(find.text('TEST CONNECTION'));
    await tester.pump();
    await tester.tap(find.text('TEST CONNECTION'));
    await tester.pump();
    await tester.pump();
    expect(tested, isTrue);
    expect(find.text('✓ Works — Gemini replied'), findsOneWidget);

    // Edit reveals the field again.
    await tester.ensureVisible(find.text('EDIT KEY'));
    await tester.pump();
    await tester.tap(find.text('EDIT KEY'));
    await tester.pump();
    expect(keyField(), findsOneWidget);
  });

  testWidgets('failed test shows the reason', (tester) async {
    await pumpAi(
      tester,
      hasKey: true,
      onTest: () async => const AiResult(
          ok: false, detail: 'API key rejected — double-check the pasted key.'),
    );
    await tester.ensureVisible(find.text('TEST CONNECTION'));
    await tester.pump();
    await tester.tap(find.text('TEST CONNECTION'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Did not work: API key rejected'),
        findsOneWidget);
    expect(find.text('✓ Works — Gemini replied'), findsNothing);
  });

  testWidgets('AI section renders with defaults when handlers omitted',
      (tester) async {
    await pumpAi(tester);
    expect(find.text('Not set'), findsOneWidget); // card still shows
    expect(find.text('Saved ✓'), findsNothing);
    expect(keyField(), findsOneWidget);
  });

  test('AiResult carries ok/detail', () {
    const r = AiResult(ok: true, detail: 'hi');
    expect(r.ok, isTrue);
    expect(r.detail, 'hi');
    expect(Palette.skyDeep, isNot(Palette.blushDeep)); // colors distinct
  });
}
