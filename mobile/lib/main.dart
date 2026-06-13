import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'services/audio/whisper_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Allow lazy font fetch with instant system fallback — never block launch.
  GoogleFonts.config.allowRuntimeFetching = true;

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
              'Now playing, lock-screen controls, and active session',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'drawable/ic_notification',
          androidNotificationClickStartsActivity: true,
          notificationColor: const Color(0xFF2E8BFF),
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (e, st) {
      debugPrint('AudioService.init failed, using plain handler: $e\n$st');
      whisperAudioHandler = WhisperAudioHandler();
    }
  } else {
    whisperAudioHandler = WhisperAudioHandler();
  }

  runApp(const ProviderScope(child: WhisperBackApp()));
}
