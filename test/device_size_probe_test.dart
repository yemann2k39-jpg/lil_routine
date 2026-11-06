import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lil_routine/features/food/calorie_ring.dart';
import 'package:lil_routine/features/home/home_screen.dart';
import 'package:lil_routine/features/mascot/animated_mascot.dart';

/// Reproduces Niko's phone: 1080x2340 @ 2.8125 dpr = 384x~832 logical.
void main() {
  testWidgets('device-size meals page renders greeting + ring', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.8125;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('LilRoutine')),
          body: FoodPageView(
            kcalTotal: 1250,
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

    expect(find.byType(CalorieRing), findsOneWidget);
    expect(find.byType(AnimatedMascot), findsOneWidget,
        reason: 'calorie mascot should render inside the ring');
    expect(find.textContaining('Niko'), findsOneWidget,
        reason: 'greeting should render');
    expect(find.text('63%'), findsOneWidget);
    debugDumpApp();
  });
}
