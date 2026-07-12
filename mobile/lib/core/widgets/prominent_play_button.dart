import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../ux/tap_feedback.dart';

/// High-contrast circular play / pause control for list cards.
class ProminentPlayButton extends StatelessWidget {
  const ProminentPlayButton({
    super.key,
    required this.onTap,
    this.size = 44,
    this.iconSize = 22,
    this.filled = true,
    this.isPlaying = false,
  });

  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool filled;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final fill = theme.actionFill;
    final fg = theme.onActionFill;
    final glow = theme.isDark ? AppColors.brandGlow : AppColors.lightBrandGlow;
    final icon = isPlaying ? AppIcons.pause : AppIcons.play;

    if (filled) {
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
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
          child: Material(
            color: fill,
            shape: CircleBorder(
              side: BorderSide(
                color: theme.isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : AppColors.ink.withValues(alpha: 0.08),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap == null
                  ? null
                  : () {
                      tapHaptic();
                      onTap!();
                    },
              customBorder: const CircleBorder(),
              child: Center(
                child: Icon(icon, color: fg, size: iconSize),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: fill.withValues(alpha: theme.isDark ? 0.14 : 0.08),
        shape: CircleBorder(
          side: BorderSide(color: theme.accentIcon.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  tapHaptic();
                  onTap!();
                },
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(icon, color: theme.accentIcon, size: iconSize),
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
