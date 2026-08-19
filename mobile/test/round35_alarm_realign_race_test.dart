// Round 35 — pinning test for the QA report:
//
//   Bug 1: "Scheduled whispers do not play at the set time" — behavior is
//   inconsistent, sometimes a whisper fires exactly on time, sometimes it
//   doesn't fire at all, with no consistent pattern.
//
//   Bug 3: "Schedule interval drifts from configured value" — the gap
//   between consecutive whispers grows past the configured interval, and
//   the drift itself is inconsistent from run to run.
//
// Root cause: `PlaybackCoordinator._onNativePlaybackState`'s IDLE branch
// (fired every time a scheduled clip finishes) used to kick off TWO
// independent `unawaited()` tasks back-to-back with no ordering between
// them:
//
//   1. `_stampNativeFireCompletion(...)` — writes the real completion
//      timestamp into `ScheduleLastFiredStore`.
//   2. `refreshScheduleNotifications(forceAlarmRebuild: true)` — the
//      Round 34 "realign" rebuild, which reprojects the native alarm
//      table using `ScheduleLastFiredStore`'s completion value as its
//      anchor.
//
// Because both were fire-and-forget tasks racing each other, whichever
// task's first `await` hop resolved first ran first. When the realign
// rebuild won the race, it read the STALE (one-cycle-old) completion
// stamp and projected the next alarm table from the wrong anchor —
// producing exactly the reported symptoms: whispers that sometimes
// silently miss their slot, and a gap between fires that drifts by an
// inconsistent amount instead of a fixed, predictable one.
//
// The fix chains the two steps sequentially inside ONE task — the stamp
// write is awaited to completion BEFORE the realign rebuild reads it —
// which makes the ordering deterministic instead of a race.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  final root = Directory.current.path;
  final path = p.join(root, relPath);
  // Normalize CRLF -> LF so `\n`-anchored substring searches below are not
  // thrown off by the repo's Windows line endings.
  return File(path).readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  group('Round 35 — deterministic ordering of stamp-then-realign', () {
    test(
        '_stampNativeFireCompletion is awaitable (not internally '
        'fire-and-forget) so callers can guarantee the write has landed', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final declIdx = src.indexOf('Future<void> _stampNativeFireCompletion(');
      expect(declIdx, greaterThanOrEqualTo(0),
          reason: '_stampNativeFireCompletion must return a Future<void> — '
              'a void-returning method that wraps its body in an internal '
              'unawaited() task cannot be sequenced by its caller, which '
              'was exactly the Round 34/35 race.');

      final bodyEnd = src.indexOf('\n  }', declIdx);
      expect(bodyEnd, greaterThan(declIdx));
      final body = src.substring(declIdx, bodyEnd);
      expect(body, isNot(contains('unawaited(')),
          reason: 'The method body must not spawn its own fire-and-forget '
              'task — the whole point is that the CALLER controls when '
              'this write is awaited.');
    });

    test(
        '_onNativePlaybackState\'s idle branch awaits the completion stamp '
        'BEFORE calling the forced alarm-table realign, inside the same '
        'task, so the realign can never read a stale completion value', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final handlerIdx = src.indexOf('void _onNativePlaybackState');
      expect(handlerIdx, greaterThanOrEqualTo(0));
      final handlerEnd = src.indexOf('\n  }\n', handlerIdx);
      expect(handlerEnd, greaterThan(handlerIdx));
      final handlerBody = src.substring(handlerIdx, handlerEnd);

      final stampCallIdx =
          handlerBody.indexOf('await _stampNativeFireCompletion(');
      expect(stampCallIdx, greaterThanOrEqualTo(0),
          reason: 'The idle branch must AWAIT the completion stamp, not '
              'fire it off and move on.');

      final realignCallIdx = handlerBody.indexOf(
          'await refreshScheduleNotifications?.call(forceAlarmRebuild: true)');
      expect(realignCallIdx, greaterThan(stampCallIdx),
          reason: 'The forced realign rebuild must run AFTER the awaited '
              'completion stamp so `applySnapshot` always projects from '
              'the freshly-written value, never a stale one.');

      // Both calls must live inside the SAME unawaited(() async { ... }())
      // task — i.e. there must be exactly one `unawaited(() async {` between
      // the stamp call and the realign call, not two separate tasks.
      final betweenCalls = handlerBody.substring(stampCallIdx, realignCallIdx);
      expect(betweenCalls.contains('unawaited(() async'), isFalse,
          reason: 'A second unawaited() task started between the stamp '
              'and the realign call would reintroduce the race — both '
              'must be sequenced inside one task.');
    });
  });
}
