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
import '../playback/active_mode_binding.dart';
import '../../l10n/runtime_copy.dart';

/// Payload attached to scheduled alarm notifications.
const scheduleAlarmPayload = 'schedule_alarm';
const activeStopActionId = 'stop_active';

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
  static const String _prayerChannelId = 'whisperback_prayer';

  /// Plugin handle for advanced features (prayer notification scheduling, etc.).
  FlutterLocalNotificationsPlugin get plugin => _plugin;

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (e) {
      // Use device UTC offset instead of pure UTC (critical for AU/US/EU clients).
      if (kDebugMode) {
        debugPrint('Timezone lookup failed, using offset fallback: $e');
      }
      _setLocalFromDeviceOffset();
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
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _prayerChannelId,
        'Prayer times',
        description: 'Adhan reminders at each prayer time.',
        importance: Importance.high,
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

  /// Returns true when the app was opened from a scheduled-alarm notification.
  Future<bool> launchedFromScheduleAlarm() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return false;
    return details!.notificationResponse?.payload == scheduleAlarmPayload;
  }

  static void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId == activeStopActionId) {
      unawaited(ActiveModeBinding.instance.stopActive());
      unawaited(instance.cancelActiveOngoing());
      return;
    }
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
    if (whisperAudioHandler.isPlayingClip) return;
    if (!whisperAudioHandler.shouldUseFlutterActiveNotification) return;
    final copy = RuntimeCopy.l10n;
    final body = upcomingSummary ??
        nextUpcoming ??
        (scheduleCount > 0
            ? copy.notificationSchedulesArmed(scheduleCount)
            : copy.notificationActiveBodyIdle);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _statusChannelId,
        copy.nowPlaying,
        channelDescription: copy.notificationActiveBodyIdle,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
        onlyAlertOnce: false,
        styleInformation: upcomingSummary != null
            ? BigTextStyleInformation(
                upcomingSummary,
                contentTitle: copy.notificationActiveTitle,
                summaryText: nextUpcoming,
              )
            : null,
        category: AndroidNotificationCategory.status,
        actions: [
          AndroidNotificationAction(
            activeStopActionId,
            copy.stop,
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
    );
    await _plugin.show(_ongoingId, copy.notificationActiveTitle, body, details);
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
    final copy = RuntimeCopy.l10n;
    final body = subtitle ?? copy.tapToOpenApp;
    await _plugin.show(
      _ongoingId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _nowPlayingChannelId,
          copy.nowPlaying,
          channelDescription: copy.tapToOpenApp,
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
    final copy = RuntimeCopy.l10n;
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
          body: copy.notificationScheduledReady(name),
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

  /// Fallback when [FlutterTimezone] cannot resolve IANA id (some OEM builds).
  void _setLocalFromDeviceOffset() {
    final offsetSeconds = DateTime.now().timeZoneOffset.inSeconds;
    tz.setLocalLocation(
      tz.Location(
        'DeviceOffset',
        [0],
        [0],
        [tz.TimeZone(offsetSeconds, isDst: false, abbreviation: 'LOCAL')],
      ),
    );
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
