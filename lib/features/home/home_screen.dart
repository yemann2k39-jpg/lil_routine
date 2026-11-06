import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data' show Uint8List;

import '../../core/ai/ai_key_store.dart';
import '../../core/data/drink_slot_repository.dart';
import '../../core/data/entry_repository.dart';
import '../../core/data/food_repository.dart';
import '../../core/data/models.dart';
import '../../core/data/settings_repository.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_cup.dart';
import '../../core/widgets/pixel_nav_bar.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../debug/debug_screen.dart';
import '../food/ai_log_sheet.dart';
import '../food/calorie_ring.dart';
import '../food/food_history_screen.dart';
import '../food/log_food_sheet.dart';
import '../food/meal_detail_sheet.dart';
import '../mascot/animated_mascot.dart';
import '../mascot/mascot_expression.dart';
import '../settings/settings_screen.dart';
import '../water/water_history_screen.dart';
import '../water/water_ring.dart';

/// Placeholder user name until the Settings ticket (LIL-11) adds real
/// profile management.
const String kUserName = 'Niko';

/// Temporary pinned water goal until goal management arrives (LIL-11).
const int kPinnedWaterGoalMl = 3000;

/// App shell: two pages (water / meals) with a pixel bottom nav.
/// [HomeScreen] owns all data loading; the page views are pure UI.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _page = 0;
  bool _loading = true;

  // Water
  int _waterTotal = 0;
  int _goalMl = kPinnedWaterGoalMl;
  List<DrinkSlot> _slots = const [];
  bool _canUndo = false;
  List<Entry> _drinksToday = [];

  // Meals
  double _kcalTotal = 0;
  int _kcalGoal = SettingsRepository.defaultKcalGoal;
  List<Entry> _foodToday = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final db = await AppDatabase.instance();
    final entries = EntryRepository(db);
    final settings = SettingsRepository(db);
    final slots = DrinkSlotRepository(db);
    final today = dateKey(DateTime.now());

    final waterTotal = await entries.waterTotalForDate(today);
    final lastWater = await entries.latestWater();
    final kcal = await entries.kcalTotalForDate(today);
    final kcalGoal = await settings.kcalGoal();
    final allToday = await entries.entriesForDate(today);
    final foodToday =
        allToday.where((e) => !e.isWater).toList(growable: false);
    // Today's drinks, newest first (the list reads like a log).
    final drinksToday = allToday.where((e) => e.isWater).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    await slots.ensureDefault();
    final slotList = await slots.list();

    // Temporary: goal is pinned to 3000 until LIL-11 adds goal management.
    // Overwrite any stale stored value from earlier seeds.
    final goal = await settings.waterGoalMl();
    if (goal != kPinnedWaterGoalMl) {
      await settings.setWaterGoalMl(kPinnedWaterGoalMl);
    }

    if (!mounted) return;
    setState(() {
      _waterTotal = waterTotal;
      _goalMl = kPinnedWaterGoalMl;
      _slots = slotList;
      _canUndo = lastWater != null;
      _drinksToday = drinksToday;
      _kcalTotal = kcal;
      _kcalGoal = kcalGoal;
      _foodToday = foodToday;
      _loading = false;
    });
  }

  // --- Water actions ---
  Future<void> _logSlot(DrinkSlot slot) async {
    final db = await AppDatabase.instance();
    await EntryRepository(db).addWater(amountMl: slot.ml);
    await _reload();
  }

  Future<void> _undoLast() async {
    final db = await AppDatabase.instance();
    final repo = EntryRepository(db);
    final last = await repo.latestWater();
    if (last?.id != null) {
      await repo.delete(last!.id!);
      await _reload();
    }
  }

  Future<void> _deleteDrink(Entry entry) async {
    final db = await AppDatabase.instance();
    await EntryRepository(db).delete(entry.id!);
    await _reload();
  }

  Future<void> _openAddDrink() async {
    final db = await AppDatabase.instance();
    final repo = DrinkSlotRepository(db);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _AddDrinkDialog(
        onAdd: (name, ml) async {
          await repo.add(name: name, ml: ml);
        },
      ),
    );
    await _reload();
  }

  Future<void> _removeSlot(DrinkSlot slot) async {
    final db = await AppDatabase.instance();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove cup?', style: AppTypography.pixelDisplay(14)),
        content: Text(
          "'${slot.name}' (${slot.ml} ml) will be removed from your cups.",
          style: AppTypography.cozy(13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: AppTypography.cozy(13)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Remove', style: AppTypography.pixelDisplay(11)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DrinkSlotRepository(db).remove(slot.id!);
      await _reload();
    }
  }

  // --- Meal actions ---
  Future<void> _openLogFood() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const LogFoodSheet(),
    );
    await _reload();
  }

  Future<Uint8List?> _pickAiImage(ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (xfile == null) return null;
    return xfile.readAsBytes();
  }

  Future<void> _openAiLogFood() async {
    // Gated: AI features stay locked until a Gemini key is configured.
    final configured =
        await AiGate(FlutterSecureAiKeyStore()).isConfigured();
    if (!configured) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('AI is off'),
          content: const Text(
            'Add your own free Gemini key in Settings to snap or describe '
            'meals and let AI estimate them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (open == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      }
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiLogSheet(
        onPickImage: _pickAiImage,
        onSaveLog: saveFoodLog,
      ),
    );
    await _reload();
  }

  Future<void> _deleteFood(Entry entry) async {
    final db = await AppDatabase.instance();
    await EntryRepository(db).delete(entry.id!);
    await _reload();
  }

  /// Tap a logged meal -> detail sheet; edits persist via updateFood and
  /// also refresh the recents entry so one-tap re-logs stay accurate.
  Future<void> _openMealDetail(Entry entry) async {
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
          final db = await AppDatabase.instance();
          await EntryRepository(db).updateFood(Entry(
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
          await FoodRepository(db).upsertFromLog(
            name: name,
            kcal: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
          );
        },
        onDelete: () => _deleteFood(entry),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LilRoutine'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.assessment_outlined),
            tooltip: 'history chart',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    _page == 0 ? const WaterHistoryScreen() : const MealsHistoryScreen(),
              ),
            ),
          ),
          // Debug-only entry to the data-layer test room.
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'debug',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DebugScreen()),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: IndexedStack(
                index: _page,
                children: [
                  WaterPageView(
                    userName: kUserName,
                    waterTotalMl: _waterTotal,
                    goalMl: _goalMl,
                    slots: _slots,
                    maxSlots: DrinkSlotRepository.maxSlots,
                    canUndo: _canUndo,
                    drinkEntries: _drinksToday,
                    onDeleteDrink: _deleteDrink,
                    onLogSlot: _logSlot,
                    onAddSlot: _openAddDrink,
                    onRemoveSlot: _removeSlot,
                    onUndo: _undoLast,
                  ),
                  FoodPageView(
                    kcalTotal: _kcalTotal,
                    kcalGoal: _kcalGoal,
                    onLogFood: _openLogFood,
                    onAiLogFood: _openAiLogFood,
                    onMealTap: _openMealDetail,
                    foodEntries: _foodToday,
                    onDeleteFood: _deleteFood,
                  ),
                ],
              ),
            ),
      bottomNavigationBar: PixelNavBar(
        index: _page,
        onTap: (i) => setState(() => _page = i),
        items: const [
          PixelNavItem(icon: Icons.water_drop_outlined, label: 'water'),
          PixelNavItem(icon: Icons.restaurant_outlined, label: 'meals'),
        ],
      ),
    );
  }
}

