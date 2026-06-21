import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whisperback/data/database/database_helper.dart';
import 'package:whisperback/data/repositories/prayer_repository.dart';

void main() {
  test('prayer settings round-trip with playAdhan default true', () async {
    // Use an in-memory DB through the public helper; clean the file path so
    // the test is isolated from any previous run.
    final dir = await getDatabasesPath();
    final dbPath = p.join(dir, 'whisperback.db');
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {}

    final repo = PrayerRepository(DatabaseHelper.instance);
    final initial = await repo.getSettings();
    expect(initial.playAdhan, isTrue);
    expect(initial.calculationMethod, 'Karachi');

    await repo.saveSettings(initial.copyWith(playAdhan: false));
    final updated = await repo.getSettings();
    expect(updated.playAdhan, isFalse);

    await repo.saveSettings(updated.copyWith(playAdhan: true));
    final restored = await repo.getSettings();
    expect(restored.playAdhan, isTrue);

    await DatabaseHelper.instance.close();
  });
}
