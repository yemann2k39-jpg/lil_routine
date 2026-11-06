import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local water reminders: a repeating cozy nudge on a user-chosen
/// interval (Settings page, LIL-11). Android-only for now.
class ReminderService {
  ReminderService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'water_reminders';
  static const _notificationId = 1;
  static const _platformChannel = MethodChannel('lilroutine/platform');

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// Asks for the Android 13+ POST_NOTIFICATIONS permission.
  /// Returns true when granted (or not needed).
  static Future<bool> _requestPermissionIfNeeded() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? true;
  }

  static Future<bool> _exactAlarmsAllowed() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.canScheduleExactNotifications() ?? false;
  }

  /// Whether the app may schedule exact alarms. On Android 12+ this is
  /// user-controlled ("Alarms & reminders" in system settings) and
  /// denied by default for targetSdk 33+.
  static Future<bool> canScheduleExact() => _exactAlarmsAllowed();

  /// Opens the system "Alarms & reminders" page so the user can grant
  /// exact alarms. Resolves when the user returns to the app.
  static Future<void> requestExactAlarmsPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
  }

  /// Whether the app is exempt from battery optimization. OEM battery
  /// managers (Samsung Freecess) freeze background apps otherwise, which
  /// queues reminder broadcasts forever — diagnosed on-device 2026-11-03.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _platformChannel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
    } on PlatformException {
      return true;
    }
  }

  /// Opens the system dialog asking the user to exempt the app from
  /// battery optimization.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _platformChannel.invokeMethod('requestIgnoreBatteryOptimizations');
    } on PlatformException {
      // Older/other platforms: nothing to do.
    }
  }

  /// Posts the reminder notification right now — used by the Settings
  /// "Test now" button so the user can confirm delivery without waiting.
  static Future<void> testNow() async {
    await _ensureInit();
    await _plugin.show(
      id: 2, // distinct from the scheduled reminder id
      title: 'LilRoutine',
      body: 'Time for a sip 💧 Lil Drop is getting thirsty!',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Water reminders',
          channelDescription: 'Cozy nudges to drink water',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  /// Re-applies stored reminder settings. Called on every app start so
  /// the schedule always matches the settings table.
  static Future<void> applyStored({
    required bool enabled,
    required int minutes,
  }) async {
    if (!enabled) {
      await disable();
      return;
    }
    await _ensureInit();
    await _schedule(minutes: minutes);
  }

  /// Enables reminders every [minutes]. Returns false when the user
  /// denied the notification permission (nothing is scheduled then).
  static Future<bool> enable({required int minutes}) async {
    await _ensureInit();
    final granted = await _requestPermissionIfNeeded();
    if (!granted) return false;
    await _schedule(minutes: minutes);
    return true;
  }

  static Future<void> disable() async {
    await _ensureInit();
    await _plugin.cancelAll();
  }

  static Future<void> _schedule({required int minutes}) async {
    await _plugin.cancelAll(); // one repeating notification, always fresh
    final exact = await _exactAlarmsAllowed();
    await _plugin.periodicallyShowWithDuration(
      id: _notificationId,
      title: 'LilRoutine',
      body: 'Time for a sip 💧 Lil Drop is getting thirsty!',
      repeatDurationInterval: Duration(minutes: minutes),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Water reminders',
          channelDescription: 'Cozy nudges to drink water',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
