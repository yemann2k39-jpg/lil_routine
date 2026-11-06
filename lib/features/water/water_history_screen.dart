import 'package:flutter/material.dart';

import '../../core/data/entry_repository.dart';
import '../../core/data/models.dart';
import '../../core/data/settings_repository.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';

/// Which chart the dashboard shows: the 7-day bar chart or the daily
/// "today vs weekly average" hourly pattern.
enum HistoryChartView { week, daily }

/// Result of the streak/hearts engine (see [computeStreakAndHearts]).
@immutable
class StreakInfo {
  const StreakInfo({required this.days, required this.heartsLeft});

  /// Streak length in days; stacks across weeks.
  final int days;

  /// Hearts left in the current week (0..3).
  final int heartsLeft;
}

/// Streak engine. A day is "good" when its water total reaches 80% of the
/// goal. Every calendar week (Mon-based) grants 3 hearts; a missed
/// *completed* day costs one heart; losing the last heart resets the
/// streak (it rebuilds from the next good day). Today is pending: it
/// counts toward the streak as soon as it reaches the threshold, but it
/// never costs a heart — the day has to finish first.
StreakInfo computeStreakAndHearts({
  required Map<String, int> totalsByDate,
  required String firstDateKey,
  required String todayKey,
  required int goalMl,
}) {
  const heartsPerWeek = 3;
  if (goalMl <= 0 ||
      firstDateKey.isEmpty ||
      firstDateKey.compareTo(todayKey) > 0) {
    return const StreakInfo(days: 0, heartsLeft: heartsPerWeek);
  }

  final threshold = (goalMl * 0.8).round();
  final today = DateTime.parse(todayKey);
  final firstDate = DateTime.parse(firstDateKey);

  // Anchor: today when it already reached the threshold, otherwise the
  // last completed day (yesterday).
  final anchor = (totalsByDate[todayKey] ?? 0) >= threshold
      ? today
      : today.subtract(const Duration(days: 1));
  if (anchor.isBefore(firstDate)) {
    return const StreakInfo(days: 0, heartsLeft: heartsPerWeek);
  }

  // Walk forward through every day from the first record to the anchor.
  var streak = 0;
  var hearts = heartsPerWeek;
  String? currentWeek;
  for (var d = firstDate;
      !d.isAfter(anchor);
      d = d.add(const Duration(days: 1))) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final week = dateKey(monday);
    if (week != currentWeek) {
      currentWeek = week;
      hearts = heartsPerWeek; // fresh hearts every Monday
    }
    if ((totalsByDate[dateKey(d)] ?? 0) >= threshold) {
      streak += 1;
    } else {
      hearts -= 1;
      if (hearts <= 0) streak = 0; // last heart lost: streak gone
    }
  }

  // Hearts shown = 3 minus this week's misses among completed days.
  // Today is excluded (still pending).
  final mondayOfToday = today.subtract(Duration(days: today.weekday - 1));
  var missesThisWeek = 0;
  for (var d = mondayOfToday;
      dateKey(d).compareTo(todayKey) < 0;
      d = d.add(const Duration(days: 1))) {
    if ((totalsByDate[dateKey(d)] ?? 0) < threshold) missesThisWeek += 1;
  }
  final heartsLeft = heartsPerWeek - missesThisWeek;

  return StreakInfo(
    days: streak,
    heartsLeft: heartsLeft < 0 ? 0 : heartsLeft,
  );
}

/// Format ml with a thousands separator: 17650 -> 17,650.
String formatMl(int ml) {
  final s = ml.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    b.write(s[i]);
    final remaining = s.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) b.write(',');
  }
  return b.toString();
}

/// Water history dashboard. Screen owns data loading; [WaterHistoryView]
/// is pure UI.
class WaterHistoryScreen extends StatefulWidget {
  const WaterHistoryScreen({super.key});

  @override
  State<WaterHistoryScreen> createState() => _WaterHistoryScreenState();
}

class _WaterHistoryScreenState extends State<WaterHistoryScreen> {
  HistoryChartView _view = HistoryChartView.week;
  int _goalMl = SettingsRepository.defaultWaterGoalMl;
  List<WaterDay> _days = const [];
  List<int> _hourToday = const [];
  List<double> _hourAvg = const [];
  int _streakDays = 0;
  int _heartsLeft = 3;
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

    final totals = await entries.waterTotalsForRange(startKey, todayKey);
    final goal = await settings.waterGoalMl();

