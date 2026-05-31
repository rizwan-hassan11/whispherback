import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_icons.dart';

/// High-contrast circular play control for list cards.
class ProminentPlayButton extends StatelessWidget {
  const ProminentPlayButton({
    super.key,
    required this.onTap,
    this.size = 44,
    this.iconSize = 22,
    this.filled = true,
  });

  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final fill = theme.actionFill;
    final fg = theme.onActionFill;
    final glow = theme.isDark ? AppColors.brandGlow : AppColors.lightBrandGlow;

    if (filled) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(
                color: theme.isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : AppColors.ink.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: theme.isDark ? 0.55 : 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                if (theme.isDark)
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.12),
                    blurRadius: 0,
                    offset: const Offset(0, -1),
                  ),
              ],
            ),
            child: Icon(
              AppIcons.play,
              color: fg,
              size: iconSize,
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill.withValues(alpha: theme.isDark ? 0.14 : 0.08),
            border: Border.all(color: theme.accentIcon.withValues(alpha: 0.35)),
          ),
          child: Icon(
            AppIcons.play,
            color: theme.accentIcon,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}

/// Small schedule indicator on cover art.
class ScheduleBadgeDot extends StatelessWidget {
  const ScheduleBadgeDot({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.actionFill,
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.isDark ? AppColors.deep : AppColors.lightBg,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.28 : 0.14),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        AppIcons.schedule,
        size: size * 0.55,
        color: theme.onActionFill,
      ),
    );
  }
}
