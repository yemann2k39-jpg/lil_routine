import 'package:flutter_test/flutter_test.dart';
import 'package:lil_routine/features/mascot/mascot_expression.dart';

void main() {
  group('mascotExpression', () {
    // 7am-11pm awake window = 960 minutes. Goal 3000 ml, so 60% = 1800,
    // 80% = 2400, and pace at hour H is (minutes since 7am)/960 of goal.
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 11, 3, hour, minute);

    test('sleeping: late night and early morning, even with a full goal', () {
      expect(
        mascotExpression(now: at(23), totalMl: 3000, goalMl: 3000),
        MascotExpression.sleeping,
      );
      expect(
        mascotExpression(now: at(2, 30), totalMl: 3000, goalMl: 3000),
        MascotExpression.sleeping,
      );
      expect(
        mascotExpression(now: at(6, 59), totalMl: 0, goalMl: 3000),
        MascotExpression.sleeping,
      );
    });

    test('idle: fresh morning, tiny sip is still on pace', () {
      // 8am = 60/960 of the day = 6.25% expected; 200 ml = 6.7% is on pace.
      expect(
        mascotExpression(now: at(8), totalMl: 200, goalMl: 3000),
        MascotExpression.idle,
      );
    });

    test('worried: behind pace midday', () {
      // Noon = 300/960 = 31.25% expected; 300 ml = 10% is behind.
      expect(
        mascotExpression(now: at(12), totalMl: 300, goalMl: 3000),
        MascotExpression.worried,
      );
    });

    test('worried/pace boundary: exactly on pace is idle, one ml less is worried',
        () {
      // 15:00 = 480/960 = 50% of the day; 50% of 3000 = 1500 ml.
      expect(
        mascotExpression(now: at(15), totalMl: 1500, goalMl: 3000),
        MascotExpression.idle,
      );
      expect(
        mascotExpression(now: at(15), totalMl: 1499, goalMl: 3000),
        MascotExpression.worried,
      );
    });

    test('angry: past angry hour while below 60%', () {
      expect(
        mascotExpression(now: at(20, 30), totalMl: 1000, goalMl: 3000),
        MascotExpression.angry,
      );
      expect(
        mascotExpression(now: at(20), totalMl: 0, goalMl: 3000),
        MascotExpression.angry,
      );
    });

    test('excited: exactly 60%, and progress beats the angry hour', () {
      expect(
        mascotExpression(now: at(12), totalMl: 1800, goalMl: 3000),
        MascotExpression.excited,
      );
      expect(
        mascotExpression(now: at(21), totalMl: 1800, goalMl: 3000),
        MascotExpression.excited,
      );
    });

    test('excited boundary: one ml below stays a pressure mood', () {
      // 17:00 = 600/960 = 62.5% of the day; 1799 ml (59.97%) is behind pace.
      expect(
        mascotExpression(now: at(17), totalMl: 1799, goalMl: 3000),
        MascotExpression.worried,
      );
      expect(
        mascotExpression(now: at(17), totalMl: 1800, goalMl: 3000),
        MascotExpression.excited,
      );
    });

    test('loved: exactly 80% and above', () {
      expect(
        mascotExpression(now: at(12), totalMl: 2400, goalMl: 3000),
        MascotExpression.loved,
      );
      expect(
        mascotExpression(now: at(20, 30), totalMl: 3000, goalMl: 3000),
        MascotExpression.loved,
      );
    });

    test('loved boundary: one ml below is excited, not loved', () {
      expect(
        mascotExpression(now: at(12), totalMl: 2399, goalMl: 3000),
        MascotExpression.excited,
      );
    });

    test('sleeping wins over loved during the sleep window', () {
      expect(
        mascotExpression(now: at(23, 15), totalMl: 3000, goalMl: 3000),
        MascotExpression.sleeping,
      );
    });

    test('angry hour before sleeping hour: 10pm below 60% is angry', () {
      expect(
        mascotExpression(now: at(22), totalMl: 500, goalMl: 3000),
        MascotExpression.angry,
      );
    });

    test('custom wake/sleep window shifts the whole schedule', () {
      // Wake 5am, sleep 9pm: 6am is awake now, day = 16h = 960 min,
      // 60 min in = 6.25% expected -> 200 ml is on pace.
      expect(
        mascotExpression(
          now: at(6),
          totalMl: 200,
          goalMl: 3000,
          wakeHour: 5,
          sleepHour: 21,
        ),
        MascotExpression.idle,
      );
      // Custom angry hour 19: at 7:30pm below 60% -> angry.
      expect(
        mascotExpression(
          now: at(19, 30),
          totalMl: 200,
          goalMl: 3000,
          wakeHour: 5,
          sleepHour: 21,
          angryHour: 19,
        ),
        MascotExpression.angry,
      );
    });

    test('zero goal never divides by zero', () {
      expect(
        mascotExpression(now: at(12), totalMl: 0, goalMl: 0),
        MascotExpression.idle,
      );
    });
  });
}
