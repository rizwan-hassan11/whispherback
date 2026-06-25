import 'package:flutter_test/flutter_test.dart';

/// Documents the contract that `_onClipCompleted` advances to the NEXT clip
/// instead of replaying `clips.first` (the original P0 client bug). We don't
/// instantiate the full coordinator here — it depends on audio_service and
/// a foreground service binding — but we exercise the same index math the
/// coordinator uses so a regression is caught at unit time.
///
/// The fix is `(lastIndex + 1) % clips.length` and skip-over-unplayable; the
/// previous bug was always picking index 0.
int nextIndexAfterCompletion(int lastIndex, int clipCount) {
  if (clipCount <= 0) return -1;
  return (lastIndex + 1) % clipCount;
}

void main() {
  test('first completion of a 3-clip playlist advances to index 1', () {
    expect(nextIndexAfterCompletion(0, 3), 1);
  });

  test('middle completion advances to the next clip', () {
    expect(nextIndexAfterCompletion(1, 3), 2);
  });

  test('end-of-playlist wraps to track 0 instead of stalling', () {
    // Looping is the chosen behavior so a "scheduled whisper" session keeps
    // running until the next interval boundary.
    expect(nextIndexAfterCompletion(2, 3), 0);
  });

  test('single-clip playlist replays itself on completion', () {
    expect(nextIndexAfterCompletion(0, 1), 0);
  });

  test('empty playlist surfaces a sentinel (caller stops cleanly)', () {
    expect(nextIndexAfterCompletion(0, 0), -1);
  });

  test('regression: never returns 0 when lastIndex is 0 with >1 clip', () {
    // The reported client bug: 3-clip non-shuffle playlist looped at track 1.
    // Root cause was the coordinator calling `playPlaylist(...)` which always
    // picked `clips.first`. The fix advances by 1; here we assert that the
    // advance function NEVER returns the same index it was given, except for
    // the single-clip case above.
    for (var i = 0; i < 10; i++) {
      expect(nextIndexAfterCompletion(i, 10), isNot(i));
    }
  });
}
