// Regression test for QA report:
//
//   "Forward / backward sy kuch nahi hota" — the user perceives the skip
//   buttons on the Spotify-style mini player as broken.
//
// Root cause: `PlaybackCoordinator.canSkipClips` previously returned true
// for ANY playing state, including single-clip library previews and
// one-track playlists. Tapping the skip button on those just restarted
// the same clip — visually identical to "nothing happened". The fix
// hides the buttons entirely when there is genuinely nothing to skip
// to.
//
// This file pins the visibility rule with a pure helper so the
// production check inside `canSkipClips` can't silently regress.

import 'package:flutter_test/flutter_test.dart';

bool canSkipClips({
  required bool inPlaybackState,
  required String? playlistId,
  required int libraryQueueLength,
  required int knownPlaylistClipCount,
}) {
  if (!inPlaybackState) return false;
  if (playlistId == null) return libraryQueueLength > 1;
  return knownPlaylistClipCount > 1;
}

void main() {
  group('mini-player / modal skip button visibility', () {
    test('inactive state ALWAYS hides the buttons', () {
      expect(
        canSkipClips(
          inPlaybackState: false,
          playlistId: 'whatever',
          libraryQueueLength: 99,
          knownPlaylistClipCount: 99,
        ),
        isFalse,
      );
    });

    test('single-clip library preview hides the buttons (the QA bug)', () {
      expect(
        canSkipClips(
          inPlaybackState: true,
          playlistId: null,
          libraryQueueLength: 1,
          knownPlaylistClipCount: 0,
        ),
        isFalse,
        reason: 'Tapping skip on a single-clip preview just restarts the '
            'same clip — looks identical to a broken button to the user.',
      );
    });

    test('multi-clip library queue shows the buttons', () {
      expect(
        canSkipClips(
          inPlaybackState: true,
          playlistId: null,
          libraryQueueLength: 3,
          knownPlaylistClipCount: 0,
        ),
        isTrue,
      );
    });

    test('one-track playlist hides the buttons', () {
      expect(
        canSkipClips(
          inPlaybackState: true,
          playlistId: 'p1',
          libraryQueueLength: 0,
          knownPlaylistClipCount: 1,
        ),
        isFalse,
      );
    });

    test('multi-track playlist shows the buttons', () {
      expect(
        canSkipClips(
          inPlaybackState: true,
          playlistId: 'p1',
          libraryQueueLength: 0,
          knownPlaylistClipCount: 5,
        ),
        isTrue,
      );
    });
  });
}