    // Hourly pattern buckets: today's drinks + 7-day average per hour.
    final weekEntries = await entries.waterEntriesBetween(startKey, todayKey);
    final hourToday = List<int>.filled(24, 0);
    final hourSum = List<int>.filled(24, 0);
    for (final e in weekEntries) {
      final h = e.createdAt.hour;
      hourSum[h] += e.amountMl ?? 0;
      if (e.date == todayKey) hourToday[h] += e.amountMl ?? 0;
    }
    final hourAvg = [for (final s in hourSum) s / 7];

    // Streak + hearts from the full water history.
    final firstDate = await entries.firstWaterDate();
    final StreakInfo streak;
    if (firstDate == null) {
      streak = const StreakInfo(days: 0, heartsLeft: 3);
    } else {
      final allTotals =
          await entries.waterTotalsForRange(firstDate, todayKey);
      streak = computeStreakAndHearts(
        totalsByDate: allTotals,
        firstDateKey: firstDate,
        todayKey: todayKey,
        goalMl: goal,
      );
    }

    if (!mounted) return;
    final days = <WaterDay>[];
    for (var i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = dateKey(date);
      days.add(WaterDay(
        date: key,
        total: totals[key] ?? 0,
        label: i == 0
            ? 'Today'
            : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][
                date.weekday - 1],
      ));
    }
    setState(() {
      _days = days;
      _goalMl = goal;
      _hourToday = hourToday;
      _hourAvg = hourAvg;
      _streakDays = streak.days;
      _heartsLeft = streak.heartsLeft;
      _loading = false;
    });
  }

  Future<void> _openDay(WaterDay day) async {
    final db = await AppDatabase.instance();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DaySheet(
        date: day.date,
        entriesRepo: EntryRepository(db),
        onChanged: _load, // totals refresh immediately under the sheet
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Water History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: WaterHistoryView(
                  days: _days,
                  goalMl: _goalMl,
                  view: _view,
                  hourToday: _hourToday,
                  hourAvg: _hourAvg,
                  streakDays: _streakDays,
                  heartsLeft: _heartsLeft,
                  onViewChange: (v) => setState(() => _view = v),
                  onDayTap: _openDay,
                ),
              ),
            ),
    );
  }
}

/// One day in the chart.
@immutable
class WaterDay {
  const WaterDay({
    required this.date,
    required this.total,
    required this.label,
  });

  final String date; // yyyy-MM-dd
  final int total; // ml
  final String label;
}

/// Pure-UI dashboard: stat squares, chart, hint/legend, view toggle and
/// the goal-hit line. Layout top-to-bottom per spec.
class WaterHistoryView extends StatelessWidget {
  const WaterHistoryView({
    super.key,
    required this.days,
    required this.goalMl,
    required this.view,
    required this.hourToday,
    required this.hourAvg,
    required this.streakDays,
    required this.heartsLeft,
    required this.onViewChange,
    required this.onDayTap,
  });

  final List<WaterDay> days;
  final int goalMl;
  final HistoryChartView view;
  final List<int> hourToday; // 24 buckets, ml
  final List<double> hourAvg; // 24 buckets, avg ml per hour over the week
  final int streakDays;
  final int heartsLeft;
  final ValueChanged<HistoryChartView> onViewChange;
  final ValueChanged<WaterDay> onDayTap;

