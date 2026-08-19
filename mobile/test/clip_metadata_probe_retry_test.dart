// Round 37 — regression test for the QA report:
//
//   "After recording a new voice clip, the clip does not play on the
//   first attempt. Delete it, record it again, and the second recording
//   plays correctly on the first attempt."
//
// Root cause: `ClipRepository.backfillDuration`'s native
// `MediaMetadataRetriever` probe runs almost immediately after
// `AudioRecordingService.stopAndSave()` returns. A freshly-stopped
// recording's `.m4a` trailer can still be finalizing on disk at that
// instant, so the native probe can legitimately read a duration of 0 on
// the very first attempt. Before this fix, ANY native failure (including
// this transient "not flushed yet" case) fell straight through to the
// `just_audio` fallback probe — which is the exact "spin up a probe
// player and steal audio focus from the next real play() call" failure
// mode the native probe exists to avoid (see the Round 24 comments in
// this file and in `ClipMetadataProbe.kt`).
//
// The fix retries the native probe a couple of times with a short delay
// before giving up, so a transient "still flushing" 0 doesn't force the
// risky fallback. This test proves the retry loop actually runs (not
// just that the code exists) by mocking the native channel to fail
// twice then succeed, and asserting the repository ends up with the
// real duration WITHOUT ever needing the fallback.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whisperback/data/database/database_helper.dart';
import 'package:whisperback/data/repositories/clip_repository.dart';
import 'package:whisperback/domain/entities/audio_clip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.whisperback.clip_metadata');
  late DatabaseHelper helper;
  late ClipRepository repo;

  setUp(() async {
    helper = DatabaseHelper.instance;
    await helper.close();
    final dbPath = await getDatabasesPath();
    final file = File(p.join(dbPath, 'whisperback.db'));
    if (await file.exists()) await file.delete();
    repo = ClipRepository(helper);
    await helper.database;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await helper.close();
  });

  test(
      'backfillDuration retries the native probe on a transient 0 read '
      'instead of immediately falling through to the just_audio fallback',
      () async {
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      callCount++;
      expect(call.method, 'readDurationMs');
      // Simulate a recording whose container isn't fully flushed yet on
      // the first two probes, then succeeds on the third.
      if (callCount < 3) return 0;
      return 4200;
    });

    final clip = await repo.create(
      title: 'Fresh recording',
      filePath: '/tmp/fresh_recording.m4a',
      durationMs: 0,
      source: ClipSource.recorded,
    );

    await repo.backfillDuration(clip.id, clip.filePath);

    expect(callCount, 3,
        reason: 'The probe must be retried until it succeeds (up to the '
            'retry budget), not abandoned after the first 0 read.');
    final reloaded = await repo.getById(clip.id);
    expect(reloaded?.durationMs, 4200,
        reason: 'Once a retry succeeds, the real duration must land in '
            'the row — proving the risky just_audio fallback was never '
            'needed for this transient case.');
  });

  test(
      'the retry budget is a small, fixed number of attempts — not '
      'unbounded, and not just one shot', () {
    // The exhausted-retries-then-falls-through-to-just_audio path can't
    // be driven end-to-end here: constructing a real `AudioPlayer()` (the
    // fallback) isn't viable in the pure-VM test suite without the
    // platform plugin runtime — see the note in
    // clip_duration_backfill_test.dart. Pin the retry budget itself at
    // the source level instead.
    final src =
        File('lib/data/repositories/clip_repository.dart').readAsStringSync();
    expect(src, contains('_nativeProbeRetryDelays'),
        reason: 'A named retry-delay list makes the budget explicit and '
            'testable, instead of a magic loop count.');
    final listIdx = src.indexOf('_nativeProbeRetryDelays = [');
    expect(listIdx, greaterThanOrEqualTo(0));
    final listEnd = src.indexOf('];', listIdx);
    expect(listEnd, greaterThan(listIdx));
    final list = src.substring(listIdx, listEnd);
    expect('Duration'.allMatches(list).length, 3,
        reason: 'Exactly 3 attempts (1 initial + 2 retries) — enough to '
            'absorb a moov-atom-still-flushing race without retrying so '
            'long that duration backfill becomes noticeably slow.');
  });
}
