/// Which face Lil Drop is making, decided by simple cozy rules.
///
/// Pure logic only — no AI, no clocks in the background. Recomputed
/// whenever the dashboard rebuilds or water is logged (LIL-14).
/// Expressions in use: idle, worried, angry, excited, loved, sleeping.
/// (sad exists as art but is reserved for the later smart system.)
enum MascotExpression { idle, worried, angry, excited, loved, sleeping }

/// Rule machine, checked top-down (first match wins):
///
/// 1. sleeping — during the sleep window (wraps midnight, 11pm-7am)
/// 2. loved    — today's total >= 80% of the goal
/// 3. excited  — total >= 60% of the goal (progress beats pressure:
///               hitting 60% at 9pm still means excited, never angry)
/// 4. angry    — past [angryHour] while still below 60%
/// 5. worried  — behind pace for the time of day
/// 6. idle     — otherwise (a fresh morning, or comfortably on pace)
///
/// "Pace" is proportional: expected fraction of the goal equals the
/// fraction of the awake day elapsed (wake 7am -> sleep 11pm by default),
/// so worried adapts to any hour without magic checkpoint times.
MascotExpression mascotExpression({
  required DateTime now,
  required int totalMl,
  required int goalMl,
  int wakeHour = 7,
  int sleepHour = 23,
  int angryHour = 20,
}) {
  // Sleep window wraps midnight (23 -> 7).
  if (now.hour >= sleepHour || now.hour < wakeHour) {
    return MascotExpression.sleeping;
  }
  if (goalMl <= 0) return MascotExpression.idle;

  // Integer cross-multiplication so 60% / 80% boundaries are exact.
  if (totalMl * 10 >= goalMl * 8) return MascotExpression.loved;
  if (totalMl * 10 >= goalMl * 6) return MascotExpression.excited;

  final wake = DateTime(now.year, now.month, now.day, wakeHour);
  final dayMinutes = (sleepHour - wakeHour) * 60;
  final elapsed = now.difference(wake).inMinutes.clamp(0, dayMinutes);
  // Behind pace: total/goal < elapsed/dayMinutes (exact integer compare).
  final behindPace = totalMl * dayMinutes < goalMl * elapsed;

  if (now.hour >= angryHour) return MascotExpression.angry;
  if (behindPace) return MascotExpression.worried;
  return MascotExpression.idle;
}
