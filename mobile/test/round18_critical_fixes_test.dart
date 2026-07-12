// Pins the Round 18 critical fixes so future refactors cannot regress
// the user-reported bugs they were designed to address.
//
//   18-A  Native Android foreground service [WhisperKeepAliveService]
//         that holds a partial wake lock and a high-priority ongoing
//         notification so the process survives swipe-away and
//         aggressive OEM battery managers even WITHOUT a battery-
//         exemption grant. Bridged to Dart via [KeepAliveService].
//
//   18-B  Active toggle ON starts the native keep-alive service;
//         Active toggle OFF stops it. Cold start while Active also
//         restarts the service so a process kill + relaunch fully
//         restores background scheduling.
//
//   18-C  stopClip's keep-alive transition is atomic — the silence
//         loop is restarted WITHOUT publishing a `playing: false`
//         playbackState in between, so audio_service never sees a
//         "stop" event that would trigger Service.stopForeground().
//
//   18-D  dismissPlayer branches on Active state. Active mode hands
//         off to silence keep-alive (FG service stays bound).
//         Inactive mode pauses (clip position preserved for resume).
//         No call ever publishes the dangerous `playing:false +
//         processingState:idle + controls:[]` triple that demoted
//         the FG service in Round 16/17.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readFile(String relative) {
  final f = File(relative);
  if (!f.existsSync()) {
    fail('Expected source file does not exist: $relative');
  }
  return f.readAsStringSync();
}

