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

    test('stale native PAUSED must not undo an in-flight resume or skip', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('bool _awaitingNativePlay'),
          reason: 'Resume/skip optimistic UI is otherwise overwritten by '
              'the 1.5s prefs poll still reporting PAUSED.');
      final idx = src.indexOf('if (native.isPaused)');
      expect(idx, greaterThanOrEqualTo(0));
      final idleIdx = src.indexOf('if (_nativeScheduledActive)', idx);
      final pausedBranch = src.substring(idx, idleIdx);
      expect(pausedBranch, contains('if (_awaitingNativePlay)'),
          reason: 'Skip/resume set isPlaying true before native prepare. '
              'A PAUSED poll in that window must not flip the icon back.');
    });

    test('pause/resume gate times out in 1.5s, skip gate in 2.5s', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        src,
        contains('await body().timeout(const Duration(milliseconds: 1500)'),
        reason: 'A hung pauseNative must not freeze the next tap for 4s.',
      );
      expect(
        src,
        contains(
            'static const _skipGateBodyTimeout = Duration(milliseconds: 2500)'),
        reason: 'A hung skipNative must not freeze next/prev for 10s.',
      );
    });

    test('mini-player play/pause and cover follow coordinator snapshot only',
        () {
      final src = _read('lib/features/playback/mini_player_bar.dart');
      expect(src.contains('nativeLive && native.isPlaying'), isFalse,
          reason: 'OR-ing native.isPlaying with the snapshot re-lit the '
              'pause icon after the user tapped pause.');
      expect(src, contains('isPlaying: snapshot.isPlaying'));
      expect(src, contains('final playing = snapshot.isPlaying;'));
    });

    test('native skip notifies Flutter and posts playClip after the UI update',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      final idx = src.indexOf('private fun handleSkipCommand(');
      expect(idx, greaterThanOrEqualTo(0));
      final end = src.indexOf('\n    }\n', idx);
      final body = src.substring(idx, end);
      final notifyIdx = body.indexOf('notifyListener(STATE_PLAYING)');
      final playIdx = body.indexOf('playClipAfterUiUpdate(');
      expect(notifyIdx, greaterThanOrEqualTo(0));
      expect(playIdx, greaterThan(notifyIdx),
          reason: 'Flutter must hear about the new track before '
              'setDataSource/prepareAsync block the main thread.');
      expect(src, contains('player.reset()'),
          reason: 'Skip should reuse MediaPlayer via reset() instead of '
              'release()+new MediaPlayer() on every next/prev.');
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
