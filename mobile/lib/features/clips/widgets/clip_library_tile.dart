import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/prominent_play_button.dart';
import '../../../core/widgets/whisper_card.dart';
import '../../../domain/entities/audio_clip.dart';
import '../../../l10n/app_localizations.dart';

class ClipLibraryTile extends StatelessWidget {
  const ClipLibraryTile({
    super.key,
    required this.clip,
    required this.onPlay,
    this.onDelete,
  });

  final AudioClip clip;
  final VoidCallback onPlay;
  final VoidCallback? onDelete;

  static String relativeDate(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return l10n.today;
    if (diff == 1) return l10n.yesterday;
    if (diff < 7) return l10n.daysAgo(diff);
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final l10n = context.l10n;
    final isRecorded = clip.source == ClipSource.recorded;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.isDark ? theme.glass : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isRecorded
                  ? theme.glassBorder
                  : AppColors.success.withValues(alpha: 0.22),
            ),
            boxShadow: theme.isDark
                ? null
                : [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      relativeDate(clip.createdAt, l10n),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.muted,
                        letterSpacing: 0.2,
                      ),
                    ),
                    WhisperBadge(
                      label: isRecorded ? 'Recorded' : 'Imported',
                      variant: isRecorded
                          ? WhisperBadgeVariant.brand
                          : WhisperBadgeVariant.gold,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isRecorded
                            ? AppColors.neon.withValues(
                                alpha: theme.isDark ? 0.16 : 0.12,
                              )
                            : AppColors.success.withValues(alpha: 0.12),
                        border: Border.all(
                          color: isRecorded
                              ? AppColors.neon.withValues(alpha: 0.4)
                              : AppColors.success.withValues(alpha: 0.3),
                        ),
                        boxShadow: isRecorded
                            ? [
                                BoxShadow(
                                  color: AppColors.neon.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        isRecorded ? AppIcons.mic : AppIcons.audioFile,
                        color: isRecorded
                            ? AppColors.neonBright
                            : AppColors.success,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clip.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: theme.foreground,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            clip.durationLabel,
                            style: TextStyle(fontSize: 12, color: theme.muted),
                          ),
                        ],
                      ),
                    ),
                    ProminentPlayButton(onTap: onPlay, size: 40, iconSize: 18),
                    if (onDelete != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(AppIcons.trash,
                            color: AppColors.error, size: 20),
                        tooltip: l10n.deleteClip,
                        onPressed: onDelete,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
