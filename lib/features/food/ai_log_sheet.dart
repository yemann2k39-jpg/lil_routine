import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai/ai_key_store.dart';
import '../../core/ai/gemini_provider.dart';
import '../../core/data/models.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';

import 'log_food_sheet.dart' show AwaitedFoodLogSaved;

/// (AwaitedFoodLogSaved imported from log_food_sheet.dart — kept as a
/// local alias name for readability below.)
typedef AiFoodLogSaved = AwaitedFoodLogSaved;

/// AI food logging (LIL-10): snap a photo or type a description, let
/// Gemini estimate the meal, review on an editable confirmation card,
/// then confirm. NEVER auto-logged — saving goes through the exact
/// manual-log path (entry + recents upsert).
class AiLogSheet extends StatefulWidget {
  const AiLogSheet({
    super.key,
    required this.onPickImage,
    required this.onSaveLog,
    this.estimate,
  });

  /// Returns image bytes or null when the user cancels.
  final Future<Uint8List?> Function(ImageSource source) onPickImage;

  /// The manual-log path (entry + recents), awaited before the sheet pops.
  final AiFoodLogSaved onSaveLog;

  /// Injectable estimator (tests); defaults to the real Gemini provider.
  final Future<AiEstimateResult> Function({
    String? description,
    Uint8List? image,
    String imageMimeType,
  })? estimate;

  @override
  State<AiLogSheet> createState() => _AiLogSheetState();
}

class _AiLogSheetState extends State<AiLogSheet> {
  late final GeminiProvider _provider =
      GeminiProvider(keyStore: FlutterSecureAiKeyStore());
  final _descriptionController = TextEditingController();
  final _nameController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _fiberController = TextEditingController();
  final _sugarController = TextEditingController();
  final _sodiumController = TextEditingController();

  Uint8List? _image;
  String _imageMime = 'image/jpeg';
  bool _busy = false;
  bool _confirming = false; // estimate accepted, editable card shown
  bool _showError = false;
  String? _error;
  String _note = '';
  MealType _meal = MealType.snack;
  double _portion = 1;

  @override
  void initState() {
    super.initState();
    _meal = guessMealType(DateTime.now());
  }

