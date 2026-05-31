import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Gradient backdrop with soft ambient orbs for premium screens.
class PremiumScreenBackground extends StatelessWidget {
  const PremiumScreenBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: theme.isDark
                ? AppColors.backgroundGradient
                : AppColors.lightBackgroundGradient,
          ),
        ),
        if (!theme.isDark) ...[
          Positioned(
            top: -80,
            right: -50,
            child: _LightOrb(size: 220, color: AppColors.ink.withValues(alpha: 0.06)),
          ),
          Positioned(
            top: 120,
            left: -60,
            child: _LightOrb(size: 160, color: AppColors.lightMuted.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: 120,
            right: -30,
            child: _LightOrb(size: 140, color: AppColors.success.withValues(alpha: 0.06)),
          ),
        ] else
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandLight.withValues(alpha: 0.07),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

class _LightOrb extends StatelessWidget {
  const _LightOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
