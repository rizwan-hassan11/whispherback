import '../database/database_helper.dart';

class PrayerSettings {
  const PrayerSettings({
    required this.calculationMethod,
    required this.madhab,
    required this.useGps,
    this.manualCity,
    this.playAdhan = true,
  });

  final String calculationMethod;
  final String madhab;
  final bool useGps;
  final String? manualCity;
  final bool playAdhan;

  PrayerSettings copyWith({
    String? calculationMethod,
    String? madhab,
    bool? useGps,
    String? manualCity,
    bool? playAdhan,
  }) {
    return PrayerSettings(
      calculationMethod: calculationMethod ?? this.calculationMethod,
      madhab: madhab ?? this.madhab,
      useGps: useGps ?? this.useGps,
      manualCity: manualCity ?? this.manualCity,
      playAdhan: playAdhan ?? this.playAdhan,
    );
  }
}

class PrayerRepository {
  PrayerRepository(this._db);

  final DatabaseHelper _db;

  Future<PrayerSettings> getSettings() async {
    final db = await _db.database;
    final rows = await db.query('prayer_settings', where: 'id = 1');
    if (rows.isEmpty) {
      return const PrayerSettings(
        calculationMethod: 'Karachi',
        madhab: 'Shafi',
        useGps: true,
      );
    }
    final row = rows.first;
    return PrayerSettings(
      calculationMethod: row['calculation_method']! as String,
      madhab: row['madhab']! as String,
      useGps: (row['use_gps'] as int) == 1,
      manualCity: row['manual_city'] as String?,
      playAdhan: ((row['play_adhan'] as int?) ?? 1) == 1,
    );
  }

  Future<void> saveSettings(PrayerSettings settings) async {
    final db = await _db.database;
    await db.update(
      'prayer_settings',
      {
        'calculation_method': settings.calculationMethod,
        'madhab': settings.madhab,
        'use_gps': settings.useGps ? 1 : 0,
        'manual_city': settings.manualCity,
        'play_adhan': settings.playAdhan ? 1 : 0,
      },
      where: 'id = 1',
    );
  }
}
