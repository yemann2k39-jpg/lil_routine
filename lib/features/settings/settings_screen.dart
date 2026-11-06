import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai/ai_key_store.dart';
import '../../core/ai/gemini_provider.dart';
import '../../core/data/settings_repository.dart';
import '../../core/db/app_database.dart';
import '../../core/notifications/reminder_service.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';

/// Settings screen: for now the water reminder. Water goal, glass size,
/// calorie goal and the user name land here later (rest of LIL-11).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _enabled = SettingsRepository.defaultReminderEnabled;
  int _minutes = SettingsRepository.defaultReminderMinutes;
  bool _aiHasKey = false;
  bool _loading = true;
  late final AiKeyStore _aiKeyStore = FlutterSecureAiKeyStore();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final settings = SettingsRepository(db);
    final enabled = await settings.reminderEnabled();
    final minutes = await settings.reminderMinutes();
    final aiHasKey = await _aiKeyStore.readKey() != null;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _minutes = minutes;
      _aiHasKey = aiHasKey;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    if (value) {
      final ok = await ReminderService.enable(minutes: _minutes);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are blocked — enable them in system settings',
            ),
          ),
        );
        return; // stay off
      }
      // Exact alarms are denied by default on Android 12+; without them
      // reminders can be delayed a lot when the phone sleeps.
      if (!(await ReminderService.canScheduleExact())) {
        if (!mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Allow Exact Alarms?'),
            content: const Text(
              'Without exact alarms, Android may delay your reminders by '
              '10-15 minutes or more when the phone is sleeping. '
              'Open system settings to allow them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not Now'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        if (open == true) {
          await ReminderService.requestExactAlarmsPermission();
        }
        if (!(await ReminderService.canScheduleExact())) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Reminders are on, but Android may delay them while '
                'the phone sleeps',
              ),
            ),
          );
        }
      }
      // Battery optimization exemption: without it, Samsung-style battery
      // managers freeze the app and reminders never arrive at all.
      if (!(await ReminderService.isIgnoringBatteryOptimizations())) {
        if (!mounted) return;
        final allowBattery = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Allow Background Running?'),
            content: const Text(
              'Phones freeze background apps to save battery, which can '
              'swallow your reminders entirely. Allow LilRoutine to run '
              'in the background?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not Now'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Allow'),
              ),
            ],
          ),
        );
        if (allowBattery == true) {
          await ReminderService.requestIgnoreBatteryOptimizations();
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Reminders are on, but may not arrive while the phone '
                'is sleeping',
              ),
            ),
          );
        }
      }
    } else {
      await ReminderService.disable();
    }
    final db = await AppDatabase.instance();
    await SettingsRepository(db).setReminderEnabled(value);
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _setMinutes(int value) async {
    final minutes = value.clamp(1, 720);
    final db = await AppDatabase.instance();
    await SettingsRepository(db).setReminderMinutes(minutes);
    if (!mounted) return;
    setState(() => _minutes = minutes);
    if (_enabled) {
      await ReminderService.enable(minutes: minutes); // reschedule
    }
  }

  Future<void> _saveAiKey(String key) async {
    await _aiKeyStore.writeKey(key.trim());
    if (!mounted) return;
    setState(() => _aiHasKey = true);
  }

  Future<AiResult> _testAiKey() =>
      GeminiProvider(keyStore: _aiKeyStore).testConnection();

  Future<void> _openAiStudio() async {
    final uri = Uri.parse(kAiStudioUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // No browser/handler available; the URL is visible in the card, so
      // the user can copy it manually.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SettingsView(
                    reminderEnabled: _enabled,
                    reminderMinutes: _minutes,
                    onToggleReminders: _toggle,
                    onMinutesChanged: _setMinutes,
                    onTestReminder: () => ReminderService.testNow(),
                    aiHasKey: _aiHasKey,
                    onAiSaveKey: _saveAiKey,
                    onAiTestKey: _testAiKey,
                    onOpenAiStudio: _openAiStudio,
                  ),
                ],
              ),
            ),
    );
  }
}

