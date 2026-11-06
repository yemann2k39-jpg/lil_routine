import 'package:flutter/material.dart';

import '../../core/data/entry_repository.dart';
import '../../core/data/food_repository.dart';
import '../../core/data/models.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';

/// Saved food log payload from the manual form.
typedef FoodLogSaved = void Function({
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

/// Same fields, awaited — used by sheets that pop only after the write
/// completes (AI confirm card, meal edit).
typedef AwaitedFoodLogSaved = Future<void> Function({
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

/// The manual-log path: writes the entry AND upserts the personal food
/// DB (recents/favorites). Used by both the manual sheet and the AI
/// sheet, so AI-confirmed logs behave exactly like hand-logged ones.
Future<void> saveFoodLog({
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
}) async {
  final db = await AppDatabase.instance();
  await EntryRepository(db).addFood(
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
  );
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
}

/// Bottom sheet for logging food:
/// - favorites & recents re-log in ONE tap
/// - custom form: meal type, name, kcal, optional macros, portion multiplier
/// Every save writes an entry AND upserts the personal food DB (recents).
class LogFoodSheet extends StatefulWidget {
  const LogFoodSheet({super.key});

  @override
  State<LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends State<LogFoodSheet> {
  List<FoodItem> _favorites = [];
  List<FoodItem> _recents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final foods = FoodRepository(db);
    final favorites = await foods.favorites();
    final recents = await foods.recents(limit: 8);
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _recents = recents;
      _loading = false;
    });
  }

  Future<void> _saveLog({
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
  }) async {
    await saveFoodLog(
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
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// One-tap re-log from favorites/recents: default portion, smart meal.
  Future<void> _quickLog(FoodItem food) async {
    await _saveLog(
      name: food.name,
      mealType: guessMealType(DateTime.now()),
      kcal: food.kcal,
      protein: food.protein,
      carbs: food.carbs,
      fat: food.fat,
      fiber: food.fiber,
      sugar: food.sugar,
      sodium: food.sodium,
      portion: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_favorites.isNotEmpty) ...[
                    Text('favorites · one tap to log',
                        style:
                            AppTypography.cozy(12, color: Palette.cocoaSoft)),
                    const SizedBox(height: 8),
                    _foodChips(_favorites, highlight: true),
                    const SizedBox(height: 14),
                  ],
                  if (_recents.isNotEmpty) ...[
                    Text('recent', style:
                        AppTypography.cozy(12, color: Palette.cocoaSoft)),
                    const SizedBox(height: 8),
                    _foodChips(_recents),
                    const SizedBox(height: 14),
                  ],
                  Text('custom',
                      style: AppTypography.cozy(12, color: Palette.cocoaSoft)),
                  const SizedBox(height: 8),
                  FoodLogForm(
                    defaultMealType: guessMealType(DateTime.now()),
                    onSave: _saveLog,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _foodChips(List<FoodItem> items, {bool highlight = false}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final food in items)
          GestureDetector(
            onTap: () => _quickLog(food),
            child: Container(
              decoration: BoxDecoration(
                color: highlight ? Palette.skySoft : Palette.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Palette.outline, width: 2),
                boxShadow: const [
                  BoxShadow(color: Palette.shadow, offset: Offset(0, 3),
                      blurRadius: 0),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (highlight)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.favorite, size: 14,
                          color: Palette.blushDeep),
                    ),
                  Text(
                    '${food.name} · ${food.kcal.round()}',
                    style: AppTypography.cozy(13),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Pure-UI manual food form (testable without a database).
/// Pass [initial] to prefill the fields — used when editing an existing
/// logged meal.
class FoodLogForm extends StatefulWidget {
  const FoodLogForm({
    super.key,
    required this.defaultMealType,
    required this.onSave,
    this.initial,
  });

  final MealType defaultMealType;
  final FoodLogSaved onSave;
  final Entry? initial;

  @override
  State<FoodLogForm> createState() => _FoodLogFormState();
}

class _FoodLogFormState extends State<FoodLogForm> {
  late MealType _meal = widget.initial?.mealType ?? widget.defaultMealType;
  late double _portion = widget.initial?.portion ?? 1;
  bool _showError = false;

  late final TextEditingController _nameController =
      TextEditingController(text: widget.initial?.name);
  late final TextEditingController _kcalController = TextEditingController(
      text: widget.initial?.kcal == null ? '' : _fmt(widget.initial!.kcal!));
  late final TextEditingController _proteinController =
      TextEditingController(text: _opt(widget.initial?.protein));
  late final TextEditingController _carbsController =
      TextEditingController(text: _opt(widget.initial?.carbs));
  late final TextEditingController _fatController =
      TextEditingController(text: _opt(widget.initial?.fat));
  late final TextEditingController _fiberController =
      TextEditingController(text: _opt(widget.initial?.fiber));
  late final TextEditingController _sugarController =
      TextEditingController(text: _opt(widget.initial?.sugar));
  late final TextEditingController _sodiumController =
      TextEditingController(text: _opt(widget.initial?.sodium));

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  static String _opt(double? v) => v == null || v == 0 ? '' : _fmt(v);

  @override
  void dispose() {
    _nameController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    _sugarController.dispose();
    _sodiumController.dispose();
    super.dispose();
  }

  double? get _kcal => double.tryParse(_kcalController.text.trim());

  double get _effectiveKcal {
    final kcal = _kcal ?? 0;
    return kcal * _portion;
  }

  void _submit() {
    final name = _nameController.text.trim();
    final kcal = _kcal;
    if (name.isEmpty || kcal == null || kcal <= 0) {
      setState(() => _showError = true);
      return;
    }
    widget.onSave(
      name: name,
      mealType: _meal,
      kcal: kcal,
      protein: double.tryParse(_proteinController.text.trim()) ?? 0,
      carbs: double.tryParse(_carbsController.text.trim()) ?? 0,
      fat: double.tryParse(_fatController.text.trim()) ?? 0,
      fiber: double.tryParse(_fiberController.text.trim()) ?? 0,
      sugar: double.tryParse(_sugarController.text.trim()) ?? 0,
      sodium: double.tryParse(_sodiumController.text.trim()) ?? 0,
      portion: _portion,
    );
  }

  @override
  Widget build(BuildContext context) {
    const portions = [0.5, 1.0, 1.5, 2.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Meal type chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final meal in MealType.values)
              GestureDetector(
                onTap: () => setState(() {
                  _meal = meal;
                  _showError = false;
                }),
                child: Container(
                  decoration: BoxDecoration(
                    color: _meal == meal ? Palette.skySoft : Palette.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          _meal == meal ? Palette.skyDeep : Palette.outline,
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  child: Text(
                    meal.name,
                    style: AppTypography.cozy(
                      12,
                      color: _meal == meal ? Palette.skyDeep : Palette.cocoa,
                      weight: _meal == meal ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
              labelText: 'what did you eat?'),
          onChanged: (_) => setState(() => _showError = false),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _kcalController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'calories (kcal)'),
          onChanged: (_) => setState(() => _showError = false),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _proteinController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'protein g'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _carbsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'carbs g'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _fatController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'fat g'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fiberController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'fiber g'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _sugarController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'sugar g'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _sodiumController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'sodium mg'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Portion multiplier
        Text('portion', style: AppTypography.cozy(12,
            color: Palette.cocoaSoft)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final p in portions)
              GestureDetector(
                onTap: () => setState(() => _portion = p),
                child: Container(
                  decoration: BoxDecoration(
                    color: _portion == p ? Palette.skySoft : Palette.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          _portion == p ? Palette.skyDeep : Palette.outline,
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  child: Text(
                    '${p.toStringAsFixed(p == p.roundToDouble() && p != 0.5 ? 0 : 1)}x',
                    style: AppTypography.cozy(
                      13,
                      color: _portion == p ? Palette.skyDeep : Palette.cocoa,
                      weight: _portion == p ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'logs as: ${_effectiveKcal.toStringAsFixed(0)} kcal',
          style: AppTypography.pixelDisplay(12, color: Palette.peachDeep),
        ),
        if (_showError)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'food name and calories are needed',
              style: AppTypography.cozy(12, color: Palette.blushDeep),
            ),
          ),
        const SizedBox(height: 12),
        Center(
          child: PixelButton(
            label: 'save meal',
            icon: Icons.check,
            onTap: _submit,
            color: Palette.peachDeep,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
