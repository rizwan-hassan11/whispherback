import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/prominent_play_button.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/audio_clip.dart';
import '../../../core/widgets/whisper_card.dart';

class PlaylistClipTile extends StatelessWidget {
  const PlaylistClipTile({
    super.key,
    required this.clip,
    required this.index,
    required this.onPlay,
  });

  final AudioClip clip;
  final int index;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final isRecorded = clip.source == ClipSource.recorded;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.glass,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.glassBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.muted,
                    ),
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.brand.withValues(alpha: 0.4),
                        AppColors.brandLight.withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                  child: Icon(
                    isRecorded ? AppIcons.mic : AppIcons.audioFile,
                    color: AppColors.brandLight,
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            clip.durationLabel,
                            style: TextStyle(fontSize: 12, color: theme.muted),
                          ),
                          const SizedBox(width: 8),
                          WhisperBadge(
                            label: isRecorded ? 'Recorded' : 'Imported',
                            variant: isRecorded
                                ? WhisperBadgeVariant.brand
                                : WhisperBadgeVariant.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _MiniWaveform(active: false),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ProminentPlayButton(onTap: onPlay),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniWaveform extends StatelessWidget {
  const _MiniWaveform({required this.active});

  final bool active;

  static const _heights = [4.0, 7.0, 10.0, 6.0, 9.0, 5.0, 8.0, 11.0, 6.0, 4.0];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_heights.length, (i) {
          return Expanded(
            child: Container(
              height: _heights[i],
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: active
                    ? AppColors.brandLight.withValues(alpha: 0.8)
                    : AppColors.brandLight.withValues(alpha: 0.25),
              ),
            ),
          );
        }),
      ),
    );
  }
}
