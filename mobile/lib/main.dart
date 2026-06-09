import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Allow lazy font fetch with instant system fallback — never block launch.
  GoogleFonts.config.allowRuntimeFetching = true;
  // Run immediately; the splash screen warms the DB/seed in the background.
  runApp(const ProviderScope(child: WhisperBackApp()));
}
