import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/bootstrap/app_bootstrap.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_logos.dart';
import '../../core/widgets/whisper_wordmark.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _minDisplay = Duration(milliseconds: 400);

  /// Cap bootstrap wait so a stuck SQLite / orphan reconcile never leaves
  /// the user on a black splash after a force-close reopen (QA Aug 22).
  static const _bootstrapTimeout = Duration(seconds: 8);

  /// Cancellable caps — `Future.timeout` leaves a pending Timer that breaks
  /// widget tests when the tree is torn down before the duration elapses.
  Timer? _bootstrapCap;
  Timer? _minDisplayCap;

  @override
  void initState() {
    super.initState();
    _goHomeWhenReady();
  }

  @override
  void dispose() {
    _bootstrapCap?.cancel();
    _minDisplayCap?.cancel();
    super.dispose();
  }

  Future<void> _goHomeWhenReady() async {
    final started = DateTime.now();
    try {
      await _ensureReadyWithCap();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'Splash: bootstrap timed out or failed — home anyway: $e\n$st');
      }
    }
    if (!mounted) return;
    final elapsed = DateTime.now().difference(started);
    final remaining = _minDisplay - elapsed;
    if (remaining > Duration.zero) {
      final delayDone = Completer<void>();
      _minDisplayCap = Timer(remaining, delayDone.complete);
      await delayDone.future;
      _minDisplayCap = null;
    }
    if (!mounted) return;
    context.go('/home');
  }

  /// Race bootstrap against a manually cancellable timer (not Future.timeout)
  /// so dispose can clear pending timers during tests / fast navigation.
  Future<void> _ensureReadyWithCap() {
    final done = Completer<void>();
    _bootstrapCap = Timer(_bootstrapTimeout, () {
      if (!done.isCompleted) {
        done.completeError(
          TimeoutException('splash bootstrap exceeded $_bootstrapTimeout'),
        );
      }
    });
    AppBootstrap.ensureReady().then((_) {
      if (!done.isCompleted) done.complete();
    }, onError: (Object e, StackTrace st) {
      if (!done.isCompleted) done.completeError(e, st);
    });
    return done.future.whenComplete(() {
      _bootstrapCap?.cancel();
      _bootstrapCap = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark
              ? AppColors.backgroundGradient
              : AppColors.lightBackgroundGradient,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const WhisperBackLogo(size: 88),
            const SizedBox(height: 28),
            const WhisperWordmark(
              showTagline: true,
              titleFontSize: 36,
              taglineFontSize: 10,
              alignment: CrossAxisAlignment.center,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? AppColors.neonCyan : AppColors.neonDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