/// Pure-UI settings content (testable without the plugin).
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.reminderEnabled,
    required this.reminderMinutes,
    required this.onToggleReminders,
    required this.onMinutesChanged,
    this.onTestReminder,
    this.aiHasKey = false,
    this.onAiSaveKey,
    this.onAiTestKey,
    this.onOpenAiStudio,
  });

  final bool reminderEnabled;
  final int reminderMinutes;
  final ValueChanged<bool> onToggleReminders;
  final ValueChanged<int> onMinutesChanged;
  final VoidCallback? onTestReminder;

  /// AI section — null handlers hide the section entirely (pure tests).
  final bool aiHasKey;
  final Future<void> Function(String)? onAiSaveKey;
  final Future<AiResult> Function()? onAiTestKey;
  final VoidCallback? onOpenAiStudio;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _minutesController =
      TextEditingController(text: '${widget.reminderMinutes}');
  String? _error;
  bool _saved = false;

  @override
  void didUpdateWidget(SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reminderMinutes != oldWidget.reminderMinutes &&
        widget.reminderMinutes.toString() != _minutesController.text) {
      _minutesController.text = '${widget.reminderMinutes}';
    }
  }

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  void _commit() {
    final value = int.tryParse(_minutesController.text.trim());
    if (value == null || value < 1 || value > 720) {
      setState(() {
        _error = 'Enter 1 - 720 minutes';
        _saved = false;
      });
      return;
    }
    setState(() {
      _error = null;
      _saved = true;
    });
    widget.onMinutesChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reminders',
          style: AppTypography.pixelDisplay(12, color: Palette.cocoaSoft),
        ),
        const SizedBox(height: 8),
        PixelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Water Reminders',
                      style: AppTypography.cozy(14, color: Palette.cocoa),
                    ),
                  ),
                  Switch(
                    value: widget.reminderEnabled,
                    onChanged: widget.onToggleReminders,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.reminderEnabled
                          ? 'A cozy nudge every ${widget.reminderMinutes} '
                              '${widget.reminderMinutes == 1 ? 'minute' : 'minutes'}'
                          : 'Reminders are off',
                      style: AppTypography.cozy(12, color: Palette.cocoaSoft),
                    ),
                  ),
                  if (widget.onTestReminder != null)
                    GestureDetector(
                      onTap: widget.onTestReminder,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'Test now',
                          style: AppTypography.cozy(
                            12,
                            color: Palette.skyDeep,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PixelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Every (minutes)',
                style: AppTypography.cozy(13, color: Palette.cocoa),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _minutesController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Minutes between reminders',
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null || _saved) {
                    setState(() {
                      _error = null;
                      _saved = false;
                    });
                  }
                },
                onSubmitted: (_) => _commit(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _saved
                          ? 'Saved ✓'
                          : 'Type a number, then tap Save',
                      style: AppTypography.cozy(
                        11,
                        color: _saved ? Palette.skyDeep : Palette.cocoaSoft,
                      ),
                    ),
                  ),
                  PixelButton(label: 'Save', onTap: _commit),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const [5, 15, 30, 60, 120])
                    ActionChip(
                      label: Text(
                        '$m Min',
                        style: AppTypography.cozy(12, color: Palette.cocoa),
                      ),
                      onPressed: () {
                        _minutesController.text = '$m';
                        setState(() {
                          _error = null;
                          _saved = true;
                        });
                        widget.onMinutesChanged(m);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'AI (bring your own key)',
          style: AppTypography.pixelDisplay(12, color: Palette.cocoaSoft),
        ),
        const SizedBox(height: 8),
        AiKeyCard(
          hasKey: widget.aiHasKey,
          onSaveKey: widget.onAiSaveKey,
          onTestKey: widget.onAiTestKey,
          onOpenAiStudio: widget.onOpenAiStudio,
        ),
        const SizedBox(height: 16),
        PixelCard(
          child: Text(
            'More settings — water goal, glass size, your name — arrive here later.',
            style: AppTypography.cozy(12, color: Palette.cocoaSoft),
          ),
        ),
      ],
    );
  }
}

