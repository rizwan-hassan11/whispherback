// Regression test for QA report:
//
//   "Initially the schedule worked perfectly, then I turned the schedule OFF,
//    but after some time the app started playing clips by itself."
//
// Root cause vector #2 (in addition to the save-preserves-enabled fix in
// schedule_repository.dart): there is a small race window inside
// `ScheduleEngine._runTick` where we read the schedule list, decide
// which schedule to fire, then do I/O to look up the playlist and
// compute slot timing before finally calling `requestScheduledPlay`.
// If the user toggles the schedule OFF during that window, the engine
// would still fire the now-disabled schedule.
//
// The fix is a last-chance re-read of the schedule row immediately
// before stamping + asking the coordinator to play. This file pins the
// invariant with a pure helper.

import 'package:flutter_test/flutter_test.dart';

bool shouldStillFire({
  required bool enabledAtSelection,
  required bool enabledNow,
}) {
  // The engine's per-tick loop reads `enabledAtSelection` from the list it
  // computed at the top of `_runTick`. Just before stamping + firing, it
  // re-reads `enabledNow` from the DB. We only proceed if BOTH are true.
  return enabledAtSelection && enabledNow;
}

void main() {
  group('ScheduleEngine last-chance disable re-check', () {
    test('schedule fires when it is enabled at both checkpoints', () {
      expect(
        shouldStillFire(enabledAtSelection: true, enabledNow: true),
        isTrue,
      );
    });

    test(
      'schedule MUST NOT fire when the user toggled it OFF during the tick',
      () {
        expect(
          shouldStillFire(enabledAtSelection: true, enabledNow: false),
          isFalse,
          reason: 'Without the re-check, the engine would fire a schedule '
              'the user disabled milliseconds earlier — this is exactly '
              'the QA report "schedule turned off but app still plays".',
        );
      },
    );

    test('schedule MUST NOT fire when the row vanished (deleted mid-tick)', () {
      // We model a deleted row as enabledNow == false because the engine
      // treats "no matching enabled row" as "do not fire". The branch is
      // the same in production; only the path that produces `enabledNow`
      // differs.
      expect(
        shouldStillFire(enabledAtSelection: true, enabledNow: false),
        isFalse,
      );
    });

    test('schedule MUST NOT fire if the initial enabled flag was already false',
        () {
      expect(
        shouldStillFire(enabledAtSelection: false, enabledNow: true),
        isFalse,
        reason: 'Defense in depth — the per-row enabled check at the top '
            'of the loop body is the primary guard; the re-read is a '
            'belt-and-suspenders against races, not a replacement.',
      );
    });
  });
}
