// Round 53 — QA v1.0.0 blockers (Aug 21, 2026)
//
// BUG-001: next/prev updated title while the previous clip kept playing.
// BUG-002: native AlarmManager fired scheduled audio during Sleep Mode.
// BUG-003: battery settings opened with no in-app guidance.
// BUG-004: sleep toggle felt silent; nav icons sat on different baselines.
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
  group('Round 53 — QA blocker fixes', () {
    test('playFile publishes MediaItem only after setAudioSource', () {
      final src = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = src.indexOf('Future<void> _playFileBound(');
      expect(idx, greaterThanOrEqualTo(0));
      final end = src.indexOf('void _scheduleStartWatchdog()', idx);
      final body = src.substring(idx, end);
      final bindIdx = body.indexOf('setAudioSource(_clipFileSource(path)');
      final itemIdx = body.indexOf('mediaItem.add(item)');
      expect(bindIdx, greaterThanOrEqualTo(0));
      expect(itemIdx, greaterThan(bindIdx),
          reason: 'Title must not update until the new file is bound.');
      expect(body, contains('await _flushPlayerSource()'));
    });

    test('skip flushes Dart source before playFile bind (title may flip first)', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(');
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('flushCurrentSource()'));
      expect(body, contains('_serializeTransport'));
      expect(
        body.indexOf('flushCurrentSource()'),
        lessThan(body.indexOf('_serializeTransport')),
        reason: 'Old audio must stop before the skip body binds the new file.',
      );
      // Round 55: coordinator title may flip before flush for instant feedback;
      // handler still publishes MediaItem only after setAudioSource (above).
    });

    test('native alarm receiver and service refuse Sleep Mode fires', () {
      final receiver = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmReceiver.kt');
      expect(receiver, contains('WhisperPlaybackService.isSleepActive'));
      final service = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(service, contains('KEY_SLEEP_END_MS'));
      expect(service, contains('isSleepActive(this)'));
      final coordinator =
          _read('lib/services/playback/playback_coordinator.dart');
      expect(coordinator, contains('if (_sleep.isSleepActive(sleep))'));
      expect(coordinator, contains('setSleepBarrier('));
      expect(coordinator, contains('stopNative()'));
    });

    test('battery guide dialog is shown before opening system settings', () {
      final prompt = _read('lib/services/platform/permission_prompt.dart');
      expect(prompt, contains('showBatteryOptimizationGuideDialog'));
      final battery = _read('lib/features/device/battery_settings_screen.dart');
      expect(battery, contains('showBatteryOptimizationGuideDialog'));
    });

    test('bottom nav reserves a label slot so icons share one baseline', () {
      final nav = _read('lib/core/widgets/glass_nav_bar.dart');
      expect(nav, contains('height: compact ? 12 : 13'));
      expect(nav, contains("showLabel ? destination.label : ''"));
    });
  });
}
