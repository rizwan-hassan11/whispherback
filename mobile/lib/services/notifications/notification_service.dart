import 'dart:async';
import 'dart:ui' show Color;

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

    // Notification small-icon MUST be a flat white silhouette on a
    // transparent background; the OS applies the channel `notificationColor`
    // at paint time. Using `@mipmap/ic_launcher` (the full-colour launcher)
    // caused Android to silhouette it into a featureless white circle —
    // the QA report "notification icon is just a white circle, not the
    // WhisperBack logo". `@drawable/ic_notification` is our hand-crafted
    // monochrome W silhouette and renders correctly on every OEM.
    const androidInit = AndroidInitializationSettings('ic_notification');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
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
        // Round 16: bumped from `low` to `defaultImportance`. The user
        // reported "notification bar appears and disappears even when
        // Active is ON". `Importance.low` notifications get auto-
        // collapsed by Samsung One UI 6 / MIUI / Funtouch and were
        // disappearing entirely when the activity was destroyed. At
        // `defaultImportance` the OS keeps the status-bar icon and
        // notification card visible reliably across all OEMs we
        // tested. `playSound: false` + `enableVibration: false` keep
        // the bump silent so the user is never annoyed.
        importance: Importance.defaultImportance,
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
    try {
      await android?.requestNotificationsPermission();
    } catch (_) {}
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
    try {
      // Android 14+: full-screen intent permission is required for
      // schedule-alarm notifications to auto-launch the activity from
      // screen-off. Without this permission, the alarm only posts a
      // notification and the user has to tap it manually — the QA
      // report "scheduled audio doesn't play when the screen is off"
      // is exactly this. We request it eagerly so even cold-installs
      // get the chance to opt in.
      await android?.requestFullScreenIntentPermission();
    } catch (_) {}

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
    // Round 16: "Play now" alarm action — same wakeup behaviour as
    // tapping the notification body; the engine's `fireNow` pass
    // will start the matching schedule.
    if (response.actionId == 'schedule_play_now' ||
        response.payload == scheduleAlarmPayload) {
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
    // Skip ONLY when an actual clip is playing — the audio_service media
    // notification carries that case. Previously we also skipped whenever
    // `shouldUseFlutterActiveNotification` returned false (i.e. the silent
    // keep-alive card was up), which on many OEMs left the user with the
    // foreground-service binding alive but NO visible notification: the
    // audio_service silent card is suppressed on Samsung / Vivo when the
    // metadata says "WhisperBack is active" with no clip title. We now
    // ALWAYS render the WhisperBack ongoing card when Active is on and
    // no clip is playing, so the user has a permanent visual cue.
    if (whisperAudioHandler.isPlayingClip) return;
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
        // Round 16: matches the channel-level bump. OEMs that ignore
        // the channel-level setting fall back to this per-notification
        // value, so we set both to be safe.
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
        // True so periodic re-posts (every 30s from the engine tick and
        // every app resume) never produce a sound or peek/heads-up alert
        // even on OEMs that ignore the channel's `playSound: false`.
        onlyAlertOnce: true,
        // Explicit silhouette icon — same one the channel default falls
        // back to, but pinning it here too defends against OEMs that
        // ignore the channel-level icon in favour of the per-notification
        // override.
        icon: 'ic_notification',
        color: const Color(0xFF2E8BFF),
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
  ///
  /// CRITICAL throttling: we only register the **next 12 slots per schedule
  /// across the next 48 hours** — never the entire weekly grid. Previous
  /// versions scheduled every interval-grid slot for every enabled
  /// schedule, capped at 400 globally. That cap was reached easily by a
  /// 3-minute interval (480 slots per day × 7 days = 3360 candidates),
  /// and each `zonedSchedule` is a synchronous Android binder call
  /// (~50 ms). Scheduling 400 alarms serially took 20+ seconds — long
  /// enough for the OS to kill the activity with an ANR, which is what
  /// the QA report "app crashed on schedule save" was caused by. The
  /// in-process engine re-fires every 5 seconds, so the OS alarm is
  /// only needed as a **wake-up trigger** when the engine has been
  /// throttled by Doze. 12 next-up alarms per schedule (typically a
  /// few hours of coverage at 3-minute intervals) is more than enough
  /// for that role.
  /// Last-applied schedule fingerprint. We rebuild the AlarmManager
  /// entries only when the schedule SET (id + start + end + interval +
  /// daysMask + enabled + alarmEnabled) actually changes. Without this
  /// the engine's 10-second tick re-registers up to 60 alarms × 50 ms
  /// each = ~3 seconds of binder calls every tick, which on Samsung
  /// One UI 6 occasionally trips the OS's ANR watcher and starves the
  /// notification panel of refresh cycles (the QA report "notification
  /// disappears intermittently"). Caching by fingerprint keeps the
  /// alarms-up-to-date semantics while collapsing redundant work to
  /// near-zero on idle ticks.
  String? _lastSyncedFingerprint;
  bool _lastSyncedActive = false;

  static String _fingerprintFor(List<PlaybackSchedule> schedules) {
    final parts = <String>[];
    for (final s in schedules) {
      if (!s.enabled || !s.alarmEnabled) continue;
      parts.add(
        '${s.id}|${s.startTime.toIso8601String()}|'
        '${s.endTime?.toIso8601String() ?? ""}|'
        '${s.intervalMinutes}|${s.daysMask}|'
        '${s.playlistDurationMs}',
      );
    }
    parts.sort();
    return parts.join(';');
  }

  Future<void> syncSchedules(
    List<PlaybackSchedule> schedules, {
    required bool active,
  }) async {
    await init();
    final fingerprint = _fingerprintFor(schedules);
    if (_lastSyncedFingerprint == fingerprint &&
        _lastSyncedActive == active) {
      return;
    }
    _lastSyncedFingerprint = fingerprint;
    _lastSyncedActive = active;
    await _cancelAllScheduleAlarms();
    if (!active) return;

    var id = _scheduleBase;
    final copy = RuntimeCopy.l10n;
    final now = DateTime.now();
    // Round 16: aggressive caps + per-call event-loop yield so the
    // save flow NEVER blocks the UI thread long enough to ANR.
    //   • 3 alarms/schedule (was 12) — these are OS-level wake-ups
    //     that fire when the engine has been throttled by Doze. The
    //     engine's 5-second in-process tick is the real source of
    //     truth; OS alarms only need to cover the "device went to
    //     deep doze" case, for which 3 next-up alarms is plenty.
    //   • 20 global cap (was 60) — at ~100ms per binder call worst
    //     case that's 2 seconds total even when nothing is cached.
    //   • 12-hour horizon (was 48h) — same reasoning; we only need
    //     the very next-up alarms.
    //   • Per-iteration `await Future.delayed(Duration.zero)` so the
    //     event loop pumps between binder calls and the UI thread
    //     can paint a frame without being starved.
    final horizon = now.add(const Duration(hours: 12));
    const maxAlarmsPerSchedule = 3;
    const maxAlarmsGlobal = 20;

    for (final schedule in schedules) {
      if (!schedule.enabled || !schedule.alarmEnabled) continue;
      var perScheduleCount = 0;
      for (final slot in ScheduleFireHelper.intervalAlarmSlots(schedule)) {
        if (perScheduleCount >= maxAlarmsPerSchedule) break;
        if (id >= _scheduleBase + maxAlarmsGlobal) return;
        final when = _nextWeekdayTime(slot.weekday, slot.hour, slot.minute);
        if (when.isAfter(tz.TZDateTime.from(horizon, when.location))) {
          continue;
        }
        final name = slot.label.isEmpty ? 'WhisperBack' : slot.label;
        try {
          await _scheduleWeekly(
            id: id,
            when: when,
            title: 'WhisperBack',
            body: copy.notificationScheduledReady(name),
            payload: scheduleAlarmPayload,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('syncSchedules: zonedSchedule failed for $when: $e');
          }
        }
        id++;
        perScheduleCount++;
        // Yield to the event loop after EVERY binder call so the
        // UI thread gets a chance to paint frames between scheduling
        // calls. Without this, a save with 20 alarms still serialised
        // all 20 calls in one microtask burst and the user saw the
        // save button stuck.
        await Future<void>.delayed(Duration.zero);
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
    // Round 16: added a clear "Play now" action so the user has a one-
    // tap path to launch the app from the alarm notification — even
    // when the OS killed the process between the alarm being set and
    // the alarm firing. `showsUserInterface: true` ensures the tap
    // launches the activity (which auto-revives the Dart isolate and
    // resumes the engine, which then fires the scheduled clip).
    final copy = RuntimeCopy.l10n;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alarmChannelId,
        'Scheduled whispers',
        channelDescription: 'Alerts when a scheduled whisper is due.',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        icon: 'ic_notification',
        color: const Color(0xFF2E8BFF),
        actions: [
          AndroidNotificationAction(
            'schedule_play_now',
            copy.play,
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Scheduled alarm $id exact-schedule failed: $e');
      }
      try {
        // Exact alarms may be disallowed (Android 14+); try inexact instead.
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
      } catch (e2) {
        // Best-effort: a single alarm slot must never break the rest of the
        // sync or surface as a save failure to the user. Foreground ticking
        // still drives playback even when the OS denies background alarms.
        if (kDebugMode) {
          debugPrint('Scheduled alarm $id inexact-fallback failed: $e2');
        }
      }
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
      try {
        await _plugin.cancel(id);
      } catch (_) {}
    }
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  @visibleForTesting
  bool get isReady => _ready;
}