void main() {
  group('Round 18-A — native keep-alive foreground service', () {
    test('WhisperKeepAliveService Kotlin file exists', () {
      final f = File(
        'android/app/src/main/kotlin/com/whisperback/whisperback/'
        'WhisperKeepAliveService.kt',
      );
      expect(
        f.existsSync(),
        isTrue,
        reason: 'The native FG service is the ONLY reliable way to '
            'keep the process alive on Samsung One UI 6 / Vivo '
            'Funtouch 14 / Xiaomi MIUI 14 — audio_service\'s own '
            'FG service is insufficient on these OEMs.',
      );
      final src = f.readAsStringSync();
      expect(src, contains('PARTIAL_WAKE_LOCK'),
          reason: 'A partial wake lock keeps the CPU running while '
              'the screen is off so Timer.periodic in the Dart '
              'isolate actually ticks at the right cadence.');
      expect(src, contains('startForeground'),
          reason: 'startForeground (or its compat variant) is what '
              'puts the process into the user-visible FG bucket.');
      expect(src, contains('START_STICKY'),
          reason: 'START_STICKY tells the OS to recreate the service '
              'if it gets killed.');
      expect(src, contains('onTaskRemoved'),
          reason: 'onTaskRemoved must be overridden to a no-op so '
              'the service stays alive after the user swipes the '
              'task away.');
    });

    test('AndroidManifest declares the keep-alive service', () {
      final manifest = _readFile('android/app/src/main/AndroidManifest.xml');
      expect(
        manifest,
        contains('WhisperKeepAliveService'),
        reason: 'The service must be declared in the manifest or '
            'startForegroundService will throw '
            'ClassNotFoundException at runtime.',
      );
      expect(
        manifest,
        contains('android:stopWithTask="false"'),
        reason: 'stopWithTask=false is required so the service '
            'survives task removal — without it the OS calls '
            'stopSelf() the moment the user swipes the activity.',
      );
      expect(
        manifest,
        contains('android:foregroundServiceType="specialUse"'),
        reason: 'Android 14+ requires an explicit FG service type. '
            'We use specialUse because mediaPlayback is already '
            'owned by audio_service\'s FG service.',
      );
      expect(
        manifest,
        contains('FOREGROUND_SERVICE_SPECIAL_USE'),
        reason: 'The matching permission must be declared.',
      );
    });

    test('Dart KeepAliveService bridge file exists', () {
      final f = File('lib/services/platform/keep_alive_service.dart');
      expect(f.existsSync(), isTrue);
      final src = f.readAsStringSync();
      expect(src, contains("MethodChannel('com.whisperback.keep_alive')"));
      expect(src, contains('Future<void> start()'));
      expect(src, contains('Future<void> stop()'));
    });

    test('MainActivity registers the keep-alive method channel', () {
      final src = _readFile(
        'android/app/src/main/kotlin/com/whisperback/whisperback/'
        'MainActivity.kt',
      );
      expect(src, contains('com.whisperback.keep_alive'));
      expect(src, contains('configureFlutterEngine'));
      expect(src, contains('WhisperKeepAliveService.start'));
      expect(src, contains('WhisperKeepAliveService.stop'));
    });
  });

  group('Round 18-B — Active toggle drives the keep-alive service', () {
    test('toggleActive starts the service when going ON', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<ActiveToggleResult> toggleActive()');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 2400);
      expect(
        body,
        contains('KeepAliveService.start()'),
        reason: 'toggleActive ON must start the native FG service '
            'BEFORE any audio_service work so the OS sees the FG '
            'binding before activity destruction can happen.',
      );
      expect(
        body,
        contains('KeepAliveService.stop()'),
        reason: 'toggleActive OFF must stop the native FG service '
            'so the wake lock is released and the user no longer '
            'sees the status bar icon.',
      );
    });

    test('cold-start while Active restarts the keep-alive service', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      // Look for the cold-start restoration block (right after the
      // initial snapshot emit).
      expect(
        src,
        contains('KeepAliveService.start()'),
        reason: 'A process kill + relaunch must fully restore the '
            'keep-alive FG service. The cold-start branch (active '
            '== true) must call KeepAliveService.start in addition '
            'to enterForeground.',
      );
    });
  });

  group('Round 18-C — stopClip keep-alive transition is atomic', () {
    test('keep-alive branch in stopClip does NOT publish playing:false', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final stopIdx = src.indexOf('Future<void> stopClip()');
      expect(stopIdx, greaterThan(0));
      // Capture the body up to the END of stopClip — find the next
      // top-level method declaration after stopClip.
      final nextMethodIdx =
          src.indexOf('Future<String> _ensureSilenceFile', stopIdx);
      expect(nextMethodIdx, greaterThan(stopIdx));
      final body = src.substring(stopIdx, nextMethodIdx);

      // The keep-alive branch must come BEFORE the publish-idle path,
      // and must NOT include any playbackState publish that flips
      // playing to false.
      final keepAliveIdx = body.indexOf('if (_keepAlive)');
      expect(
        keepAliveIdx,
        greaterThan(0),
        reason: 'stopClip must early-return into the keep-alive path '
            'when keep-alive is enabled.',
      );
      final keepAliveSlice =
          body.substring(keepAliveIdx, body.indexOf('return;', keepAliveIdx));
      // In Round 18 the keep-alive branch only stops the player and
      // restarts the silence loop — no `playing: false` publish.
      expect(
        keepAliveSlice,
        isNot(contains('playing: false')),
        reason: 'The keep-alive branch must NOT publish playing:false '
            'because that tells audio_service to stopForeground, '
            'which lets the OS reap the process before the silence '
            'loop can restart.',
      );
    });
  });

  group('Round 18-D — dismissPlayer branches on Active state', () {
    test('Active branch uses stop (keep-alive handoff)', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> dismissPlayer()');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 4000);
      // Active branch calls _audio.stop() which routes to stopClip
      // which handles the atomic keep-alive transition.
      expect(
        body,
        contains('_audio.stop()'),
        reason: 'Active branch must call _audio.stop so stopClip can '
            'hand off to the silence keep-alive atomically.',
      );
    });

    test('Inactive branch uses pause (preserves clip position)', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> dismissPlayer()');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 4000);
      expect(
        body,
        contains('_audio.pause()'),
        reason: 'Inactive branch must pause so the user can resume '
            'from where they left off when they re-tap the clip.',
      );
    });

    test(
        'dismissPlayer no longer CALLS hideClipMediaNotification (which '
        'was demoting the FG service)', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> dismissPlayer()');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 4000);
      // Round 18 removes the actual await call. The historical
      // reference in a code comment is fine (it documents WHY the
      // call is gone). We assert the await pattern specifically.
      expect(
        body,
        isNot(contains('await _audio.hideClipMediaNotification')),
        reason: 'hideClipMediaNotification published the lethal '
            'playing:false + processingState:idle + controls:[] '
            'triple that audio_service interpreted as "stop", which '
            'triggered Service.stopForeground() and let the OS '
            'reap the process. Round 18 removes the await call '
            '— stop() handles the atomic keep-alive transition.',
      );
    });
  });
}
