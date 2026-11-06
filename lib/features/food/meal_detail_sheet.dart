import 'package:flutter/material.dart';

import '../../core/data/models.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';
import 'log_food_sheet.dart' show AwaitedFoodLogSaved, FoodLogForm;

/// Tap a logged meal -> details, edit, delete. Reached from today's
/// meals list and from the history day sheets. Editing reuses the exact
/// manual form prefilled; saving goes through [onSave] (the parent
/// writes via updateFood and refreshes recents), never auto-applied.
class MealDetailSheet extends StatefulWidget {
  const MealDetailSheet({
    super.key,
    required this.entry,
    required this.onSave,
    required this.onDelete,
  });

  final Entry entry;
  final AwaitedFoodLogSaved onSave;
  final Future<void> Function() onDelete;

  @override
  State<MealDetailSheet> createState() => _MealDetailSheetState();
}

class _MealDetailSheetState extends State<MealDetailSheet> {
  bool _editing = false;
  bool _busy = false;

  String _two(int v) => v.toString().padLeft(2, '0');

  String get _timeLabel =>
      '${_two(widget.entry.createdAt.hour)}:${_two(widget.entry.createdAt.minute)}';

  /// The edited values as they will be written (kcal scaled by portion).
  String _effective(double perPortion, double portion) =>
      (perPortion * portion).toStringAsFixed(0);

  Future<void> _save({
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
    setState(() => _busy = true);
    await widget.onSave(
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
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    await widget.onDelete();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Widget _macroRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppTypography.cozy(13, color: Palette.cocoaSoft)),
          ),
          Text(value, style: AppTypography.cozy(13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: _editing
            ? FoodLogForm(
                defaultMealType: e.mealType ?? MealType.snack,
                initial: e,
                onSave: _save,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    e.name ?? 'meal',
                    textAlign: TextAlign.center,
                    style: AppTypography.pixelDisplay(14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${e.mealType?.name ?? 'meal'} · $_timeLabel',
                    textAlign: TextAlign.center,
                    style: AppTypography.cozy(12, color: Palette.cocoaSoft),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_effective(e.kcal ?? 0, e.portion)} kcal logged'
                    '${e.portion != 1 ? ' (${e.kcal?.toStringAsFixed(0)} × ${e.portion} portion)' : ''}',
                    textAlign: TextAlign.center,
                    style:
                        AppTypography.pixelDisplay(12, color: Palette.peachDeep),
                  ),
                  const SizedBox(height: 12),
                  PixelCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _macroRow('protein', _g(e.protein)),
                        _macroRow('carbs', _g(e.carbs)),
                        _macroRow('fat', _g(e.fat)),
                        _macroRow('fiber', _g(e.fiber)),
                        _macroRow('sugar', _g(e.sugar)),
                        _macroRow('sodium', _mg(e.sodium)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        PixelButton(
                          label: 'edit',
                          icon: Icons.edit_outlined,
                          onTap: () => setState(() => _editing = true),
                          color: Palette.skyDeep,
                        ),
                        PixelButton(
                          label: 'delete',
                          icon: Icons.delete_outline,
                          onTap: _delete,
                          color: Palette.blushDeep,
                        ),
                      ],
                    ),
                ],
              ),
      ),
    );
  }

  static String _g(double? v) =>
      '${(v ?? 0).toStringAsFixed((v ?? 0) == (v ?? 0).roundToDouble() ? 0 : 1)} g';

  static String _mg(double? v) =>
      '${(v ?? 0).toStringAsFixed((v ?? 0) == (v ?? 0).roundToDouble() ? 0 : 1)} mg';
}
