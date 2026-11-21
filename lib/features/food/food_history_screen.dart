import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_key_store.dart';
import '../../core/data/entry_repository.dart';
import '../../core/data/food_repository.dart';
import '../../core/data/models.dart';
import '../../core/data/settings_repository.dart';
import '../../core/db/app_database.dart';
import '../../core/insights/coach_recap.dart';
import '../../core/insights/insight_engine.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../insights/insight_card.dart';
import 'meal_detail_sheet.dart';

/// One day in the meals chart.
@immutable
class MealDay {
  const MealDay({
    required this.date,
    required this.total,
    required this.label,
  });

  final String date; // yyyy-MM-dd
  final double total; // kcal (kcal * portion summed)
  final String label;
}

/// Most frequent meal type across [entries] (ties: first in enum order),
/// or null when nothing was logged.
MealType? mostLoggedMeal(Iterable<Entry> entries) {
  final counts = <MealType, int>{};
  for (final e in entries) {
    final t = e.mealType;
    if (t == null) continue;
    counts[t] = (counts[t] ?? 0) + 1;
  }
  MealType? best;
  var bestCount = 0;
  for (final t in MealType.values) {
    final c = counts[t] ?? 0;
    if (c > bestCount) {
      best = t;
      bestCount = c;
    }
  }
  return best;
}

/// Format kcal with a thousands separator and no decimals: 1765 -> 1,765.
String formatKcal(num kcal) {
  final s = kcal.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    b.write(s[i]);
    final remaining = s.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) b.write(',');
  }
  return b.toString();
}

/// Meals history dashboard. Screen owns data loading; [MealsHistoryView]
/// is pure UI (embeddable blocks — a combined dashboard can host it).
class MealsHistoryScreen extends StatefulWidget {
  const MealsHistoryScreen({super.key});

  @override
  State<MealsHistoryScreen> createState() => _MealsHistoryScreenState();
}

class _MealsHistoryScreenState extends State<MealsHistoryScreen> {
  int _goalKcal = SettingsRepository.defaultKcalGoal;
  List<MealDay> _weekDays = const [];
  Map<String, MacroTotals> _macros = const {};
  List<Insight> _insights = const [];
  CoachRecapData? _recap;
  bool _aiOn = false;
  bool _recapRunning = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final entries = EntryRepository(db);
    final settings = SettingsRepository(db);
    final now = DateTime.now();
    final todayKey = dateKey(now);
    final startKey = dateKey(now.subtract(const Duration(days: 6)));

    final totals = await entries.kcalTotalsForRange(startKey, todayKey);
    final goal = await settings.kcalGoal();
    final macros = await entries.macroTotalsForRange(startKey, todayKey);

    // Insights: deterministic rules over the same week, including the
    // water <-> food cross-domain rules.
    final foodEntries = await entries.foodEntriesBetween(startKey, todayKey);
    final waterEntries = await entries.waterEntriesBetween(startKey, todayKey);
    final waterGoal = await settings.waterGoalMl();
    final insights = InsightEngine.generate(InsightEngineInput(
      foodEntries: foodEntries,
      waterEntries: waterEntries,
      goalKcal: goal,
      goalMl: waterGoal,
      now: now,
    ))
        .where(
            (i) => i.scope == InsightScope.food || i.scope == InsightScope.both)
        .toList(growable: false);

    // Coach recap: show the cached one immediately; AI refresh happens
    // in the background below (at most once per 7 days, key required).
    final recapJson = await settings.lastCoachRecap();
    final aiOn = await AiGate(FlutterSecureAiKeyStore()).isConfigured();