  @override
  void dispose() {
    _descriptionController.dispose();
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

  Future<void> _pick(ImageSource source) async {
    final bytes = await widget.onPickImage(source);
    if (bytes == null) return;
    setState(() {
      _image = bytes;
      _imageMime = source == ImageSource.camera ? 'image/jpeg' : 'image/jpeg';
      _showError = false;
    });
  }

  Future<void> _estimate() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty && _image == null) {
      setState(() => _showError = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = widget.estimate != null
        ? await widget.estimate!(
            description: description,
            image: _image,
            imageMimeType: _imageMime,
          )
        : await _provider.estimateFood(
            description: description,
            image: _image,
            imageMimeType: _imageMime,
          );
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.detail;
      });
      return;
    }
    final e = result.estimate!;
    // Prefill the editable confirmation card.
    _nameController.text = e.name;
    _kcalController.text = e.kcal.round().toString();
    _proteinController.text = e.protein == 0 ? '' : e.protein.round().toString();
    _carbsController.text = e.carbs == 0 ? '' : e.carbs.round().toString();
    _fatController.text = e.fat == 0 ? '' : e.fat.round().toString();
    _fiberController.text = e.fiber == 0 ? '' : e.fiber.round().toString();
    _sugarController.text = e.sugar == 0 ? '' : e.sugar.round().toString();
    _sodiumController.text = e.sodium == 0 ? '' : e.sodium.round().toString();
    setState(() {
      _busy = false;
      _confirming = true;
      _meal = e.mealType;
      _portion = e.portion;
      _note = e.note;
    });
  }

  double get _kcal =>
      double.tryParse(_kcalController.text.trim()) ?? 0;

  double get _effectiveKcal => _kcal * _portion;

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _kcal <= 0) {
      setState(() => _showError = true);
      return;
    }
    await widget.onSaveLog(
      name: name,
      mealType: _meal,
      kcal: _kcal,
      protein: double.tryParse(_proteinController.text.trim()) ?? 0,
      carbs: double.tryParse(_carbsController.text.trim()) ?? 0,
      fat: double.tryParse(_fatController.text.trim()) ?? 0,
      fiber: double.tryParse(_fiberController.text.trim()) ?? 0,
      sugar: double.tryParse(_sugarController.text.trim()) ?? 0,
      sodium: double.tryParse(_sodiumController.text.trim()) ?? 0,
      portion: _portion,
    );
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _backToInput() {
    setState(() {
      _confirming = false;
      _note = '';
      _showError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: _confirming
            ? _buildConfirm()
            : _buildInput(),
      ),
    );
  }

  // ---- Stage 1: input (photo + description) --------------------------

  Widget _buildInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ai meal log · snap or describe',
            style: AppTypography.cozy(12, color: Palette.cocoaSoft)),
        const SizedBox(height: 12),
        // Photo source buttons + preview
        Row(
          children: [
            PixelButton(
              label: 'camera',
              icon: Icons.photo_camera_outlined,
              onTap: _busy ? null : () => _pick(ImageSource.camera),
              color: Palette.peachDeep,
            ),
            const SizedBox(width: 8),
            PixelButton(
              label: 'gallery',
              icon: Icons.photo_outlined,
              onTap: _busy ? null : () => _pick(ImageSource.gallery),
              color: Palette.peachDeep,
            ),
            if (_image != null) ...[
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: Palette.outline, width: 2),
                  borderRadius: BorderRadius.circular(10),
                  image: DecorationImage(
                    image: MemoryImage(_image!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() => _image = null),
                child: const Icon(Icons.close, size: 18,
                    color: Palette.cocoaSoft),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _showError = false),
          decoration: const InputDecoration(
            labelText: 'describe it (e.g. "2 scrambled eggs + toast")',
          ),
        ),
        const SizedBox(height: 12),
        if (_showError)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('a photo or a description is needed',
                style: AppTypography.cozy(12, color: Palette.blushDeep)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!,
                style: AppTypography.cozy(12, color: Palette.blushDeep)),
          ),
        Center(
          child: PixelButton(
            label: _busy ? 'thinking…' : 'estimate with ai',
            icon: Icons.auto_awesome,
            onTap: _busy ? null : _estimate,
            color: Palette.skyDeep,
          ),
        ),
      ],
    );
  }

  // ---- Stage 2: editable confirmation card ---------------------------

  Widget _buildConfirm() {
    const portions = [0.5, 1.0, 1.5, 2.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('gemini says · check before saving',
            style: AppTypography.cozy(12, color: Palette.cocoaSoft)),
        const SizedBox(height: 8),
        if (_note.isNotEmpty) ...[
          Text('note: $_note',
              style: AppTypography.cozy(11, color: Palette.peachDeep)),
          const SizedBox(height: 8),
        ],
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
                      color: _meal == meal ? Palette.skyDeep : Palette.outline,
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
          decoration: const InputDecoration(labelText: 'what did you eat?'),
          onChanged: (_) => setState(() => _showError = false),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _kcalController,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'calories (kcal)'),
          onChanged: (_) => setState(() => _showError = false),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _proteinController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'protein g'),
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
                decoration: const InputDecoration(labelText: 'fiber g'),
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
                decoration: const InputDecoration(labelText: 'sodium mg'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                      color: _portion == p ? Palette.skyDeep : Palette.outline,
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
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            PixelButton(
              label: 'back',
              onTap: _backToInput,
              color: Palette.cocoaSoft,
            ),
            PixelButton(
              label: 'save meal',
              icon: Icons.check,
              onTap: _save,
              color: Palette.peachDeep,
            ),
          ],
        ),
      ],
    );
  }
}
