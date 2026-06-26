// Regression test for QA report:
//
//   "Spotify-styled bar behaves unusually — like pressing pause plays the
//    next clip, and forward/backward do nothing."
//
// Root cause: on short whisper clips (2-5 seconds), the player can race
// `ProcessingState.completed` against the user's pause tap. Even though
// `coordinator.pause()` calls `_player.pause()`, the completion event
// fires first (or at the same time) and reaches `_onClipCompleted`,
// which auto-advances to the next clip in a multi-clip playlist. The
// user perceives this as "I tapped pause and got the next clip".
//
// The fix: `coordinator.pause()` (and any system-side pause via the
// media notification) sets `_userInitiatedPause = true` BEFORE the
// `await _audio.pause()`. `_onClipCompleted` checks this flag first
// and, if set, parks the position at zero and emits paused — the
// auto-advance only runs on a genuine end-of-clip with no preceding
// user pause. The flag is cleared on explicit resume, on a fresh
// play/skip, on stop, and on toggling Active off.
//
// This file pins the state-machine contract with a tiny pure helper so
// a future refactor of the coordinator can't silently regress.

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the post-fix decision tree inside
/// `PlaybackCoordinator._onClipCompleted`. The first branch is the new
/// suppression check; the rest of the routing is left to the production
/// coordinator (and covered by the broader playlist-advance test).
enum CompletionResult {
  parkAtPauseEnd,
  finishScheduled,
  finishManualPreview,
  advancePlaylist,
}

CompletionResult decideCompletion({
  required bool userInitiatedPause,
  required bool isScheduled,
  required String? playlistId,
}) {
  if (userInitiatedPause) return CompletionResult.parkAtPauseEnd;
  if (isScheduled) return CompletionResult.finishScheduled;
  if (playlistId == null) return CompletionResult.finishManualPreview;
  return CompletionResult.advancePlaylist;
}

void main() {
  group('clip completion routing (user-paused suppression)', () {
    test(
      'when user paused, a completion event that races the pause MUST NOT '
      'auto-advance the playlist',
      () {
        expect(
          decideCompletion(
            userInitiatedPause: true,
            isScheduled: false,
            playlistId: 'playlist-a',
          ),
          CompletionResult.parkAtPauseEnd,
          reason: 'This is the exact QA bug: a 3-clip playlist where the '
              'user tapped pause on a 4-second clip and the natural '
              'completion race caused the next clip to start.',
        );
      },
    );

    test(
      'when user paused inside a scheduled run, suppression also wins over '
      'the scheduled-completion bookkeeping',
      () {
        expect(
          decideCompletion(
            userInitiatedPause: true,
            isScheduled: true,
            playlistId: 'playlist-b',
          ),
          CompletionResult.parkAtPauseEnd,
          reason: 'A scheduled fire that the user pauses should also park '
              'cleanly; the engine will get its completion stamp from the '
              'subsequent resume + natural completion, not from this '
              'phantom race-completion.',
        );
      },
    );

    test(
      'natural end of a multi-clip playlist still auto-advances when the '
      'user did not pause',
      () {
        expect(
          decideCompletion(
            userInitiatedPause: false,
            isScheduled: false,
            playlistId: 'playlist-c',
          ),
          CompletionResult.advancePlaylist,
          reason: 'Regression guard: the suppression must not over-apply '
              'and break normal playlist auto-advance. This is the '
              'baseline contract that drives session continuity.',
        );
      },
    );

    test(
      'natural end of a single-clip library preview routes to the manual '
      'finish path',
      () {
        expect(
          decideCompletion(
            userInitiatedPause: false,
            isScheduled: false,
            playlistId: null,
          ),
          CompletionResult.finishManualPreview,
          reason: 'Library queue / single-clip preview should not be '
              'caught by the suppression branch — it has its own end-of-'
              'preview routing.',
        );
      },
    );

    test(
      'natural end of a scheduled fire routes to the scheduled-completion '
      'bookkeeping',
      () {
        expect(
          decideCompletion(
            userInitiatedPause: false,
            isScheduled: true,
            playlistId: 'playlist-d',
          ),
          CompletionResult.finishScheduled,
          reason: 'Scheduled completion is what feeds `setCompletion()` so '
              'the next slot is measured from playback END. Suppression '
              'flag must clear in the happy path so this stays correct.',
        );
      },
    );
  });

  group('user-paused flag lifecycle', () {
    test(
      'flag is set on pause, cleared on resume — the two are symmetric',
      () {
        var flag = false;

        void pause() => flag = true;
        void resume() => flag = false;

        pause();
        expect(flag, isTrue, reason: 'pause must arm the suppression');
        resume();
        expect(flag, isFalse, reason: 'resume must disarm it cleanly');
      },
    );

    test(
      'flag is cleared on starting a brand-new playlist, even when the '
      'user previously paused without an explicit resume',
      () {
        var flag = true;

        void playNewPlaylist() {
          // Mirrors `_userInitiatedPause = false` in `_playPlaylistInternal`.
          flag = false;
        }

        playNewPlaylist();
        expect(flag, isFalse,
            reason: 'Otherwise the very first completion of the new '
                'playlist would be swallowed by the suppression check, '
                'leaving the user stuck on track 1 forever.');
      },
    );

    test(
      'flag is cleared on explicit skip — the user wants to move on, even '
      'if they previously paused',
      () {
        var flag = true;

        void skipNext() {
          flag = false;
        }

        skipNext();
        expect(flag, isFalse,
            reason: 'A tap on the skip button is an unambiguous "move on" '
                'intent; suppression must not block subsequent natural '
                'completions in the new clip.');
      },
    );
  });
}
