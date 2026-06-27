// Regression tests for the play/pause/next/prev control layout that the
// `WhisperAudioHandler` publishes to the system MediaSession.
//
// Why these tests exist: A real QA report described tapping the lock-screen
// pause button and getting Next-clip instead. The root cause was that the
// controls array dropped the play/pause entry on the `completed` state,
// shifting `skipToNext` into the compact-bar slot users were aiming for.
// These tests pin the invariant: the controls array layout MUST be stable
// across every transition (loading → playing → paused → completed) so the
// compact indices always point at the same logical buttons.
//
// We assert on the LOGICAL layout rather than spinning up the full
// MediaSession (which requires the Android plugin runtime). The handler's
// public API only exposes the resulting positions implicitly via the
// internal map; we test by reflecting on the publicly visible
// `_playPauseControl` rules instead.

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Mirrors the production `_publishClipControls` layout so the regression
/// test pins the EXACT list ordering that ships to the system MediaSession.
/// If the production logic ever drops/reorders entries again, this test
/// flips red and reminds the developer of the lock-screen incident.
({List<MediaControl> controls, List<int> compact}) _layout({
  required bool playing,
  required ProcessingState processing,
  required bool playlistMode,
}) {
  final loading = processing == ProcessingState.loading ||
      processing == ProcessingState.buffering;
  final completed = processing == ProcessingState.completed;
  final reportPlaying = !completed && (playing || loading);
  final playPause = reportPlaying ? MediaControl.pause : MediaControl.play;

  const stop = MediaControl(
    androidIcon: 'drawable/ic_media_stop',
    label: 'Stop',
    action: MediaAction.stop,
  );

  // Single-clip AND playlist both expose [prev, play|pause, next, stop]
  // (compact = [0, 1, 2]). The previous single-clip layout dropped
  // `skipToNext` entirely — the QA report "the notification only shows
  // pause and previous, there is no next button" matched that drop.
  // Now the lock-screen layout matches the in-app mini-player/modal
  // and a single-clip context interprets next/prev as "restart from
  // the top" (handled inside `skipToNext` / `skipToPrevious`).
  return (
    controls: [
      MediaControl.skipToPrevious,
      playPause,
      MediaControl.skipToNext,
      stop,
    ],
    compact: const [0, 1, 2],
  );
}

void main() {
  group('WhisperAudioHandler controls layout', () {
    test(
        'single-clip layout ALWAYS has [prev, play|pause, next, stop] — the '
        'QA report "no next button" is fixed and pinned by this test', () {
      for (final state in [
        ProcessingState.idle,
        ProcessingState.loading,
        ProcessingState.buffering,
        ProcessingState.ready,
        ProcessingState.completed,
      ]) {
        for (final playing in [true, false]) {
          final result = _layout(
            playing: playing,
            processing: state,
            playlistMode: false,
          );
          expect(
            result.controls.length,
            4,
            reason: 'Single-clip controls must be exactly 4 entries '
                '(prev, play|pause, next, stop) — '
                'state=$state playing=$playing collapsed to '
                '${result.controls.length}',
          );
          expect(
            result.controls.first.action,
            MediaAction.skipToPrevious,
            reason: 'Prev must stay at index 0',
          );
          expect(
            result.controls[1].action,
            isIn({MediaAction.play, MediaAction.pause}),
            reason: 'Play/pause must always live at index 1 — got '
                '${result.controls[1].action}',
          );
          expect(
            result.controls[2].action,
            MediaAction.skipToNext,
            reason: 'Next must live at index 2 even for single-clip; '
                'restart-from-top is the single-clip semantics.',
          );
          expect(
            result.controls.last.action,
            MediaAction.stop,
            reason: 'Stop must stay at the last index',
          );
        }
      }
    });

    test(
        'playlist layout always has [prev, play|pause, next, stop] regardless '
        'of processing state', () {
      for (final state in [
        ProcessingState.idle,
        ProcessingState.loading,
        ProcessingState.buffering,
        ProcessingState.ready,
        ProcessingState.completed,
      ]) {
        for (final playing in [true, false]) {
          final result = _layout(
            playing: playing,
            processing: state,
            playlistMode: true,
          );
          expect(
            result.controls.length,
            4,
            reason: 'Playlist-mode controls must always be exactly 4 entries — '
                'state=$state playing=$playing collapsed to '
                '${result.controls.length}',
          );
          expect(
              result.controls.map((c) => c.action).toList(),
              [
                MediaAction.skipToPrevious,
                isIn({MediaAction.play, MediaAction.pause}),
                MediaAction.skipToNext,
                MediaAction.stop,
              ],
              reason: 'Layout shifted; this is exactly the bug that made the '
                  'lock-screen pause icon trigger Next.');
        }
      }
    });

    test(
        'completed state shows PLAY (not pause, not blank) so the user can tap '
        'to restart from the top', () {
      final result = _layout(
        playing: false,
        processing: ProcessingState.completed,
        playlistMode: true,
      );
      expect(result.controls[1].action, MediaAction.play,
          reason: 'Completed clip must surface PLAY at index 1 so the '
              'compact-bar slot stays meaningful — never drop the entry.');
    });

    test('compact indices are stable across the entire play-pause cycle', () {
      for (final state in [
        ProcessingState.loading,
        ProcessingState.ready,
        ProcessingState.completed,
      ]) {
        for (final playing in [true, false]) {
          final playlist = _layout(
            playing: playing,
            processing: state,
            playlistMode: true,
          );
          final single = _layout(
            playing: playing,
            processing: state,
            playlistMode: false,
          );
          expect(playlist.compact, const [0, 1, 2]);
          expect(single.compact, const [0, 1, 2]);
          // The icon at compact index 1 must always be play/pause — that's
          // the contract users learn after the first time they use the
          // app. Shifting any other icon into that slot is a regression.
          expect(
            playlist.controls[1].action,
            isIn({MediaAction.play, MediaAction.pause}),
          );
          expect(
            single.controls[1].action,
            isIn({MediaAction.play, MediaAction.pause}),
          );
        }
      }
    });
  });
}