/// Gemini API key card: locked (no key) state with explainer + AI Studio
/// link + paste field, and a saved state with test-connection + edit.
/// The key lives in secure storage (Keystore-backed), never in sqlite.
class AiKeyCard extends StatefulWidget {
  const AiKeyCard({
    super.key,
    required this.hasKey,
    this.onSaveKey,
    this.onTestKey,
    this.onOpenAiStudio,
  });

  final bool hasKey;
  final Future<void> Function(String)? onSaveKey;
  final Future<AiResult> Function()? onTestKey;
  final VoidCallback? onOpenAiStudio;

  @override
  State<AiKeyCard> createState() => _AiKeyCardState();
}

class _AiKeyCardState extends State<AiKeyCard> {
  late final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  bool _editing = false; // field visible?
  bool _saving = false;
  bool _testing = false;
  bool _savedOnce = false;
  AiResult? _result;

  @override
  void initState() {
    super.initState();
    _editing = !widget.hasKey;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    setState(() => _saving = true);
    await widget.onSaveKey?.call(key);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedOnce = true;
      _editing = false;
      _controller.clear();
      _result = null;
    });
  }

  Future<void> _test() async {
    final tester = widget.onTestKey;
    if (tester == null) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    final result = await tester();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PixelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gemini · ${kGeminiModel.replaceAll('gemini-', '')}',
                  style: AppTypography.cozy(14, color: Palette.cocoa),
                ),
              ),
              Text(
                widget.hasKey ? 'Saved ✓' : 'Not set',
                style: AppTypography.cozy(
                  11,
                  color: widget.hasKey ? Palette.skyDeep : Palette.blushDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Explainer + key source link
          GestureDetector(
            onTap: widget.onOpenAiStudio,
            child: Text(
              'Free key from Google AI Studio:\n$kAiStudioUrl',
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Palette.peachDeep,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Key field (visible while not saved or while editing)
          if (_editing) ...[
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Paste your Gemini API key',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
          ],
          // Action row
          Row(
            children: [
              Expanded(
                child: Text(
                  _statusLine(),
                  style: AppTypography.cozy(
                    11,
                    color: _result == null
                        ? (_savedOnce ? Palette.skyDeep : Palette.cocoaSoft)
                        : (_result!.ok ? Palette.skyDeep : Palette.blushDeep),
                  ),
                ),
              ),
              if (_editing) PixelButton(label: _saving ? 'Saving…' : 'Save', onTap: _save),
            ],
          ),
          if (!_editing) ...[
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                PixelButton(label: 'Edit key', onTap: () {
                  setState(() {
                    _editing = true;
                    _result = null;
                    _savedOnce = false;
                  });
                }),
                PixelButton(
                  label: _testing ? 'Testing…' : 'Test connection',
                  onTap: _testing ? null : _test,
                ),
              ],
            ),
          ],
          // Test result detail
          if (_result != null) ...[
            const SizedBox(height: 8),
            Text(
              _result!.ok
                  ? '✓ Works — Gemini replied'
                  : 'Did not work: ${_result!.detail}',
              style: AppTypography.cozy(
                12,
                color: _result!.ok ? Palette.skyDeep : Palette.blushDeep,
              ),
            ),
          ],
          // Model reply preview (success only, collapsed)
          if (_result != null && _result!.ok) ...[
            const SizedBox(height: 6),
            Text(
              '"${_result!.detail}"',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.cozy(11, color: Palette.cocoaSoft),
            ),
          ],
        ],
      ),
    );
  }

  String _statusLine() {
    if (_testing) return 'Asking Gemini…';
    if (_result != null) return '';
    if (_savedOnce) return 'Saved in secure storage ✓';
    if (widget.hasKey) return 'Key stored securely on this phone.';
    return 'Paste the key, then tap Save.';
  }
}
