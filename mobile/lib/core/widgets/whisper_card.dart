import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'depth_surface.dart';

class WhisperCard extends StatelessWidget {
  const WhisperCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.badges = const [],
    this.progress,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> badges;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    return DepthTile(
      onTap: onTap,
      radius: AppRadii.sm,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: AppDepth.iconTile(isDark: theme.isDark, radius: 10),
            child: Icon(icon, color: AppColors.soft, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.soft,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: badges),
                ],
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: AppColors.glassBorder,
                      color: AppColors.brandLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class WhisperBadge extends StatelessWidget {
  const WhisperBadge({
    super.key,
    required this.label,
    this.variant = WhisperBadgeVariant.brand,
  });

  final String label;
  final WhisperBadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (variant) {
      WhisperBadgeVariant.gold => (
          AppColors.accent.withValues(alpha: 0.12),
          AppColors.soft,
          AppColors.accent.withValues(alpha: 0.22),
        ),
      WhisperBadgeVariant.brand => (
          AppColors.brandLight.withValues(alpha: 0.15),
          AppColors.brandLight,
          AppColors.brandLight.withValues(alpha: 0.25),
        ),
      WhisperBadgeVariant.success => (
          AppColors.success.withValues(alpha: 0.12),
          AppColors.success,
          AppColors.success.withValues(alpha: 0.3),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 0,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

enum WhisperBadgeVariant { gold, brand, success }