    if (!mounted) return;
    final weekDays = <MealDay>[];
    for (var i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = dateKey(date);
      weekDays.add(MealDay(
        date: key,
        total: totals[key] ?? 0,
        label: i == 0
            ? 'Today'
            : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][
                date.weekday - 1],
      ));
    }

    setState(() {
      _weekDays = weekDays;
      _goalKcal = goal;
      _macros = macros;
      _insights = insights;
      _recap = recapJson == null ? null : CoachRecapData.fromJson(recapJson);
      _aiOn = aiOn;
      _loading = false;
    });

    if (aiOn && !_recapRunning) {
      _recapRunning = true;
      unawaited(_refreshRecap());
    }
  }

  /// Background recap refresh; silently keeps the cached recap on any
  /// failure (no network, bad key, AI hiccup).
  Future<void> _refreshRecap() async {
    try {
      final db = await AppDatabase.instance();
      final fresh = await CoachRecap.maybeRun(
        db: db,
        keyStore: FlutterSecureAiKeyStore(),
        now: DateTime.now(),
      );
      if (fresh != null && mounted) {
        setState(() => _recap = fresh);
      }
    } on Object {
      // Recap is a bonus — never break the dashboard over it.
    } finally {
      _recapRunning = false;
    }
  }

  /// Bottom sheet with every stored weekly recap, newest first.
  Future<void> _openRecapHistory() async {
    final db = await AppDatabase.instance();
    final history = await SettingsRepository(db).coachRecapHistory();
    final recaps = <CoachRecapData>[];
    for (final (_, json) in history) {
      final data = CoachRecapData.fromJson(json);
      if (data != null) recaps.add(data);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'past recaps',
                textAlign: TextAlign.center,
                style: AppTypography.pixelDisplay(14),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: recaps.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'no past recaps yet',
                          textAlign: TextAlign.center,
                          style: AppTypography.cozy(
                              13, color: Palette.cocoaSoft),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: recaps.length,
                        itemBuilder: (context, i) {
                          final r = recaps[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RecapSection(recap: r),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDay(MealDay day) async {
    final db = await AppDatabase.instance();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DaySheet(
        date: day.date,
        entriesRepo: EntryRepository(db),
        onChanged: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meals History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: MealsHistoryView(
                  weekDays: _weekDays,
                  goalKcal: _goalKcal,
                  macros: _macros,
                  insights: _insights,
                  recap: _aiOn ? _recap : null,
                  onDayTap: _openDay,
                  onRecapHistory: _aiOn ? _openRecapHistory : null,
                ),
              ),
            ),
    );
  }
}

/// Pure-UI meals dashboard: 2+3 stat squares, swipeable kcal/macros
/// charts, hint and goal status lines. Embeddable — no DB.
class MealsHistoryView extends StatelessWidget {
  const MealsHistoryView({
    super.key,
    required this.weekDays,
    required this.goalKcal,
    required this.macros,
    this.insights = const [],
    this.recap,
    this.onRecapHistory,
    required this.onDayTap,
  });

  final List<MealDay> weekDays; // last 7, oldest -> newest
  final Map<String, MacroTotals> macros; // date -> portion-scaled totals
  final int goalKcal;

  /// Food-scoped insights; empty by default so existing callers and
  /// tests stay untouched.
  final List<Insight> insights;

  /// Cached AI coach recap (null = no card: AI off or never ran).
  final CoachRecapData? recap;
  final VoidCallback? onRecapHistory;
  final ValueChanged<MealDay> onDayTap;

  /// Average of one macro across the 7 shown days (empty days count as
  /// 0, same semantics as the kcal average).
  double _avgMacro(double Function(MacroTotals) pick) {
    if (weekDays.isEmpty) return 0;
    final sum = weekDays.fold<double>(
      0,
      (s, d) => s + pick(macros[d.date] ?? const MacroTotals()),
    );
    return sum / weekDays.length;
  }

  @override
  Widget build(BuildContext context) {
    final weekSum = weekDays.fold<double>(0, (s, d) => s + d.total);
    final weekAvg = weekDays.isEmpty ? 0.0 : weekSum / weekDays.length;
    // Whole-week goal vs. what was actually eaten this week.
    final weekLeft = goalKcal * 7 - weekSum;
    final overWeek = weekLeft < 0;
    final overDays = weekDays.where((d) => d.total > goalKcal).length;
    final rangeLen = weekDays.length;

    final todayTotal = weekDays.isEmpty ? 0.0 : weekDays.last.total;
    final todayLine = todayTotal > goalKcal
        ? 'You are over goal today — mind the snacks!'
        : todayTotal > goalKcal * 0.8
            ? 'Close to the goal — plan the rest!'
            : 'Plenty of goal left — eat well!';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1) Row 1: Week Avg kcal · Week Left (Niko's spec).
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatSquare(
                label: 'Week Avg',
                value: formatKcal(weekAvg),
                sub: 'kcal/day',
              ),
              const SizedBox(width: 8),
              _StatSquare(
                label: 'Week Left',
                value: formatKcal(weekLeft.abs()),
                sub: overWeek ? 'kcal over' : 'kcal left',
                valueColor: overWeek ? Palette.blushDeep : Palette.peachDeep,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 2) Row 2: avg Protein · Fat · Carbs across the 7 days.
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatSquare(
                label: 'Protein',
                value: _avgMacro((m) => m.protein).round().toString(),
                sub: 'g/day',
              ),
              const SizedBox(width: 8),
              _StatSquare(
                label: 'Fat',
                value: _avgMacro((m) => m.fat).round().toString(),
                sub: 'g/day',
              ),
              const SizedBox(width: 8),
              _StatSquare(
                label: 'Carbs',
                value: _avgMacro((m) => m.carbs).round().toString(),
                sub: 'g/day',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 3) Swipeable charts: kcal (page 1) -> macros (page 2).
        PixelCard(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: _HistoryCharts(
            days: weekDays,
            goalKcal: goalKcal,
            macros: macros,
            onDayTap: onDayTap,
          ),
        ),
        const SizedBox(height: 12),
        // 4) Hint under the chart
        Center(
          child: Text(
            'Tap a day to view meal history · swipe left for macros',
            style: AppTypography.cozy(11, color: Palette.cocoaSoft),
          ),
        ),
        const SizedBox(height: 20),
        // 5) Goal status
        Center(
          child: Text(
            'You stayed under goal on ${rangeLen - overDays} of '
            '$rangeLen days.',
            textAlign: TextAlign.center,
            style: AppTypography.cozy(13, color: Palette.cocoa),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            todayLine,
            textAlign: TextAlign.center,
            style: AppTypography.cozy(12, color: Palette.cocoaSoft),
          ),
        ),
        const SizedBox(height: 20),
        // 6) Coach recap (AI, cached weekly; hidden when AI is off)
        if (recap != null) ...[
          _RecapSection(recap: recap!, onHistory: onRecapHistory),
          const SizedBox(height: 20),
        ],
        // 7) Insights section (food-scoped rules + cross-domain links)
        InsightsSection(insights: insights, max: 3, now: DateTime.now()),
      ],
    );
  }
}

