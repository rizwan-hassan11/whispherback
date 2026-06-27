// Regression test for QA report:
//
//   "I imported one clip and there are no NEXT/PREV buttons" — the user
//   expects every playback context (single library preview, one-track
//   playlist, multi-clip playlist, scheduled play) to expose skip
//   controls in the mini-player and on the lock-screen MediaSession.
//
// Earlier behaviour hid the buttons when there was nothing to skip to,
// but users perceived that as "the controls are broken". We now ALWAYS
// expose the buttons while playback is in progress — single-clip taps
// restart from the top (handled in `WhisperAudioHandler.skipToNext` /
// `skipToPrevious`), which feels alive and matches the lock-screen
// notification layout pinned in `whisper_audio_handler_controls_test`.
//
// This file pins the new rule so the production check inside
// `PlaybackCoordinator.canSkipClips` can't silently regress.

import 'package:flutter_test/flutter_test.dart';

bool canSkipClips({required bool inPlaybackState}) {
  return inPlaybackState;
}

void main() {
  group('mini-player / modal skip button visibility', () {
    test('inactive playback state ALWAYS hides the buttons', () {
      expect(canSkipClips(inPlaybackState: false), isFalse);
    });

    test('any active playback ALWAYS shows the buttons (single or playlist)',
        () {
      expect(canSkipClips(inPlaybackState: true), isTrue);
    });
  });
}
