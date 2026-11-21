import 'package:flutter/material.dart';

import '../../core/insights/insight_engine.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';

/// Cozy insight card: small icon + pixel title + one-line message.
/// Colors follow the insight kind (nudge peach, water-link sky,
/// celebration blush, pattern cocoa, goal suggestion soft).
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight});

  final Insight insight;

  static Color _color(InsightKind kind) => switch (kind) {
        InsightKind.nudge => Palette.peachDeep,
        InsightKind.link => Palette.skyDeep,
        InsightKind.celebrate => Palette.blushDeep,
        InsightKind.pattern => Palette.cocoa,
        InsightKind.goal => Palette.cocoaSoft,
      };

  static IconData _icon(InsightKind kind) => switch (kind) {
        InsightKind.nudge => Icons.tips_and_updates_outlined,
        InsightKind.link => Icons.water_drop_outlined,
        InsightKind.celebrate => Icons.celebration_outlined,
        InsightKind.pattern => Icons.query_stats,
        InsightKind.goal => Icons.flag_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color(insight.kind);
    return PixelCard(
      color: Palette.paper,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(insight.kind), size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: AppTypography.pixelDisplay(11, color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  insight.message,
                  style: AppTypography.cozy(12, color: Palette.cocoa),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rotating stable pick: with more qualifying insights than [max], a
/// different subset shows each day (deterministic, no randomness).
List<Insight> pickInsights(List<Insight> insights, int max, DateTime now) {
  if (insights.length <= max) return insights;
  final dayIndex = now.difference(DateTime(now.year)).inDays;
  final start = dayIndex % insights.length;
  return [
    for (var i = 0; i < insights.length; i++)
      insights[(start + i) % insights.length],
  ].take(max).toList(growable: false);
}

/// The insights section for a dashboard: up to [max] cards, plus a cozy
/// hint when there is nothing to say yet.
class InsightsSection extends StatelessWidget {
  const InsightsSection({
    super.key,
    required this.insights,
    required this.now,
    this.max = 3,
    this.emptyText =
        'Log a few more days and I will start noticing things!',
  });

  final List<Insight> insights;
  final DateTime now;
  final int max;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final shown = pickInsights(insights, max, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'little insights',
            style: AppTypography.pixelDisplay(13, color: Palette.cocoa),
          ),
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          Center(
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: AppTypography.cozy(12, color: Palette.cocoaSoft),
            ),
          )
        else
          for (final insight in shown) ...[
            InsightCard(insight: insight),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}