/// Coach recap card: week label, tip list, optional history entry.
class _RecapSection extends StatelessWidget {
  const _RecapSection({required this.recap, this.onHistory});

  final CoachRecapData recap;
  final VoidCallback? onHistory;

  String get _weekLabel {
    if (recap.weekKey.isEmpty) return 'coach recap';
    final parts = recap.weekKey.split('-');
    final d = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return 'coach recap · week of ${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: Palette.skyDeep),
            const SizedBox(width: 6),
            Text(
              _weekLabel,
              style: AppTypography.pixelDisplay(12, color: Palette.skyDeep),
            ),
            if (onHistory != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'past recaps',
                icon: const Icon(
                  Icons.history,
                  size: 18,
                  color: Palette.cocoaSoft,
                ),
                onPressed: onHistory,
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (final tip in recap.tips) ...[
          PixelCard(
            color: Palette.skySoft,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style:
                      AppTypography.pixelDisplay(11, color: Palette.skyDeep),
                ),
                const SizedBox(height: 3),
                Text(
                  tip.body,
                  style: AppTypography.cozy(12, color: Palette.cocoa),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// One stat square: pixel label, big value, small sub line.
class _StatSquare extends StatelessWidget {
  const _StatSquare({
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor = Palette.cocoa,
  });

  final String label;
  final String value;
  final String sub;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    // Expanded so all squares in a row share the width equally.
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Palette.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.outline, width: 2),
          boxShadow: const [
            BoxShadow(
                color: Palette.shadow, offset: Offset(0, 3), blurRadius: 0),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.pixelDisplay(10, color: Palette.cocoaSoft),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.pixelDisplay(16, color: valueColor),
            ),
            const SizedBox(height: 3),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.cozy(10, color: Palette.cocoaSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// Daily kcal bar chart split into three peach macro tones (protein /
/// carbs / fat, kcal without macro data in cream). Bars over goal get a
/// blush border. In compact (month) mode bars thin out and labels show
/// only on milestones.
///
/// Each day's bar is split into three same-hue peach tones showing the
/// macro composition (protein = deep, carbs = mid, fat = light, kcal
/// without macro data = cream), so the Goal line stays a kcal line.
/// Swipeable chart pair for the last 7 days.
/// Page 1: the classic kcal bar (solid color, kcal count inside/above,
/// Goal line). Page 2 (swipe left): the same kcal-scale bars split into
/// three same-hue peach tones by macro (protein deep, carbs mid, fat
/// light, kcal without macro data in cream), grams written inside each
/// colored segment, legend naming the colors. Day taps work on both.
class _HistoryCharts extends StatefulWidget {
  const _HistoryCharts({
    required this.days,
    required this.goalKcal,
    required this.macros,
    required this.onDayTap,
  });

  final List<MealDay> days;
  final int goalKcal;
  final Map<String, MacroTotals> macros; // date -> portion-scaled totals
  final ValueChanged<MealDay> onDayTap;

  @override
  State<_HistoryCharts> createState() => _HistoryChartsState();
}

class _HistoryChartsState extends State<_HistoryCharts> {
  int _page = 0;

  static const _chartHeight = 240.0;
  static const _legendHeight = 18.0;
  static const _labelArea = 24.0;
  static const _maxBar = 130.0;

  Color _kcalBarColor(MealDay day) {
    if (day.total == 0) return Palette.creamDeep;
    if (day.total > widget.goalKcal) return Palette.blushDeep;
    if (day.total >= widget.goalKcal) return Palette.peachDeep;
    return Palette.peach;
  }

  ({double p, double c, double f, double rest}) _segments(MealDay day) {
    final m = widget.macros[day.date] ?? const MacroTotals();
    final p = m.protein * 4; // kcal from protein
    final c = m.carbs * 4; // kcal from carbs
    final f = m.fat * 9; // kcal from fat
    final rest = (day.total - p - c - f).clamp(0.0, double.infinity);
    return (p: p, c: c, f: f, rest: rest);
  }

  double get _maxScale => <double>[
        widget.goalKcal.toDouble(),
        ...widget.days.map((d) => d.total),
      ].fold<double>(1, (a, b) => a > b ? a : b);

  Widget _goalLine(double areaHeight) {
    final lineBottom =
        _labelArea + _maxBar * widget.goalKcal / _maxScale - 1;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: lineBottom,
          child: Container(
            height: 2,
            color: Palette.cocoaSoft.withValues(alpha: 0.45),
          ),
        ),
        Positioned(
          right: 0,
          bottom: lineBottom + 4,
          child: Text(
            'Goal - ${formatKcal(widget.goalKcal)} kcal',
            style: AppTypography.cozy(10, color: Palette.cocoaSoft),
          ),
        ),
      ],
    );
  }

  /// Page 1 column: classic kcal bar (old style: solid color, kcal count
  /// inside the bar when it fits, else above it).
  Widget _kcalDay(MealDay day, double areaHeight) {
    final maxScale = _maxScale;
    final barH = day.total == 0 ? 3.0 : _maxBar * day.total / maxScale;
    final labelInside = barH >= 24;
    final showKcal = day.total > 0;

    return _dayColumn(
      day,
      _chartHeight,
      Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 2,
            child: Text(
              day.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: AppTypography.cozy(
                10,
                color: day.label == 'Today'
                    ? Palette.peachDeep
                    : Palette.cocoaSoft,
              ),
            ),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: _labelArea,
            child: Container(
              height: barH,
              decoration: BoxDecoration(
                color: _kcalBarColor(day),
                border: Border.all(color: Palette.outline, width: 1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ),
          ),
          if (showKcal)
            Positioned(
              left: 0,
              right: 0,
              bottom: labelInside
                  ? _labelArea + barH - 18
                  : _labelArea + barH + 3,
              child: Text(
                formatKcal(day.total),
                textAlign: TextAlign.center,
                style: AppTypography.cozy(
                  10,
                  weight: labelInside ? FontWeight.w600 : null,
                  color: labelInside ? Palette.paper : Palette.cocoa,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Page 2 column: macro-split bar with grams inside each colored
  /// segment (when the segment is tall enough).
  Widget _macroDay(MealDay day, double areaHeight) {
    final maxScale = _maxScale;
    final barH = day.total == 0 ? 3.0 : _maxBar * day.total / maxScale;
    final over = day.total > widget.goalKcal;
    final seg = _segments(day);
    final m = widget.macros[day.date] ?? const MacroTotals();

    Widget segment(double h, Color color, {String? label}) {
      if (h < 1) return const SizedBox();
      return SizedBox(
        height: h,
        child: label == null
            ? ColoredBox(color: color)
            : Container(
                color: color,
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: AppTypography.cozy(
                    8,
                    color: color == Palette.peachSoft
                        ? Palette.cocoa
                        : Palette.paper,
                  ),
                ),
              ),
      );
    }

    // Segment heights in px (share of the kcal bar), top -> bottom:
    // rest, fat, carbs, protein (protein anchored at the bottom).
    // The bar's 1px border eats 2px of the inner column height.
    final innerH = barH - 2;
    final hP = day.total > 0 ? innerH * seg.p / day.total : 0.0;
    final hC = day.total > 0 ? innerH * seg.c / day.total : 0.0;
    final hF = day.total > 0 ? innerH * seg.f / day.total : 0.0;
    final hRest = day.total > 0 ? innerH * seg.rest / day.total : innerH;

    final children = <Widget>[
      segment(hRest, Palette.creamDeep),
      segment(hF, Palette.peachSoft,
          label: hF >= 12 && m.fat.round() > 0 ? '${m.fat.round()}g' : null),
      segment(hC, Palette.peach,
          label: hC >= 12 && m.carbs.round() > 0
              ? '${m.carbs.round()}g'
              : null),
      segment(hP, Palette.peachDeep,
          label: hP >= 12 && m.protein.round() > 0
              ? '${m.protein.round()}g'
              : null),
    ];

    return _dayColumn(
      day,
      areaHeight,
      Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 2,
            child: Text(
              day.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: AppTypography.cozy(
                10,
                color: day.label == 'Today'
                    ? Palette.peachDeep
                    : Palette.cocoaSoft,
              ),
            ),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: _labelArea,
            child: Container(
              height: barH,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Palette.creamDeep,
                border: Border.all(
                  color: over ? Palette.blushDeep : Palette.outline,
                  width: 1,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
              child: day.total == 0
                  ? null
                  : Column(children: children),
            ),
          ),
        ],
      ),
    );
  }

  /// Shared day column wrapper: tap target + fixed-height canvas.
  Widget _dayColumn(MealDay day, double areaHeight, Widget content) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onDayTap(day),
        child: SizedBox(
          height: _chartHeight,
          child: content,
        ),
      ),
    );
  }

  Widget _legendChip(Color color, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(color: Palette.outline, width: 0.5),
              ),
            ),
            const SizedBox(width: 4),
            Text(label,
                style: AppTypography.cozy(9, color: Palette.cocoaSoft)),
          ],
        ),
      );

  Widget _macroPage() => Column(
        children: [
          // Legend: which color is which macro.
          SizedBox(
            height: _legendHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendChip(Palette.peachDeep, 'protein'),
                _legendChip(Palette.peach, 'carbs'),
                _legendChip(Palette.peachSoft, 'fat'),
              ],
            ),
          ),
          SizedBox(
            height: _chartHeight - _legendHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _goalLine(_chartHeight - _legendHeight),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in widget.days) _macroDay(d, _chartHeight - _legendHeight),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final kcalPage = Stack(
      clipBehavior: Clip.none,
      children: [
        _goalLine(_chartHeight),
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in widget.days) _kcalDay(d, _chartHeight),
            ],
          ),
        ),
      ],
    );

    return SizedBox(
      height: _chartHeight + 18,
      child: Column(
        children: [
          Expanded(
            child: PageView(
              onPageChanged: (i) => setState(() => _page = i),
              children: [kcalPage, _macroPage()],
            ),
          ),
          const SizedBox(height: 4),
          // Page dots (pixel squares)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 2; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _page ? Palette.peachDeep : Palette.outline,
                    border: Border.all(color: Palette.outline, width: 1),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet: one day's food entries, each deletable.
class _DaySheet extends StatefulWidget {
  const _DaySheet({
    required this.date,
    required this.entriesRepo,
    required this.onChanged,
  });

  final String date;
  final EntryRepository entriesRepo;
  final VoidCallback onChanged;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  List<Entry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final all = await widget.entriesRepo.entriesForDate(widget.date);
    final food = all.where((e) => !e.isWater).toList(growable: false);
    if (!mounted) return;
    setState(() {
      _entries = food;
      _loading = false;
    });
  }

  Future<void> _delete(Entry entry) async {
    await widget.entriesRepo.delete(entry.id!);
    widget.onChanged(); // chart totals update immediately
    await _refresh();
  }

  /// Tap a day-sheet meal -> detail sheet. Edits persist via updateFood
  /// and refresh recents so one-tap re-logs stay accurate.
  Future<void> _openMeal(Entry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MealDetailSheet(
        entry: entry,
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
          await widget.entriesRepo.updateFood(Entry(
            id: entry.id,
            type: EntryType.food,
            name: name,
            mealType: mealType,
            kcal: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            portion: portion,
            createdAt: entry.createdAt,
            date: entry.date,
          ));
          await FoodRepository(widget.entriesRepo.db).upsertFromLog(
            name: name,
            kcal: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
          );
          widget.onChanged();
        },
        onDelete: () => _delete(entry),
      ),
    );
    await _refresh();
  }

  String _prettyDate(String key) {
    final parts = key.split('-');
    final d = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final suffix = dateKey(now) == key ? ' · today' : '';
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}$suffix';
  }

  double get _total =>
      _entries.fold(0, (s, e) => s + (e.effectiveKcal ?? 0));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _prettyDate(widget.date),
              textAlign: TextAlign.center,
              style: AppTypography.pixelDisplay(14),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatKcal(_total)} kcal total',
              textAlign: TextAlign.center,
              style: AppTypography.cozy(13, color: Palette.cocoaSoft),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'no meals logged this day',
                            textAlign: TextAlign.center,
                            style: AppTypography.cozy(
                                13, color: Palette.cocoaSoft),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          itemBuilder: (context, i) {
                            final e = _entries[i];
                            final kcal = e.effectiveKcal ?? 0;
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: GestureDetector(
                                onTap: () => _openMeal(e),
                                child: PixelCard(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.restaurant_outlined,
                                          size: 18, color: Palette.peachDeep),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${e.name ?? 'meal'} · '
                                          '${formatKcal(kcal)} kcal',
                                          style: AppTypography.cozy(13),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                            color: Palette.blushDeep),
                                        onPressed: () => _delete(e),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}