  @override
  Widget build(BuildContext context) {
    final totalInRange = days.fold<int>(0, (sum, d) => sum + d.total);
    final avg = days.isEmpty ? 0 : (totalInRange / days.length).round();
    final goalHitDays = days.where((d) => d.total >= goalMl).length;
    final todayTotal = days.isEmpty ? 0 : days.last.total;

    final todayLine = todayTotal >= goalMl
        ? 'Today\'s goal is already complete!'
        : todayTotal >= goalMl * 0.6
            ? 'Today is well on track!'
            : 'Today is behind — keep sipping!';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1) Stat squares: Total · Daily Avg · Streak (with hearts)
        // Fixed height: a stretch Row must not sit in unbounded height.
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatSquare(
                label: 'Total',
                value: formatMl(totalInRange),
                sub: 'ml',
              ),
              const SizedBox(width: 8),
              _StatSquare(
                label: 'Daily Avg',
                value: formatMl(avg),
                sub: 'ml/day',
              ),
              const SizedBox(width: 8),
              _StatSquare(
                label: 'Streak',
                value: '$streakDays',
                sub: streakDays == 1 ? 'day' : 'days',
                hearts: heartsLeft,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 2) Chart (week bars with ml labels, or daily pattern lines),
        // framed in a pixel card so it reads as one clean block.
        if (view == HistoryChartView.week)
          PixelCard(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: _WeekChart(days: days, goalMl: goalMl, onDayTap: onDayTap),
          )
        else
          PixelCard(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 200,
                  child: CustomPaint(
                    painter: _DailyLinePainter(
                      today: hourToday,
                      avg: hourAvg,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const _DailyHourLabels(),
              ],
            ),
          ),
        const SizedBox(height: 12),
        // 3) Hint under the chart (legend in daily view)
        Center(
          child: Text(
            view == HistoryChartView.week
                ? 'Tap a day to view drink history'
                : 'Sky = Today · Peach = Week Avg',
            style: AppTypography.cozy(11, color: Palette.cocoaSoft),
          ),
        ),
        const SizedBox(height: 12),
        // 4) View toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final v in HistoryChartView.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: PixelCard(
                  onTap: v == view ? null : () => onViewChange(v),
                  color: v == view ? Palette.skySoft : Palette.paper,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 8),
                  child: Text(
                    v == HistoryChartView.week ? '7 Days' : 'Daily',
                    style: AppTypography.pixelDisplay(
                      12,
                      color: v == view ? Palette.skyDeep : Palette.cocoa,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        // 5) Goal-hit line + today status
        Center(
          child: Text(
            "You've hit your daily goal on $goalHitDays out of 7 days.",
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
      ],
    );
  }
}

/// One stat square: pixel label, big value, small sub line; the streak
/// square additionally shows the 3 heart tokens.
class _StatSquare extends StatelessWidget {
  const _StatSquare({
    required this.label,
    required this.value,
    required this.sub,
    this.hearts,
  });

  final String label;
  final String value;
  final String sub;
  final int? hearts;

