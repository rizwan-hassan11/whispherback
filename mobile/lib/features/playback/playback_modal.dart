import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../domain/playback/playback_state.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../services/audio/audio_services.dart';
import '../../services/scheduler/native_alarms_bridge.dart';

bool _useNativeProgress(PlaybackSnapshot snapshot, AudioPlaybackService audio) {
  return snapshot.state == AppPlaybackState.scheduledPlaying &&
      audio.currentPath == null;
}

/// Fires [body] without awaiting and routes any thrown error to the zone
/// handler instead of letting it crash the app. The buttons in the
/// playback modal call into the coordinator which talks to native audio
/// — every interaction has a small but non-zero chance of throwing a
/// `PlatformException` on certain OEM firmwares (Vivo / Infinix /
/// Samsung mid-range). This guard guarantees a tap is never the
/// reason the app crashes.
void _safeCall(Future<void> Function() body, String tag) {
  unawaited(() async {
    try {
      await body();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('playback_modal $tag failed (handled): $e\n$st');
      }
    }
  }());
}

class PlaybackModal extends ConsumerWidget {
  const PlaybackModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackSnapshotProvider);
    final snapshot = playback.valueOrNull;
    if (snapshot == null ||
        snapshot.state == AppPlaybackState.inactive ||
        snapshot.state == AppPlaybackState.activeIdle ||
        snapshot.playlistName == null ||
        !snapshot.modalVisible) {
      return const SizedBox.shrink();
    }

    final coordinator = ref.read(playbackCoordinatorProvider);
    final audio = ref.read(audioPlaybackServiceProvider);
    final l10n = context.l10n;

    return Stack(
      children: [
        // Tap-outside scrim to dismiss.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: coordinator.dismissModal,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          // Swipe the sheet down to dismiss.
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 250) coordinator.dismissModal();
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                0,
                0,
                ShellMetrics.playbackModalBottomInset(context),
              ),
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFA081634), Color(0xFA020611)],
                      ),
                      border:
                          Border(top: BorderSide(color: AppColors.glassBorder)),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: -80,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 280,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.07),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const _NowPlayingChip(),
                              const SizedBox(height: 18),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _CoverArt(isPlaying: snapshot.isPlaying),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          snapshot.playlistName ?? '',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.1,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          snapshot.clipTitle ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.fraunces(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            height: 1.15,
                                            color: AppColors.soft,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Semantics(
                                    label: l10n.minimizePlayer,
                                    button: true,
                                    child: Material(
                                      color: AppColors.glass,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                            color: AppColors.glassBorder),
                                      ),
                                      child: InkWell(
                                        onTap: coordinator.dismissModal,
                                        borderRadius: BorderRadius.circular(12),
                                        child: const SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: Icon(
                                            AppIcons.chevronDown,
                                            size: 22,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              StreamBuilder<Duration?>(
                                stream: _useNativeProgress(snapshot, audio)
                                    ? NativeAlarmsBridge.instance.stateStream
                                        .map<Duration?>((n) => Duration(
                                            milliseconds: n.positionMs))
                                    : audio.positionStream,
                                initialData: _useNativeProgress(snapshot, audio)
                                    ? Duration(
                                        milliseconds: NativeAlarmsBridge
                                            .instance.lastSnapshot.positionMs)
                                    : null,
                                builder: (context, posSnap) {
                                  return StreamBuilder<Duration?>(
                                    stream: _useNativeProgress(snapshot, audio)
                                        ? NativeAlarmsBridge
                                            .instance.stateStream
                                            .map<Duration?>((n) => Duration(
                                                milliseconds: n.durationMs))
                                        : audio.durationStream,
                                    initialData:
                                        _useNativeProgress(snapshot, audio)
                                            ? Duration(
                                                milliseconds: NativeAlarmsBridge
                                                    .instance
                                                    .lastSnapshot
                                                    .durationMs)
                                            : null,
                                    builder: (context, durSnap) {
                                      final rawPos =
                                          posSnap.data ?? Duration.zero;
                                      final dur = durSnap.data ?? Duration.zero;
                                      final maxMs = dur.inMilliseconds;
                                      final posMs = maxMs > 0
                                          ? rawPos.inMilliseconds
                                              .clamp(0, maxMs)
                                          : rawPos.inMilliseconds
                                              .clamp(0, 1 << 31);
                                      final pos = Duration(milliseconds: posMs);
                                      final progress =
                                          maxMs > 0 ? posMs / maxMs : 0.0;
                                      final clamped = progress.clamp(0.0, 1.0);
                                      final remainingMs =
                                          (maxMs - posMs).clamp(0, maxMs);
                                      final remaining =
                                          Duration(milliseconds: remainingMs);

                                      return Column(
                                        children: [
                                          _WaveformProgress(progress: clamped),
                                          const SizedBox(height: 10),
                                          _SeekBar(
                                            progress: clamped,
                                            enabled: maxMs > 0 &&
                                                !_useNativeProgress(
                                                    snapshot, audio),
                                            onSeek: (fraction) {
                                              if (maxMs <= 0) return;
                                              // Native scheduled playback
                                              // does not yet expose seek —
                                              // only Dart clips scrub.
                                              if (_useNativeProgress(
                                                  snapshot, audio)) {
                                                return;
                                              }
                                              final target = Duration(
                                                milliseconds:
                                                    (fraction * maxMs).round(),
                                              );
                                              coordinator.seek(target);
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _format(pos),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.soft,
                                                  fontFeatures: [
                                                    FontFeature.tabularFigures()
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                remaining.isNegative
                                                    ? _format(Duration.zero)
                                                    : '−${_format(remaining)}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.muted,
                                                  fontFeatures: [
                                                    FontFeature.tabularFigures()
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 24),
                              Builder(builder: (context) {
                                final canSkip = coordinator.canSkipClips;
                                final isPlaylistContext =
                                    snapshot.playlistId != null;
                                // Scroll horizontally on very narrow phones (≤320 dp)
                                // so the controls row never overflows or gets clipped.
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  padding: EdgeInsets.zero,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (isPlaylistContext)
                                        _CtrlButton(
                                          semanticLabel: l10n.toggleShuffle,
                                          icon: AppIcons.shuffle,
                                          highlighted: snapshot.shuffleEnabled,
                                          onPressed: () => _safeCall(
                                            () => coordinator.toggleShuffle(
                                              snapshot.playlistId!,
                                              !snapshot.shuffleEnabled,
                                            ),
                                            'toggleShuffle',
                                          ),
                                        ),
                                      if (isPlaylistContext)
                                        const SizedBox(width: 12),
                                      if (canSkip)
                                        _CtrlButton(
                                          semanticLabel: l10n.previousTrack,
                                          icon: Icons.skip_previous_rounded,
                                          onPressed: () => _safeCall(
                                            coordinator.skipPrevious,
                                            'skipPrevious',
                                          ),
                                        ),
                                      if (canSkip) const SizedBox(width: 12),
                                      _CtrlButton(
                                        semanticLabel: snapshot.isPlaying
                                            ? l10n.pause
                                            : l10n.play,
                                        icon: snapshot.isPlaying
                                            ? AppIcons.pause
                                            : AppIcons.play,
                                        filled: true,
                                        onPressed: () {
                                          if (snapshot.isPlaying) {
                                            _safeCall(
                                                coordinator.pause, 'pause');
                                          } else {
                                            _safeCall(
                                                coordinator.resume, 'resume');
                                          }
                                        },
                                      ),
                                      if (canSkip) const SizedBox(width: 12),
                                      if (canSkip)
                                        _CtrlButton(
                                          semanticLabel: l10n.nextTrack,
                                          icon: Icons.skip_next_rounded,
                                          onPressed: () => _safeCall(
                                            coordinator.skipNext,
                                            'skipNext',
                                          ),
                                        ),
                                      const SizedBox(width: 12),
                                      _CtrlButton(
                                        semanticLabel: l10n.stopPlayback,
                                        icon: AppIcons.close,
                                        // Same OEM activity-kill defence
                                        // as the mini-player cross — see
                                        // `PlaybackCoordinator.dismissPlayer`
                                        // for the full rationale.
                                        onPressed: () => _safeCall(
                                          coordinator.dismissPlayer,
                                          'dismiss',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _NowPlayingChip extends StatelessWidget {
  const _NowPlayingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.55),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.nowPlaying,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.isPlaying});

  final bool isPlaying;

  static const _barHeights = [12.0, 22.0, 30.0, 18.0, 26.0, 14.0];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.card, AppColors.ink],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final h in _barHeights)
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              width: 3,
              height: isPlaying ? h : h * 0.55,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveformProgress extends StatelessWidget {
  const _WaveformProgress({required this.progress});

  final double progress;

  static const _count = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_count, (i) {
          final h = 5 +
              (24 * (0.5 + 0.5 * _wave(i * 0.38 + 0.4)).abs()) +
              (4 * _wave(i * 0.17));
          final clampedH = h.clamp(4.0, 36.0);
          final played = i / _count < progress;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  height: clampedH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: played
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [AppColors.brand, Color(0x8CF1F5F9)],
                          )
                        : null,
                    color:
                        played ? null : AppColors.muted.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  double _wave(double x) => math.sin(x * 3.7);
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.filled = false,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final bool filled;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Semantics(
        label: semanticLabel,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brand,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandGlow,
                    blurRadius: 28,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: AppColors.deep, size: 30),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: highlighted
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        shape: CircleBorder(
          side: BorderSide(
            color: highlighted
                ? Colors.white.withValues(alpha: 0.28)
                : AppColors.glassBorder,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icon,
              color: highlighted ? AppColors.brand : AppColors.soft,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

/// Scrubbable progress bar — tap anywhere to seek, drag to scrub.
///
/// While the user is interacting we render the local thumb position instead of
/// the live [progress] so the bar doesn't fight finger movement when audio
/// position updates lag the gesture by a frame or two.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.progress,
    required this.enabled,
    required this.onSeek,
  });

  final double progress;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _draggingFraction;

  double _fractionForDx(double dx, double width) {
    if (width <= 0) return 0;
    return (dx / width).clamp(0.0, 1.0);
  }

  void _handleDown(double dx, double width) {
    if (!widget.enabled) return;
    final f = _fractionForDx(dx, width);
    setState(() => _draggingFraction = f);
  }

  void _handleUpdate(double dx, double width) {
    if (!widget.enabled) return;
    final f = _fractionForDx(dx, width);
    setState(() => _draggingFraction = f);
  }

  void _commit() {
    if (!widget.enabled || _draggingFraction == null) return;
    final f = _draggingFraction!;
    widget.onSeek(f);
    setState(() => _draggingFraction = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fraction = (_draggingFraction ?? widget.progress).clamp(0.0, 1.0);
        final thumbLeft = (fraction * width - 9).clamp(0.0, width - 18);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _handleDown(d.localPosition.dx, width);
            _commit();
          },
          onHorizontalDragStart: (d) => _handleDown(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) =>
              _handleUpdate(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _commit(),
          onHorizontalDragCancel: () =>
              setState(() => _draggingFraction = null),
          child: SizedBox(
            // Tall hit area for a finger-friendly tap/drag target.
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      width: width,
                      child: Stack(
                        children: [
                          Container(color: AppColors.glassBorder),
                          FractionallySizedBox(
                            widthFactor: fraction,
                            child: Container(color: AppColors.brand),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: thumbLeft,
                  top: 5,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brand,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
