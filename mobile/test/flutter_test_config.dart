import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Enables SQLite in VM unit/widget tests (Windows/Linux/macOS dev machines).
///
/// We also redirect `getDatabasesPath()` to a per-isolate temp directory so
/// parallel test files don't fight over `.dart_tool/.../whisperback.db` —
/// on Windows that path is held by another isolate and `File.delete()` fails
/// with `OS Error 32` ("file in use"), making the suite flaky.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final perIsolateDbDir =
      Directory.systemTemp.createTempSync('whisperback_dbs_');
  // Redirect the default databases path for the *whole* isolate so any code
  // path that calls `getDatabasesPath()` (including app + repository code
  // under test) lands in this isolate's private dir.
  await databaseFactory.setDatabasesPath(perIsolateDbDir.path);
  await testMain();
}
