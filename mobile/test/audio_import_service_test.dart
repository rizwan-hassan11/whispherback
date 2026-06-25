import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whisperback/data/database/database_helper.dart';
import 'package:whisperback/data/repositories/clip_repository.dart';
import 'package:whisperback/services/audio/audio_services.dart'
    show AudioImportService;

/// Reproduces the Samsung / Android 10+ scoped-storage scenario the client hit:
/// the file picker returns a content URI with a null path. The import service
/// must accept bytes as a fallback and either succeed (valid file) or surface
/// a clear error (invalid argument) — never silently no-op.
void main() {
  late DatabaseHelper db;
  late ClipRepository clips;
  late AudioImportService importer;

  setUp(() async {
    db = DatabaseHelper.instance;
    await db.close();
    final dbPath = await getDatabasesPath();
    final file = File(p.join(dbPath, 'whisperback.db'));
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    clips = ClipRepository(db);
    importer = AudioImportService(clips);
    await db.database;
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'rejects unsupported extensions early with a friendly ArgumentError',
    () async {
      // Synchronous-enough: fires before path_provider is touched, so it
      // works even on dev machines without the Android plugin.
      expect(
        () async {
          await for (final _ in importer.importFile('/tmp/song.wav', 'song')) {}
        },
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test(
    'rejects null path with no bytes — never silently no-ops',
    () async {
      expect(
        () async {
          await for (final _ in importer.importFile(
            null,
            'mystery',
            fileName: 'mystery.mp3',
          )) {}
        },
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test(
    'rejects empty bytes — never silently no-ops',
    () async {
      expect(
        () async {
          await for (final _ in importer.importFile(
            null,
            'empty',
            fileName: 'empty.mp3',
            sourceBytes: Uint8List(0),
          )) {}
        },
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  // Note: the bytes-copy and file-copy branches both invoke `just_audio` to
  // probe the duration of the saved clip. That plugin has no host-only
  // implementation, so end-to-end decode-and-persist runs are intentionally
  // covered by the on-device matrix (Samsung A-series Android 12, Pixel
  // 6/7/8 Android 14/15, Galaxy S24 Android 16). Here we lock in the
  // control-flow contracts that *don't* depend on a working decoder — the
  // ones that have actually regressed in production reports.
}
