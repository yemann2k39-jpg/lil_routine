import 'package:flutter/material.dart';

import 'core/data/settings_repository.dart';
import 'core/db/app_database.dart';
import 'core/notifications/reminder_service.dart';
import 'core/theme/theme.dart';
import 'features/home/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LilRoutineApp());
  // Best-effort: re-apply stored reminder settings after every start so
  // the schedule always matches the settings table. Never blocks launch.
  _applyStoredReminders();
}

Future<void> _applyStoredReminders() async {
  try {
    final db = await AppDatabase.instance();
    final settings = SettingsRepository(db);
    await ReminderService.applyStored(
      enabled: await settings.reminderEnabled(),
      minutes: await settings.reminderMinutes(),
    );
  } catch (_) {
    // Notifications are optional; the app must launch without them.
  }
}

class LilRoutineApp extends StatelessWidget {
  const LilRoutineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LilRoutine',
      debugShowCheckedModeBanner: false,
      theme: buildLilRoutineTheme(),
      home: const HomeScreen(),
    );
  }
}
