import 'dart:async';

import 'package:adhan/adhan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/repositories/prayer_repository.dart';
import '../../l10n/runtime_copy.dart';

/// Re-arms a small set of "prayer time" notifications for the next 24h so the
/// user is reminded at every prayer even if the app is killed. When the app is
/// open, [AdhanPlayer] plays the actual adhan voice; the notification is the
/// fallback when the OS won't keep our process alive.
class PrayerNotificationScheduler {
  PrayerNotificationScheduler({
    required FlutterLocalNotificationsPlugin plugin,
    required PrayerRepository prayerRepository,
  })  : _plugin = plugin,
        _prayer = prayerRepository;

  final FlutterLocalNotificationsPlugin _plugin;
  final PrayerRepository _prayer;

  static const int _baseId = 2000; // sits above schedule alarm range (1000+).
  static const int _slotCount = 70; // 14 days × 5 prayers — covers OS reboots
  static const int _daysAhead = 14;
  static const String channelId = 'whisperback_prayer';

  /// Re-arms upcoming prayer-time notifications. Independent of WhisperBack's
  /// Active toggle — adhan reminders are a standalone feature.
  Future<void> sync() async {
    await _cancelAll();

    final settings = await _prayer.getSettings();
    if (!settings.playAdhan) return;

    final coords = await _resolveCoords(settings);
    if (coords == null) return;

    final params = _paramsForMethod(settings.calculationMethod);
    params.madhab = settings.madhab == 'Hanafi' ? Madhab.hanafi : Madhab.shafi;

    final now = DateTime.now();
    final upcoming = <(_PrayerKey, DateTime)>[];

    for (var d = 0; d < _daysAhead; d++) {
      final day = now.add(Duration(days: d));
      final times = d == 0
          ? PrayerTimes.today(coords, params)
          : PrayerTimes(coords, DateComponents.from(day), params);
      upcoming.addAll([
        (_PrayerKey.fajr, times.fajr),
        (_PrayerKey.dhuhr, times.dhuhr),
        (_PrayerKey.asr, times.asr),
        (_PrayerKey.maghrib, times.maghrib),
        (_PrayerKey.isha, times.isha),
      ]);
    }

    final future = upcoming
        .where((e) => e.$2.isAfter(now))
        .take(_slotCount)
        .toList(growable: false);

    for (var i = 0; i < future.length; i++) {
      final entry = future[i];
      await _scheduleOne(
        id: _baseId + i,
        when: entry.$2,
        prayerName: entry.$1.label,
      );
    }
  }

  /// Back-compat alias retained while older call sites migrate.
  Future<void> syncForNext24h({required bool active}) => sync();

  Future<Coordinates?> _resolveCoords(PrayerSettings settings) async {
    if (!settings.useGps) {
      // Default to a sensible city; PrayerService uses Lahore — match that.
      return Coordinates(31.5204, 74.3587);
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return Coordinates(last.latitude, last.longitude);
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 5),
        ),
      );
      return Coordinates(pos.latitude, pos.longitude);
    } catch (e) {
      if (kDebugMode) debugPrint('Prayer scheduler GPS lookup failed: $e');
      return Coordinates(31.5204, 74.3587);
    }
  }

  Future<void> _scheduleOne({
    required int id,
    required DateTime when,
    required String prayerName,
  }) async {
    final tzWhen = tz.TZDateTime.from(when, tz.local);
    final copy = RuntimeCopy.l10n;
    final body = copy.prayerNotificationBody(prayerName);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Prayer times',
        channelDescription: 'Adhan reminders at each prayer time.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: 'ic_notification',
      ),
    );
    try {
      await _plugin.zonedSchedule(
        id,
        prayerName,
        body,
        tzWhen,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id,
        prayerName,
        body,
        tzWhen,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> _cancelAll() async {
    // Cancel the full reserved range so leftover IDs from earlier app versions
    // (which used a smaller slot count) are also cleared.
    for (var i = 0; i < _slotCount; i++) {
      try {
        await _plugin.cancel(_baseId + i);
      } catch (_) {}
    }
  }

  CalculationParameters _paramsForMethod(String method) {
    switch (method) {
      case 'MWL':
        return CalculationMethod.muslim_world_league.getParameters();
      case 'ISNA':
        return CalculationMethod.north_america.getParameters();
      case 'Umm al-Qura':
        return CalculationMethod.umm_al_qura.getParameters();
      case 'Egyptian':
        return CalculationMethod.egyptian.getParameters();
      default:
        return CalculationMethod.karachi.getParameters();
    }
  }
}

enum _PrayerKey { fajr, dhuhr, asr, maghrib, isha }

extension on _PrayerKey {
  String get label => switch (this) {
        _PrayerKey.fajr => 'Fajr',
        _PrayerKey.dhuhr => 'Dhuhr',
        _PrayerKey.asr => 'Asr',
        _PrayerKey.maghrib => 'Maghrib',
        _PrayerKey.isha => 'Isha',
      };
}
