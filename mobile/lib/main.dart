import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'services/audio/whisper_audio_handler.dart';
import 'services/scheduler/background_alarm_playback.dart';

/// Global crash guard. Wraps the entire app in a zone so any uncaught
/// exception (sync or async) on a user tap is logged and survived instead
/// of force-closing the app. The user's previous QA report — "I clicked
/// play and the app CRASHED" — was almost always an unhandled
/// `PlatformException` from `just_audio` or `audio_service` on slow /
/// OEM-modified Android devices that bubbled past our per-tap try/catch.
/// We swallow them here as a last-resort safety net so the user never
/// sees the OS "WhisperBack stopped responding" dialog.
Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Catch uncaught framework errors (build/layout/paint) so the user
      // sees a red error widget in debug and a graceful fallback in
      // release — not a hung black screen.
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.dumpErrorToConsole(details);
        // Forward to the zone handler so it appears in our crash log.
        Zone.current
            .handleUncaughtError(details.exception, details.stack ?? StackTrace.empty);
      };
      // Catch platform-channel errors from outside the Flutter framework
      // (e.g. native plugin futures, isolate ports). Without this, an
      // unhandled PlatformException in `just_audio` after `setAudioSource`
      // crashes the entire app on some Samsung firmware.
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('Uncaught platform error: $error\n$stack');
        return true;
      };

      if (Platform.isAndroid) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      // Allow lazy font fetch with instant system fallback — never block launch.
      GoogleFonts.config.allowRuntimeFetching = true;

      // Round 20: bring up the AndroidAlarmManager background isolate
      // BEFORE we touch audio_service. This lets the schedule sync layer
      // register periodic alarms that survive the main Dart isolate
      // being killed by aggressive OEM battery managers. Best-effort —
      // a failure here is silent so a missing plugin (iOS, web,
      // integration test) never blocks launch.
      try {
        await initializeBackgroundAlarms();
      } catch (e, st) {
        debugPrint('initializeBackgroundAlarms failed: $e\n$st');
      }

      // Initialise the background audio service, but NEVER let it block or crash
      // app launch: on failure/timeout we fall back to a plain handler so the UI
      // always renders (no black screen).
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          whisperAudioHandler = await AudioService.init(
            builder: WhisperAudioHandler.new,
            config: AudioServiceConfig(
              androidNotificationChannelId: 'com.whisperback.playback',
              androidNotificationChannelName: 'WhisperBack Playback',
              androidNotificationChannelDescription:
                  'Now playing with lock-screen controls',
              androidNotificationOngoing: true,
              androidStopForegroundOnPause: false,
              androidNotificationIcon: 'drawable/ic_notification',
              androidNotificationClickStartsActivity: true,
              androidShowNotificationBadge: true,
              notificationColor: const Color(0xFF2E8BFF),
              artDownscaleWidth: 256,
              artDownscaleHeight: 256,
            ),
          ).timeout(const Duration(seconds: 8));
          whisperAudioServiceBound = true;
          // Pre-warm the audio session BEFORE the first user tap so the first
          // recorded clip doesn't race with native session activation. This is
          // the fix for "first clip recorded won't play, the next 6 do" — the
          // session config + setActive(true) used to land AFTER the first
          // `playFile` had already called `play()` and the OS denied audio
          // focus. Best-effort: errors are swallowed inside `warmUp`.
          unawaited(whisperAudioHandler.warmUp());
        } catch (e, st) {
          debugPrint('AudioService.init failed, using plain handler: $e\n$st');
          whisperAudioHandler = WhisperAudioHandler();
          whisperAudioServiceBound = false;
        }
      } else {
        whisperAudioHandler = WhisperAudioHandler();
      }

      runApp(const ProviderScope(child: WhisperBackApp()));
    },
    (Object error, StackTrace stack) {
      // Last-resort: log and survive. The OS NEVER sees "app stopped
      // responding" — the user gets a still-running app and can retry.
      debugPrint('Uncaught error (zone): $error\n$stack');
    },
  );
}
