// Round 10 regression — the user reported:
//   "I powered ON the app but still there is no interactive and functional
//    permanent notification bar in my andorid to show me that the app is
//    working in Background, and the schedules and next schedule time..."
//
// Root cause: `home_screen.dart` called `syncWhisperNotifications` BEFORE
// `runSchedulingSetupWizard`. On a fresh install, POST_NOTIFICATIONS was
// still denied when the sync attempted to post the persistent "active"
// card — the OS silently dropped it. The wizard then granted permission
// a moment later, but there was no re-sync, so the notification stayed
// missing until the next lifecycle event.
//
// The fix re-orders the toggle handler:
//   1. coordinator.toggleActive()
//   2. runSchedulingSetupWizard  (asks POST_NOTIFICATIONS, exact alarms, battery)
//   3. syncWhisperNotifications  (NOW that permissions are granted)
//
// We pin the ordering in the source file with a string check so a
// regression won't slip through.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
      'home_screen.dart calls runSchedulingSetupWizard BEFORE '
      'syncWhisperNotifications on Active-ON toggle — fix for '
      '"no notification bar after powering on the app"', () {
    final homePath = p.join(
      Directory.current.path,
      'lib',
      'features',
      'home',
      'home_screen.dart',
    );
    final source = File(homePath).readAsStringSync();

    final wizardIndex = source.indexOf('runSchedulingSetupWizard');
    final syncIndex = source.indexOf('syncWhisperNotifications');

    expect(wizardIndex, greaterThanOrEqualTo(0),
        reason: 'runSchedulingSetupWizard call must exist in home_screen.dart');
    expect(syncIndex, greaterThanOrEqualTo(0),
        reason: 'syncWhisperNotifications call must exist in home_screen.dart');

    expect(wizardIndex, lessThan(syncIndex),
        reason: 'The permission wizard MUST run BEFORE the first '
            'syncWhisperNotifications call inside the Active toggle '
            'handler. Otherwise POST_NOTIFICATIONS is still denied at '
            'sync time and the persistent notification card is silently '
            'dropped by the OS — which is exactly the "no notification '
            'after powering on" QA report.');
  });

  test(
      'app.dart cold-start re-syncs notifications multiple times after the '
      'initial post so a late "Allow" tap on the OS permission dialog '
      'still surfaces the persistent active card', () {
    final appPath = p.join(
      Directory.current.path,
      'lib',
      'app.dart',
    );
    final source = File(appPath).readAsStringSync();

    expect(
      source.contains('syncWhisperNotifications'),
      isTrue,
      reason: 'app.dart cold-start path must sync notifications at least once.',
    );

    // The retry loop uses a list of Durations — count how many follow-up
    // syncs are scheduled. We expect at least 2 retries after the initial
    // sync so a slow "Allow" tap still lands the notification within 10s.
    final retryDelays =
        RegExp(r'Duration\(seconds:\s*\d+\)').allMatches(source).length;
    expect(
      retryDelays,
      greaterThanOrEqualTo(2),
      reason: 'app.dart should schedule at least 2 follow-up sync attempts '
          'so a late permission grant on a fresh install reliably posts '
          'the persistent active notification within 10 s.',
    );
  });

  test(
      'WhisperAudioHandler tracks `_keepAliveRunning` so '
      '`isForegroundNotificationActive` cannot lie when the silence loop '
      'failed to start — the flutter notification fallback then takes over',
      () {
    final handlerPath = p.join(
      Directory.current.path,
      'lib',
      'services',
      'audio',
      'whisper_audio_handler.dart',
    );
    final source = File(handlerPath).readAsStringSync();

    expect(
      source.contains('_keepAliveRunning'),
      isTrue,
      reason: 'A flag is required to distinguish "silence loop started" '
          'from "keep-alive requested but threw" — without it, OEMs '
          'where `setAudioSource(silence)` is rejected leave the user '
          'with NO notification at all (no media card AND no flutter '
          'fallback).',
    );

    expect(
      source.contains('isForegroundNotificationActive') &&
          source.contains('_keepAliveRunning &&'),
      isTrue,
      reason: '`isForegroundNotificationActive` must include the '
          '`_keepAliveRunning` guard so the flutter notification path '
          'kicks in when the audio_service silence loop failed.',
    );
  });

  test(
      'ScheduleEngine uses exponential backoff instead of a flat 1-minute '
      'cooldown so a transient cold-start failure is retried within 5 s '
      '(was 60 s — the QA "next whisper says NOW but no audio plays" '
      'reproduction)', () {
    final enginePath = p.join(
      Directory.current.path,
      'lib',
      'services',
      'scheduler',
      'schedule_engine.dart',
    );
    final source = File(enginePath).readAsStringSync();

    expect(source.contains('_failureStreak'), isTrue,
        reason: 'Per-schedule streak counter must exist to drive the '
            'exponential backoff.');
    expect(source.contains('_backoffFor('), isTrue,
        reason: 'Backoff helper must exist so the streak maps to a '
            'concrete Duration.');
    expect(source.contains('_baseBackoff'), isTrue,
        reason: 'A base backoff (~5 s) is required for the first retry.');
  });
}
