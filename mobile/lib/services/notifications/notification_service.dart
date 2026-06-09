import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/playback_schedule.dart';

/// Handles all system notifications: a persistent "active" status notification
/// while the master toggle is ON, and exact scheduled alarms that fire even
/// when the app is closed/killed (Android) or backgrounded (iOS).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  // Notification id space.
  static const int _ongoingId = 1; // persistent "active" notification
  static const int _scheduleBase = 1000; // scheduled alarms occupy 1000+

  static const String _statusChannelId = 'whisperback_status';
  static const String _alarmChannelId = 'whisperback_alarms';

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      // Fall back to UTC if the platform timezone can't be resolved.
    }

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
    );

    await _createChannels();
    _ready = true;
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _statusChannelId,
        'Active status',
        description: 'Shows while WhisperBack is active.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _alarmChannelId,
        'Scheduled whispers',
        description: 'Alerts when a scheduled whisper is due.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// Ask for runtime permission (Android 13+, iOS). Safe to call repeatedly.
  Future<void> requestPermissions() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  // ── Persistent "active" notification ──────────────────────────────────────

  Future<void> showActiveOngoing({int scheduleCount = 0}) async {
    await init();
    final body = scheduleCount > 0
        ? '$scheduleCount schedule(s) armed · whispers will play automatically'
        : 'Listening for your scheduled whispers';
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _statusChannelId,
        'Active status',
        channelDescription: 'Shows while WhisperBack is active.',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
        onlyAlertOnce: true,
        category: AndroidNotificationCategory.status,
      ),
    );
    await _plugin.show(_ongoingId, 'WhisperBack is active', body, details);
  }

  Future<void> cancelActiveOngoing() async {
    await init();
    await _plugin.cancel(_ongoingId);
  }

  // ── Scheduled alarms (fire when app is killed) ────────────────────────────

  /// Re-arms all scheduled-alarm notifications from the current schedules.
  /// Call after any schedule change or when the toggle turns ON.
  Future<void> syncSchedules(
    List<PlaybackSchedule> schedules, {
    required bool active,
  }) async {
    await init();
    await _cancelAllScheduleAlarms();
    if (!active) return;

    var id = _scheduleBase;
    for (final schedule in schedules) {
      if (!schedule.enabled || !schedule.alarmEnabled) continue;
      for (var weekday = 1; weekday <= 7; weekday++) {
        if ((schedule.daysMask & (1 << (weekday - 1))) == 0) continue;
        final when = _nextWeekdayTime(
          weekday,
          schedule.startTime.hour,
          schedule.startTime.minute,
        );
        await _scheduleWeekly(
          id: id,
          when: when,
          title: 'WhisperBack',
          body: schedule.playlistName.isEmpty
              ? 'A scheduled whisper is ready to play'
              : '“${schedule.playlistName}” is ready to play',
        );
        id++;
        if (id >= _scheduleBase + 400) return; // safety cap
      }
    }
  }

  Future<void> _scheduleWeekly({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alarmChannelId,
        'Scheduled whispers',
        channelDescription: 'Alerts when a scheduled whisper is due.',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
      ),
      iOS: DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (_) {
      // Exact alarms may be disallowed; fall back to inexact.
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  tz.TZDateTime _nextWeekdayTime(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> _cancelAllScheduleAlarms() async {
    for (var id = _scheduleBase; id < _scheduleBase + 400; id++) {
      await _plugin.cancel(id);
    }
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  @visibleForTesting
  bool get isReady => _ready;
}
