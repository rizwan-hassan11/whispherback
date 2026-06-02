import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/bootstrap/app_bootstrap.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _minDisplay = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _goHomeWhenReady();
  }

  Future<void> _goHomeWhenReady() async {
    final started = DateTime.now();
    await AppBootstrap.ensureReady();
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minDisplay) {
      await Future<void>.delayed(_minDisplay - elapsed);
    }
    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'WhisperBack',
              style: GoogleFonts.fraunces(
                fontSize: 40,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: AppColors.soft,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.appTagline,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentBright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