/// Water page: greeting, ring with mascot inside, stats below, cup slots,
/// then today's drinks — one scrolling page (mirrors the meals page).
class WaterPageView extends StatelessWidget {
  const WaterPageView({
    super.key,
    required this.userName,
    required this.waterTotalMl,
    required this.goalMl,
    required this.slots,
    required this.maxSlots,
    required this.canUndo,
    required this.onLogSlot,
    required this.onAddSlot,
    required this.onRemoveSlot,
    required this.onUndo,
    this.drinkEntries = const [],
    this.onDeleteDrink,
    this.showUndoChip = false,
  });

  final String userName;
  final int waterTotalMl;
  final int goalMl;
  final List<DrinkSlot> slots;
  final int maxSlots;
  final bool canUndo;
  final ValueChanged<DrinkSlot> onLogSlot;
  final VoidCallback onAddSlot;
  final ValueChanged<DrinkSlot> onRemoveSlot;
  final VoidCallback onUndo;

  /// Today's water entries, newest first, shown as pixel cards with
  /// per-entry delete (the water twin of "today's meals").
  final List<Entry> drinkEntries;
  final ValueChanged<Entry>? onDeleteDrink;

  /// The undo chip is retired (per-entry delete replaced it) but kept
  /// wired so it can be flipped back on later.
  final bool showUndoChip;

