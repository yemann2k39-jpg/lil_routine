import 'package:flutter/material.dart';

import '../../core/data/debug_data_service.dart';
import '../../core/data/entry_repository.dart';
import '../../core/data/models.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';
import 'debug_ai_chat_screen.dart';

/// DEBUG ONLY — never shown in release builds.
/// Proves the data layer: seed, wipe, counts, and today's log.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  Map<String, int> _counts = {};
  List<Entry> _today = [];
  int _waterTotal = 0;
  double _kcalTotal = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final db = await AppDatabase.instance();
    final debug = DebugDataService(db);
    final entries = EntryRepository(db);
    final today = dateKey(DateTime.now());
    setState(() {
      _busy = true;
    });
    final counts = await debug.tableCounts();
    final list = await entries.entriesForDate(today);
    final water = await entries.waterTotalForDate(today);
    final kcal = await entries.kcalTotalForDate(today);
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _today = list;
      _waterTotal = water;
      _kcalTotal = kcal;
      _busy = false;
    });
  }

  Future<void> _seed() async {
    setState(() => _busy = true);
    final db = await AppDatabase.instance();
    await DebugDataService(db).seedSampleData();
    await _refresh();
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    final db = await AppDatabase.instance();
    await DebugDataService(db).clearAllData();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('debug room')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('table counts',
                  style: AppTypography.pixelDisplay(14, color: Palette.skyDeep)),
              const SizedBox(height: 8),
              PixelCard(
                padding: const EdgeInsets.all(12),
                child: _counts.isEmpty
                    ? const Text('...')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in _counts.entries)
                            Text('${e.key}: ${e.value}',
                                style: AppTypography.cozy(13)),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Text('today',
                  style: AppTypography.pixelDisplay(14, color: Palette.skyDeep)),
              const SizedBox(height: 8),
              PixelCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('water: $_waterTotal ml',
                        style: AppTypography.cozy(13)),
                    Text('kcal: ${_kcalTotal.toStringAsFixed(0)}',
                        style: AppTypography.cozy(13)),
                    const SizedBox(height: 8),
                    if (_today.isEmpty)
                      Text('(nothing logged today)',
                          style:
                              AppTypography.cozy(12, color: Palette.cocoaSoft))
                    else
                      for (final e in _today)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            e.isWater
                                ? 'water +${e.amountMl} ml'
                                : '${e.mealType?.name}: ${e.name} '
                                    '${e.effectiveKcal?.toStringAsFixed(0)} kcal',
                            style: AppTypography.cozy(12),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  PixelButton(label: 'seed', onTap: _busy ? null : _seed),
                  PixelButton(
                    label: 'clear all',
                    onTap: _busy ? null : _clear,
                    color: Palette.blushDeep,
                  ),
                  PixelButton(label: 'refresh', onTap: _busy ? null : _refresh, color: Palette.peachDeep),
                  PixelButton(
                    label: 'ai chat',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DebugAiChatScreen()),
                    ),
                    color: Palette.skyDeep,
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 8),
              Text(
                'restart the app after seeding — data should survive',
                textAlign: TextAlign.center,
                style: AppTypography.cozy(12, color: Palette.cocoaSoft),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
