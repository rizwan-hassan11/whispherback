import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/database/seed_service.dart';
import '../../l10n/app_localizations.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await SeedService.seedIfEmpty();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
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