  @override
  Widget build(BuildContext context) {
    final complete = waterTotalMl >= goalMl;
    final progress = goalMl <= 0 ? 0.0 : (waterTotalMl / goalMl).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // One scrolling page: greeting -> ring -> cup slots -> today's
      // drinks (same pattern as the meals page).
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // Greeting (left-aligned)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${greetingFor(DateTime.now())}, $userName',
                style: AppTypography.pixelDisplay(15),
              ),
            ),
            const SizedBox(height: 12),
            // Ring with Lil Drop inside, numbers below it.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WaterRing(
                    totalMl: waterTotalMl,
                    goalMl: goalMl,
                    centerChild: AnimatedMascot(
                      size: 132,
                      expression: mascotExpression(
                        now: DateTime.now(),
                        totalMl: waterTotalMl,
                        goalMl: goalMl,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${(progress * 100).round()}%',
                    style: AppTypography.pixelDisplay(
                      26,
                      color: complete ? Palette.skyDeep : Palette.cocoa,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$waterTotalMl / $goalMl ml',
                    style: AppTypography.cozy(17, color: Palette.cocoa),
                  ),
                  const SizedBox(height: 4),
                  if (complete)
                    Text(
                      'Daily goal reached!',
                      style: AppTypography.pixelDisplay(
                          12, color: Palette.skyDeep),
                    )
                  else
                    Text(
                      '${goalMl - waterTotalMl} ml to go',
                      style: AppTypography.cozy(13, color: Palette.cocoaSoft),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Cup quick-slots, fixed square size
            LayoutBuilder(
              builder: (context, cons) {
                final slotSize = cons.maxWidth / maxSlots - 8;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final slot in slots)
                      _SlotSquare(
                        slot: slot,
                        size: slotSize,
                        onTap: () => onLogSlot(slot),
                        onLongPress: () => onRemoveSlot(slot),
                      ),
                    if (slots.length < maxSlots)
                      _AddSlotSquare(size: slotSize, onTap: onAddSlot),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
          Center(
            child: Text(
              'Hold to remove',
              style: AppTypography.cozy(11, color: Palette.cocoaSoft),
            ),
          ),
          // Undo chip retired (per-entry delete in today's drinks
          // replaced it) — kept wired behind a flag for later reuse.
          if (showUndoChip) ...[
            const SizedBox(height: 10),
            Center(
              child: _UndoChip(canUndo: canUndo, onUndo: onUndo),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'today\'s drinks',
            style: AppTypography.pixelDisplay(12, color: Palette.cocoaSoft),
          ),
          const SizedBox(height: 8),
          if (drinkEntries.isEmpty)
            PixelCard(
              child: Text(
                'nothing logged yet — tap a cup above!',
                style: AppTypography.cozy(13, color: Palette.cocoaSoft),
              ),
            )
          else
            for (final e in drinkEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PixelCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.water_drop_outlined,
                        size: 20,
                        color: Palette.skyDeep,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${e.amountMl ?? 0} ml',
                              style: AppTypography.cozy(13),
                            ),
                            Text(
                              '${e.createdAt.hour.toString().padLeft(2, '0')}:'
                              '${e.createdAt.minute.toString().padLeft(2, '0')}',
                              style: AppTypography.cozy(
                                  11, color: Palette.cocoaSoft),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: Palette.blushDeep),
                        onPressed: () => onDeleteDrink?.call(e),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Capitalize the first letter of a slot name for display.
String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// A cup quick-slot square: pixel cup art + name + ml. Tap = log.
/// Fixed [size] regardless of how many cups exist.
class _SlotSquare extends StatelessWidget {
  const _SlotSquare({
    required this.slot,
    required this.size,
    required this.onTap,
    required this.onLongPress,
  });

  final DrinkSlot slot;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: size,
          height: size / 0.85,
          child: Container(
            decoration: BoxDecoration(
              color: Palette.paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Palette.outline, width: 2),
              boxShadow: const [
                BoxShadow(color: Palette.shadow, offset: Offset(0, 4),
                    blurRadius: 0),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const PixelCup(size: 34),
                const SizedBox(height: 6),
                Text(
                  _capitalize(slot.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cozy(11),
                ),
                Text(
                  '${slot.ml} ml',
                  style: AppTypography.cozy(11, color: Palette.cocoaSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "+ add cup" square, shown while under the slot limit.
class _AddSlotSquare extends StatelessWidget {
  const _AddSlotSquare({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size / 0.85,
          child: Container(
            decoration: BoxDecoration(
              color: Palette.paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Palette.outline, width: 2),
              boxShadow: const [
                BoxShadow(color: Palette.shadow, offset: Offset(0, 4),
                    blurRadius: 0),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 30, color: Palette.cocoaSoft),
                const SizedBox(height: 6),
                Text(
                  'Add cup',
                  style: AppTypography.cozy(11, color: Palette.cocoa),
                ),
                Text(
                  'New drink',
                  style: AppTypography.cozy(11, color: Palette.cocoaSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Undo chip styled as a small button so it reads as tappable.
class _UndoChip extends StatelessWidget {
  const _UndoChip({required this.canUndo, required this.onUndo});

  final bool canUndo;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canUndo ? onUndo : null,
      child: Container(
        decoration: BoxDecoration(
          color: canUndo ? Palette.paper : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: canUndo ? Palette.cocoaSoft : Palette.outline,
            width: 2,
          ),
          boxShadow: canUndo
              ? const [
                  BoxShadow(
                      color: Palette.shadow,
                      offset: Offset(0, 2),
                      blurRadius: 0),
                ]
              : const [],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.replay,
              size: 14,
              color: canUndo ? Palette.cocoa : Palette.outline,
            ),
            const SizedBox(width: 4),
            Text(
              'Undo last',
              style: AppTypography.cozy(
                11,
                color: canUndo ? Palette.cocoa : Palette.outline,
                weight: canUndo ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog: add a new drink cup (name + ml). Cup design choice comes later.
class _AddDrinkDialog extends StatefulWidget {
  const _AddDrinkDialog({required this.onAdd});

  final Future<void> Function(String name, int ml) onAdd;

  @override
  State<_AddDrinkDialog> createState() => _AddDrinkDialogState();
}

class _AddDrinkDialogState extends State<_AddDrinkDialog> {
  late final TextEditingController _nameController = TextEditingController();
  late final TextEditingController _mlController = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mlController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    final ml = int.tryParse(_mlController.text.trim());
    if (name.isEmpty || ml == null || ml <= 0) {
      setState(() => _showError = true);
      return;
    }
    await widget.onAdd(name, ml);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add a cup', style: AppTypography.pixelDisplay(14)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
                labelText: 'Drink name (e.g. bottle, mug)'),
            onChanged: (_) => setState(() => _showError = false),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mlController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (ml)'),
            onChanged: (_) => setState(() => _showError = false),
          ),
          const SizedBox(height: 6),
          Text(
            'Cup designs are coming in the polish pass',
            style: AppTypography.cozy(11, color: Palette.cocoaSoft),
          ),
          if (_showError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Name and ml are needed',
                style: AppTypography.cozy(12, color: Palette.blushDeep),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTypography.cozy(13)),
        ),
        FilledButton(
          onPressed: _add,
          child: Text('Add cup', style: AppTypography.pixelDisplay(11)),
        ),
      ],
    );
  }
}

/// Meals page: calorie ring + log button + today's logged meals.
class FoodPageView extends StatelessWidget {
  const FoodPageView({
    super.key,
    required this.kcalTotal,
    required this.kcalGoal,
    required this.onLogFood,
    required this.onAiLogFood,
    required this.onMealTap,
    required this.foodEntries,
    required this.onDeleteFood,
  });

  final double kcalTotal;
  final int kcalGoal;
  final VoidCallback onLogFood;
  final VoidCallback onAiLogFood;
  final ValueChanged<Entry> onMealTap;
  final List<Entry> foodEntries;
  final ValueChanged<Entry> onDeleteFood;

  @override
  Widget build(BuildContext context) {
    const mealIcons = {
      MealType.breakfast: Icons.wb_sunny_outlined,
      MealType.lunch: Icons.lunch_dining_outlined,
      MealType.dinner: Icons.dinner_dining_outlined,
      MealType.snack: Icons.cookie_outlined,
    };
    final remaining = kcalGoal - kcalTotal;
    final over = remaining < 0;
    final progress = kcalGoal <= 0 ? 0.0 : (kcalTotal / kcalGoal).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // One scrolling page: greeting at the top, meal history at the
      // bottom (Niko: "make the whole page scrollable").
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // Greeting (left-aligned), matching the water page.
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${greetingFor(DateTime.now())}, $kUserName',
                style: AppTypography.pixelDisplay(15),
              ),
            ),
            const SizedBox(height: 12),
            // Ring with Lil Drop (calorie art set) inside; numbers below.
            // Render height 133 matches the water mascot's visible
            // character height (calorie canvases are ~87.7% character
            // vs water's ~88.3% — matched by character, not canvas).
            Center(
              child: CalorieRing(
                totalKcal: kcalTotal,
                goalKcal: kcalGoal,
                centerChild: AnimatedMascot(
                  size: 133,
                  artSet: MascotArtSet.calorie,
                  expression: mascotExpression(
                    now: DateTime.now(),
                    totalMl: kcalTotal.round(),
                    goalMl: kcalGoal,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${(progress * 100).round()}%',
                style: AppTypography.pixelDisplay(
                  26,
                  color: over ? Palette.peachDeep : Palette.cocoa,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${kcalTotal.round()} / $kcalGoal kcal',
                style: AppTypography.cozy(17, color: Palette.cocoa),
              ),
            ),
            const SizedBox(height: 4),
            if (over)
              Center(
                child: Text(
                  '+${remaining.abs().round()} kcal over',
                  style: AppTypography.cozy(13, color: Palette.blushDeep),
                ),
              )
            else
              Center(
                child: Text(
                  '${remaining.round()} kcal left',
                  style: AppTypography.cozy(13, color: Palette.cocoaSoft),
                ),
              ),
            const SizedBox(height: 12),
            Center(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  PixelButton(
                    label: 'log food',
                    icon: Icons.restaurant_outlined,
                    onTap: onLogFood,
                    color: Palette.peachDeep,
                  ),
                  PixelButton(
                    label: 'ai log',
                    icon: Icons.auto_awesome,
                    onTap: onAiLogFood,
                    color: Palette.skyDeep,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'today\'s meals',
              style: AppTypography.pixelDisplay(12, color: Palette.cocoaSoft),
            ),
            const SizedBox(height: 8),
          if (foodEntries.isEmpty)
            PixelCard(
              child: Text(
                'nothing logged yet — tap log food above!',
                style: AppTypography.cozy(13, color: Palette.cocoaSoft),
              ),
            )
          else
            for (final e in foodEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => onMealTap(e),
                  child: PixelCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          mealIcons[e.mealType] ?? Icons.restaurant_outlined,
                          size: 20,
                          color: Palette.peachDeep,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.name ?? '',
                                style: AppTypography.cozy(13),
                              ),
                              Text(
                                '${e.mealType?.name} · '
                                '${e.effectiveKcal?.toStringAsFixed(0)} kcal'
                                ' (${e.portion.toStringAsFixed(e.portion == e.portion.roundToDouble() ? 0 : 1)}x)',
                                style: AppTypography.cozy(11,
                                    color: Palette.cocoaSoft),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Palette.blushDeep),
                          onPressed: () => onDeleteFood(e),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
