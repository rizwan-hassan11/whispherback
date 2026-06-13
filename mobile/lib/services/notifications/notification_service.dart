import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/playback_schedule.dart';
import '../audio/whisper_audio_handler.dart';
import '../scheduler/schedule_engine_binding.dart';
import '../scheduler/schedule_fire_helper.dart';

/// Payload attached to scheduled alarm notifications.
const scheduleAlarmPayload = 'schedule_alarm';

/// Handles scheduled alarm notifications that fire when the app is closed.
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
  static const String _nowPlayingChannelId = 'whisperback_now_playing';
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
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
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
        _nowPlayingChannelId,
        'Now playing',
        description: 'Shows the currently playing whisper with controls.',
        importance: Importance.defaultImportance,
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

  static void _onNotificationResponse(NotificationResponse response) {
    if (response.payload == scheduleAlarmPayload) {
      unawaited(ScheduleEngineBinding.instance.fireNow());
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    if (response.payload == scheduleAlarmPayload) {
      // Background isolate cannot reach the engine; opening the app resumes it.
    }
  }

  // ── Legacy status notification (deprecated — use audio_service media card) ─

  Future<void> showActiveOngoing({
    int scheduleCount = 0,
    String? nextUpcoming,
    String? upcomingSummary,
  }) async {
    await init();
    if (whisperAudioHandler.occupiesMediaNotification) return;
    final body = upcomingSummary ??
        nextUpcoming ??
        (scheduleCount > 0
            ? '$scheduleCount schedule(s) armed · whispers will play automatically'
            : 'Listening for your scheduled whispers');
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _statusChannelId,
        'Active status',
        channelDescription: 'Shows while WhisperBack is active.',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
        onlyAlertOnce: false,
        styleInformation: upcomingSummary != null
            ? BigTextStyleInformation(
                upcomingSummary,
                contentTitle: 'WhisperBack is active',
                summaryText: nextUpcoming,
              )
            : null,
        category: AndroidNotificationCategory.status,
      ),
    );
    await _plugin.show(_ongoingId, 'WhisperBack is active', body, details);
  }

  Future<void> cancelActiveOngoing() async {
    await init();
    await _plugin.cancel(_ongoingId);
  }

  /// Visible now-playing line while a clip plays (complements audio_service).
  Future<void> showNowPlaying({
    required String title,
    String? subtitle,
  }) async {
    await init();
    final body = subtitle ?? 'Tap to open WhisperBack';
    await _plugin.show(
      _ongoingId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _nowPlayingChannelId,
          'Now playing',
          channelDescription:
              'Shows the currently playing whisper with controls.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          onlyAlertOnce: false,
          category: AndroidNotificationCategory.transport,
        ),
      ),
    );
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
      for (final slot in ScheduleFireHelper.intervalAlarmSlots(schedule)) {
        if (id >= _scheduleBase + 400) return;
        final when = _nextWeekdayTime(slot.weekday, slot.hour, slot.minute);
        final name = slot.label.isEmpty ? 'WhisperBack' : slot.label;
        await _scheduleWeekly(
          id: id,
          when: when,
          title: 'WhisperBack',
          body: '“$name” is ready to play',
          payload: scheduleAlarmPayload,
        );
        id++;
      }
    }
  }

  Future<void> _scheduleWeekly({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    String? payload,
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
        payload: payload,
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
        payload: payload,
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