  @override
  Widget build(BuildContext context) {
    // Expanded so all three stat squares share the row width equally.
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
            style: AppTypography.pixelDisplay(16, color: Palette.cocoa),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.cozy(10, color: Palette.cocoaSoft),
          ),
          if (hearts != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Icon(
                    i < hearts! ? Icons.favorite : Icons.favorite_border,
                    size: 13,
                    color: i < hearts! ? Palette.blushDeep : Palette.outline,
                  ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// 7-day pixel bar chart with ml labels and a goal line.
class _WeekChart extends StatelessWidget {
  const _WeekChart({
    required this.days,
    required this.goalMl,
    required this.onDayTap,
  });

  final List<WaterDay> days;
  final int goalMl;
  final ValueChanged<WaterDay> onDayTap;

  static const _chartHeight = 230.0;
  static const _labelArea = 24.0;
  static const _maxBar = 130.0;

  /// One day column: bar, day label, ml count inside the bar (above it
  /// when the bar is too short to hold the number).
  Widget _day(WaterDay day, int maxScale) {
    final barH = day.total == 0 ? 3.0 : _maxBar * day.total / maxScale;
    final labelInside = barH >= 24;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onDayTap(day),
        child: SizedBox(
          height: _chartHeight,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              // Day label
              Positioned(
                left: 0,
                right: 0,
                bottom: 2,
                child: Text(
                  day.label,
                  textAlign: TextAlign.center,
                  style: AppTypography.cozy(
                    10,
                    color: day.label == 'Today'
                        ? Palette.skyDeep
                        : Palette.cocoaSoft,
                  ),
                ),
              ),
              // Bar
              Positioned(
                left: 4,
                right: 4,
                bottom: _labelArea,
                child: Container(
                  height: barH,
                  decoration: BoxDecoration(
                    color: day.total >= goalMl
                        ? Palette.skyDeep
                        : (day.total == 0
                            ? Palette.creamDeep
                            : Palette.sky),
                    border: Border.all(color: Palette.outline, width: 1),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ),
              ),
              // ml count: inside the bar when it fits, else above it
              if (day.total > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: labelInside
                      ? _labelArea + barH - 18
                      : _labelArea + barH + 3,
                  child: Text(
                    formatMl(day.total),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxScale = <int>[goalMl, ...days.map((d) => d.total)]
        .fold<int>(1, (a, b) => a > b ? a : b);

    return SizedBox(
      height: _chartHeight,
      child: Stack(
        children: [
          // Goal line
          Positioned(
            left: 0,
            right: 0,
            bottom: _labelArea + _maxBar * goalMl / maxScale - 1,
            child: Container(
              height: 2,
              color: Palette.cocoaSoft.withValues(alpha: 0.45),
            ),
          ),
          Positioned(
            right: 0,
            bottom: _labelArea + _maxBar * goalMl / maxScale + 4,
            child: Text(
              'Goal - ${formatMl(goalMl)} ml',
              style: AppTypography.cozy(10, color: Palette.cocoaSoft),
            ),
          ),
          // Bars with ml labels + day labels
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days) _day(day, maxScale),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Daily pattern line chart: today (sky line + square markers, ml label
/// per logged hour) over the 7-day average pattern (peach line). Sharp
/// segments on purpose — pixel style, no curves.
class _DailyLinePainter extends CustomPainter {
  const _DailyLinePainter({required this.today, required this.avg});

  final List<int> today;
  final List<double> avg;

  static const _topPad = 20.0;
  static const _bottomPad = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = today.length;
    if (n < 2) return;

    var maxVal = 1.0;
    for (var h = 0; h < n; h++) {
      if (today[h] > maxVal) maxVal = today[h].toDouble();
      if (avg[h] > maxVal) maxVal = avg[h];
    }
    final chartH = size.height - _topPad - _bottomPad;
    final stepX = size.width / (n - 1);
    Offset point(int h, double v) =>
        Offset(h * stepX, _topPad + chartH - (v / maxVal) * chartH);

    // Baseline
    canvas.drawLine(
      Offset(0, size.height - _bottomPad),
      Offset(size.width, size.height - _bottomPad),
      Paint()..color = Palette.outline,
    );

    // Week-average pattern line (peach)
    final avgPath = Path()..moveTo(point(0, avg[0]).dx, point(0, avg[0]).dy);
    for (var h = 1; h < n; h++) {
      final p = point(h, avg[h]);
      avgPath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      avgPath,
      Paint()
        ..color = Palette.peach
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Today line (sky) with square markers + ml labels on logged hours
    final todayPath = Path()
      ..moveTo(point(0, today[0].toDouble()).dx, point(0, today[0].toDouble()).dy);
    for (var h = 1; h < n; h++) {
      final p = point(h, today[h].toDouble());
      todayPath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      todayPath,
      Paint()
        ..color = Palette.skyDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (var h = 0; h < n; h++) {
      if (today[h] <= 0) continue;
      final p = point(h, today[h].toDouble());
      canvas.drawRect(
        Rect.fromCenter(center: p, width: 6, height: 6),
        Paint()..color = Palette.skyDeep,
      );
      _label(canvas, p, '${today[h]}');
    }
  }

  void _label(Canvas canvas, Offset p, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.cozy(8, color: Palette.skyDeep),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height - 5));
  }

  @override
  bool shouldRepaint(covariant _DailyLinePainter old) =>
      old.today != today || old.avg != avg;
}

/// Hour labels row for the daily chart (every 3 hours).
class _DailyHourLabels extends StatelessWidget {
  const _DailyHourLabels();

  String _label(int h) {
    const names = [
      '12a', '1a', '2a', '3a', '4a', '5a',
      '6a', '7a', '8a', '9a', '10a', '11a',
      '12p', '1p', '2p', '3p', '4p', '5p',
      '6p', '7p', '8p', '9p', '10p', '11p',
    ];
    return h % 3 == 0 ? names[h] : '';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Row(
        children: [
          for (var h = 0; h < 24; h++)
            Expanded(
              child: Text(
                _label(h),
                textAlign: TextAlign.center,
                style: AppTypography.cozy(8, color: Palette.cocoaSoft),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet: one day's water entries, each deletable.
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
    final water = all.where((e) => e.isWater).toList(growable: false);
    if (!mounted) return;
    setState(() {
      _entries = water;
      _loading = false;
    });
  }

  Future<void> _delete(Entry entry) async {
    await widget.entriesRepo.delete(entry.id!);
    widget.onChanged(); // chart totals update immediately
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
    final suffix =
        dateKey(now) == key ? ' · today' : '';
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}$suffix';
  }

  int get _total => _entries.fold(0, (s, e) => s + (e.amountMl ?? 0));

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
              '${formatMl(_total)} ml total',
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
                            'no glasses logged this day',
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
                            final t = e.createdAt;
                            final hh =
                                t.hour.toString().padLeft(2, '0');
                            final mm =
                                t.minute.toString().padLeft(2, '0');
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: PixelCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.water_drop,
                                        size: 18, color: Palette.skyDeep),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '$hh:$mm · ${e.amountMl} ml',
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
