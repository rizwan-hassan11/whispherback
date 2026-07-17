import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime permission status for scheduling on Android 7–16.
class AndroidSchedulingPermissions {
  const AndroidSchedulingPermissions({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
    required this.batteryUnrestricted,
  });

  final bool notificationsGranted;
  final bool exactAlarmsGranted;
  final bool batteryUnrestricted;

  bool get schedulingReady => notificationsGranted && exactAlarmsGranted;

  bool get fullyReady => schedulingReady && batteryUnrestricted;
}

/// Requests permissions needed for reliable scheduled whispers on modern Android.
///
/// Safe to call on every cold start and when the app returns to foreground.
Future<AndroidSchedulingPermissions> ensureAndroidSchedulingPermissions({
  bool requestBattery = false,
}) async {
  if (!Platform.isAndroid) {
    return const AndroidSchedulingPermissions(
      notificationsGranted: true,
      exactAlarmsGranted: true,
      batteryUnrestricted: true,
    );
  }

  var notificationsGranted = true;
  var exactAlarmsGranted = true;

  // Android 13+ (API 33): POST_NOTIFICATIONS
  final notificationStatus = await Permission.notification.status;
  if (!notificationStatus.isGranted) {
    final result = await Permission.notification.request();
    notificationsGranted = result.isGranted;
  }

  // Android 12+ (API 31): exact alarm scheduling
  final alarmStatus = await Permission.scheduleExactAlarm.status;
  if (!alarmStatus.isGranted) {
    final result = await Permission.scheduleExactAlarm.request();
    exactAlarmsGranted = result.isGranted || result.isLimited;
  }

  var batteryUnrestricted = true;
  if (requestBattery) {
    batteryUnrestricted = await _requestBatteryExemption();
  } else {
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    batteryUnrestricted = batteryStatus.isGranted;
  }

  if (kDebugMode) {
    debugPrint(
      'Android scheduling permissions: '
      'notifications=$notificationsGranted '
      'exactAlarms=$exactAlarmsGranted '
      'batteryUnrestricted=$batteryUnrestricted',
    );
  }

  return AndroidSchedulingPermissions(
    notificationsGranted: notificationsGranted,
    exactAlarmsGranted: exactAlarmsGranted,
    batteryUnrestricted: batteryUnrestricted,
  );
}

/// Asks the user to exempt WhisperBack from battery optimization (Samsung, Xiaomi, etc.).
Future<bool> requestBatteryExemption() async {
  if (!Platform.isAndroid) return true;
  return _requestBatteryExemption();
}

/// SharedPreferences key that records we've asked for battery exemption once.
const _batteryPromptedKey = 'battery_exemption_prompted_v1';

/// Requests battery exemption **at most once** across the app's lifetime.
///
/// Requesting `ignoreBatteryOptimizations` opens a system settings screen on
/// many OEMs — Samsung One UI / Xiaomi MIUI in particular route it to the
/// "App battery usage" page. On those OEMs the permission status keeps
/// reading as *denied* even AFTER the user allows background usage, so an
/// unconditional request on every cold start re-opens that screen. When a
/// scheduled alarm cold-starts the app, that pops the settings screen
/// mid-playback and the clip pauses — exactly the QA report
/// ("schedule plays a few seconds, then jumps to App battery usage, which
/// already shows background usage ON"). Persisting a one-shot flag guarantees
/// we only ever ask on the first eligible launch; afterwards the user manages
/// it from the in-app Battery guide / system settings.
Future<bool> requestBatteryExemptionOnce() async {
  if (!Platform.isAndroid) return true;
  final status = await Permission.ignoreBatteryOptimizations.status;
  if (status.isGranted) return true;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_batteryPromptedKey) == true) return false;
  await prefs.setBool(_batteryPromptedKey, true);
  final result = await Permission.ignoreBatteryOptimizations.request();
  return result.isGranted;
}

Future<bool> _requestBatteryExemption() async {
  final status = await Permission.ignoreBatteryOptimizations.status;
  if (status.isGranted) return true;
  final result = await Permission.ignoreBatteryOptimizations.request();
  return result.isGranted;
}
