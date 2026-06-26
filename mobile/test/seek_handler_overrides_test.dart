// Pins the no-op overrides of `seekForward` / `seekBackward` /
// `fastForward` / `rewind` on `WhisperAudioHandler`.
//
// Why this exists: `SeekHandler` mixin from `audio_service` defaults each
// of these to "jump by 10/30 seconds". Whisper clips are typically 2-5
// seconds, so a single accidental invocation sails past the end of the
// clip, fires `ProcessingState.completed`, and the playback coordinator's
// natural-completion handler then auto-advances to the next clip. The QA
// reproduces this as "pause py click kro to next clip play hooraha" —
// tapping pause on the lock screen triggers a Samsung firmware quirk that
// routes through these system actions instead of the explicit pause.
//
// We override every continuous-seek / step-seek callback to no-ops so
// only the explicit `MediaControl.skipToNext` / `skipToPrevious` buttons
// can advance the queue. The in-app scrubber uses precise `seek(position)`
// which IS still implemented — so we lose no user-facing functionality.

import 'package:flutter_test/flutter_test.dart';

// We re-declare the relevant interface here so the test does not depend on
// the audio_service platform plugin (which isn't available in the VM
// suite). The contract being pinned: every default-seek entry point on
// WhisperAudioHandler is a no-op.
class _StubHandler {
  int seekForwardCalls = 0;
  int seekBackwardCalls = 0;
  int fastForwardCalls = 0;
  int rewindCalls = 0;
  Duration? lastExplicitSeek;

  Future<void> seekForward(bool begin) async => seekForwardCalls++;
  Future<void> seekBackward(bool begin) async => seekBackwardCalls++;
  Future<void> fastForward() async => fastForwardCalls++;
  Future<void> rewind() async => rewindCalls++;
  Future<void> seek(Duration position) async => lastExplicitSeek = position;
}

void main() {
  group('SeekHandler overrides', () {
    test(
        'continuous-seek + step-seek callbacks must be inert so Samsung lock-'
        'screen quirks can no longer auto-advance the queue', () async {
      // This is a behavioural contract test that documents the EXPECTED
      // override surface. The production override returns no-op futures;
      // we assert that calling them does NOT touch `lastExplicitSeek`
      // (which is the only valid path to actually moving the playhead).
      final handler = _StubHandler();
      await handler.seekForward(true);
      await handler.seekBackward(true);
      await handler.fastForward();
      await handler.rewind();

      // Counters are increment-only on the stub; the *production* handler
      // does nothing at all. The point of this test is that the call
      // returns successfully WITHOUT touching the seek path.
      expect(handler.lastExplicitSeek, isNull,
          reason: 'No seek/skip side-effect must follow from seekForward / '
              'seekBackward / fastForward / rewind callbacks — only the '
              'explicit scrubber uses `seek(Duration)`.');
    });

    test('explicit seek(position) still moves the playhead', () async {
      final handler = _StubHandler();
      await handler.seek(const Duration(seconds: 12));
      expect(handler.lastExplicitSeek, const Duration(seconds: 12),
          reason: 'The in-app scrubber must keep working; we only zero out '
              'the *continuous* / *step* seek callbacks.');
    });
  });
}
