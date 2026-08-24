// Round 41 — pause / skip / resume felt laggy or dead on the mini-player
// and the system notification. This is NOT a Riverpod-vs-BLoC issue:
// scheduled controls already leave Dart immediately via MethodChannel
// into WhisperPlaybackService's MediaPlayer. The bugs were:
//
//   1. After an optimistic pause, native progress ticks still pushed
//      STATE_PLAYING. Coordinator treated that as resume (`wasPaused`).
//   2. Mini-player play/pause used `snapshot.isPlaying || native.isPlaying`,
//      so a stale native PLAYING tick kept the pause icon and the next
//      tap raced resume.
//   3. Skip waited until MediaPlayer.prepareAsync finished before telling
//      Flutter the new track; setDataSource also blocked the main thread
//      so the posted state callback ran late.
//   4. Pause/skip gates waited 4s / 10s on a hung OEM call, so the next
//      tap looked dead.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  final root = Directory.current.path;
  return File(p.join(root, relPath))
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
}

void main() {
  group('Round 41 — transport latency (native engine, not Riverpod)', () {
    test('coordinator ignores native PLAYING ticks after a user pause', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _onNativePlaybackState(');
      expect(idx, greaterThanOrEqualTo(0));
      final playingIdx = src.indexOf('if (native.isPlaying)', idx);
      final pausedIdx = src.indexOf('if (native.isPaused)', idx);
      expect(playingIdx, greaterThan(idx));
      expect(pausedIdx, greaterThan(playingIdx));
      final playingBranch = src.substring(playingIdx, pausedIdx);
      expect(playingBranch, contains('if (_userInitiatedPause)'),
          reason: 'Progress ticks keep broadcasting PLAYING after pause. '
              'Without this guard the optimistic pause is undone and the '
              'button looks dead / inconsistent.');
      expect(playingBranch, contains('return;'),
          reason: 'Must actually ignore the tick, not only log it.');
    });

    test('native skip updates clip title on PLAYING when track changes', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('if (native.isPlaying)');
      final pausedIdx = src.indexOf('if (native.isPaused)', idx);
      final playingBranch = src.substring(idx, pausedIdx);
      expect(playingBranch, contains('titleChanged'),
          reason: 'Round-robin skip must refresh clipTitle from native.');
    });

    test('unified transport gate timeout covers setAudioSource', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('return _serializeTransport((epoch) async'));
      expect(
        src,
        contains('static const _transportBodyTimeout = Duration(seconds: 12)'),
        reason: 'Transport gate must cover setAudioSource (8s) without the '
            'old 2.5s skip timeout aborting while playFile still runs.',
      );
    });

    test('mini-player play/pause and cover follow coordinator snapshot only',
        () {
      final src = _read('lib/features/playback/mini_player_bar.dart');
      expect(src.contains('nativeLive && native.isPlaying'), isFalse,
          reason: 'OR-ing native.isPlaying with the snapshot re-lit the '
              'pause icon after the user tapped pause.');
      // Round 51: Dart-owned sessions follow MediaSession playing (same as
      // the notification). Cover/button still use a single displayPlaying.
      expect(src, contains('displayPlaying'));
      expect(
        src.contains('mediaSessionPlaying') ||
            src.contains('final displayPlaying = snapshot.isPlaying;') ||
            src.contains('final playing = snapshot.isPlaying;'),
        isTrue,
        reason: 'Play/pause icon must follow a single live playing flag.',
      );
    });

    test('native skip flushes the current player before rebinding', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      final idx = src.indexOf('private fun handleSkipCommand(');
      expect(idx, greaterThanOrEqualTo(0));
      final end = src.indexOf('private fun flushPlayerForSkip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('flushPlayerForSkip()'));
      final flushIdx = body.indexOf('flushPlayerForSkip()');
      final notifyIdx = body.indexOf('notifyListener(STATE_PAUSED)');
      final playIdx = body.indexOf('playClip(path)');
      expect(flushIdx, greaterThanOrEqualTo(0));
      expect(notifyIdx, greaterThan(flushIdx));
      expect(playIdx, greaterThan(notifyIdx));
      expect(src, contains('player.reset()'));
    });

    test('progress ticker and watchdog must not re-arm after a user pause', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      final tickerIdx = src.indexOf('private val progressTicker');
      final watchdogIdx = src.indexOf('private val playbackWatchdog');
      expect(tickerIdx, greaterThanOrEqualTo(0));
      expect(watchdogIdx, greaterThan(tickerIdx));
      final ticker = src.substring(tickerIdx, watchdogIdx);
      expect(ticker, contains('if (userPaused || !wantPlaying) return'));
      expect(
        ticker,
        contains('if (!userPaused && wantPlaying)'),
        reason: 'Re-posting the ticker at the end of run() after pause '
            'was racing stopProgressTicker and pushing STATE_PLAYING.',
      );
      final watchdogEnd = src.indexOf('override fun onBind', watchdogIdx);
      final watchdog = src.substring(watchdogIdx, watchdogEnd);
      expect(watchdog, contains('if (userPaused || !wantPlaying) return'));
      expect(watchdog, contains('if (!userPaused && wantPlaying)'));
    });
  });
}
