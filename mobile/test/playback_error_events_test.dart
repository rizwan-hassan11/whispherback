import 'package:flutter_test/flutter_test.dart';
import 'package:whisperback/services/playback/playback_coordinator.dart';

/// The play-tap path the client reported as silent must always emit a
/// PlaybackErrorEvent so the shell can show a snackbar. These tests pin the
/// public error-event API; the shell wiring is covered by the widget tests.
void main() {
  test('PlaybackErrorReason enum covers every failure class', () {
    // Pinning the public API: every reason listed here is rendered with a
    // dedicated localized message in main_shell.dart. Adding a new reason
    // without a UI mapping would surface as a missing-arm switch warning.
    expect(PlaybackErrorReason.values, hasLength(3));
    expect(
        PlaybackErrorReason.values, contains(PlaybackErrorReason.pathRejected));
    expect(
        PlaybackErrorReason.values, contains(PlaybackErrorReason.decodeFailed));
    expect(
      PlaybackErrorReason.values,
      contains(PlaybackErrorReason.emptyPlaylist),
    );
  });

  test('PlaybackErrorEvent carries reason and optional clip title', () {
    const a = PlaybackErrorEvent(PlaybackErrorReason.pathRejected);
    expect(a.reason, PlaybackErrorReason.pathRejected);
    expect(a.clipTitle, isNull);

    const b = PlaybackErrorEvent(
      PlaybackErrorReason.decodeFailed,
      clipTitle: 'Voice memo',
    );
    expect(b.reason, PlaybackErrorReason.decodeFailed);
    expect(b.clipTitle, 'Voice memo');
  });
}
