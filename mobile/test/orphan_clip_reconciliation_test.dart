import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages — transitive deps from path_provider for testing
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages — transitive dep
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whisperback/data/database/database_helper.dart';
import 'package:whisperback/data/repositories/clip_repository.dart';
import 'package:whisperback/domain/entities/audio_clip.dart';
import 'package:whisperback/services/audio/audio_services.dart';

/// Verifies that `reconcileOrphanClipFiles` deletes files left behind by
/// process-death mid-recording or import-create races while preserving every
/// file referenced by the DB.
///
/// This is the safety net behind the "I recorded and the app crashed and now
/// I have ghost files I can't see" failure mode.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docDir);
  final String docDir;
  @override
  Future<String?> getApplicationDocumentsPath() async => docDir;
}

void main() {
  late Directory tempDocs;
  late Directory clipsDir;
  late DatabaseHelper db;
  late ClipRepository repo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDocs = await Directory.systemTemp.createTemp('whisperback_orphan_');
    clipsDir = Directory(p.join(tempDocs.path, 'clips'));
    await clipsDir.create();
    PathProviderPlatform.instance = _FakePathProvider(tempDocs.path);
    db = DatabaseHelper.instance;
    await db.close();
    final dbPath = await getDatabasesPath();
    final dbFile = File(p.join(dbPath, 'whisperback.db'));
    if (await dbFile.exists()) await dbFile.delete();
    repo = ClipRepository(db);
    await db.database;
  });

  tearDown(() async {
    await db.close();
    await tempDocs.delete(recursive: true);
  });

  test('orphan .m4a files with no DB row are removed', () async {
    final orphan = File(p.join(clipsDir.path, 'orphan.m4a'));
    await orphan.writeAsBytes([1, 2, 3]);
    expect(await orphan.exists(), isTrue);
    await reconcileOrphanClipFiles(repo);
    expect(await orphan.exists(), isFalse);
  });

  test('files referenced by the DB are preserved', () async {
    final kept = File(p.join(clipsDir.path, 'kept.m4a'));
    await kept.writeAsBytes([1, 2, 3]);
    await repo.create(
      title: 'Saved',
      filePath: kept.path,
      durationMs: 1000,
      source: ClipSource.recorded,
    );
    await reconcileOrphanClipFiles(repo);
    expect(await kept.exists(), isTrue);
  });

  test('non-audio files in the clips dir are left untouched (defensive)',
      () async {
    final foreign = File(p.join(clipsDir.path, 'readme.txt'));
    await foreign.writeAsBytes([1, 2, 3]);
    await reconcileOrphanClipFiles(repo);
    expect(await foreign.exists(), isTrue);
  });

  test('a missing clips/ directory is handled gracefully (no throw)', () async {
    await clipsDir.delete(recursive: true);
    await reconcileOrphanClipFiles(repo); // should not throw
  });
}
