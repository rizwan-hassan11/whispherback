import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/repositories/prayer_repository.dart';

class PrayerService {
  PrayerService(this._repository);

  final PrayerRepository _repository;

  /// Last resolved GPS coordinates, reused when a fresh fix isn't available.
  Coordinates? _cachedCoords;

  Future<bool> adhanEnabled() async {
    final settings = await _repository.getSettings();
    return settings.playAdhan;
  }

  Future<PrayerWindow?> getCurrentPrayerWindow() async {
    final settings = await _repository.getSettings();
    Coordinates? coords;

    if (settings.useGps) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      // Prefer an instant last-known fix; only fall back to a fresh fix with a
      // short timeout so prayer checks never stall playback for seconds.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          coords = Coordinates(last.latitude, last.longitude);
          _cachedCoords = coords;
        } else {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 5),
            ),
          );
          coords = Coordinates(pos.latitude, pos.longitude);
          _cachedCoords = coords;
        }
      } catch (_) {
        // Use the last cached fix, or a sensible default (Karachi).
        coords = _cachedCoords ?? Coordinates(31.5204, 74.3587);
      }
    } else {
      coords = Coordinates(31.5204, 74.3587);
    }

    final params = _paramsForMethod(settings.calculationMethod);
    params.madhab = settings.madhab == 'Hanafi' ? Madhab.hanafi : Madhab.shafi;

    final prayers = PrayerTimes.today(coords, params);
    final now = DateTime.now();

    final entries = <PrayerWindow>[
      _window('Fajr', prayers.fajr),
      _window('Dhuhr', prayers.dhuhr),
      _window('Asr', prayers.asr),
      _window('Maghrib', prayers.maghrib),
      _window('Isha', prayers.isha),
    ];

    for (final w in entries) {
      if (now.isAfter(w.start) && now.isBefore(w.end)) return w;
    }
    return null;
  }

  PrayerWindow _window(String name, DateTime time) {
    return PrayerWindow(name, time, time.add(const Duration(minutes: 20)));
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

class PrayerWindow {
  PrayerWindow(this.name, this.start, this.end);
  final String name;
  final DateTime start;
  final DateTime end;
}
