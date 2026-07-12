import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/config/feature_flags.dart';
import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/playback/playback_state.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../core/widgets/depth_surface.dart';
import '../../core/widgets/audio_service_warning_banner.dart';
import '../../providers/repository_providers.dart';
import '../../services/audio/whisper_audio_handler.dart';
import '../../services/platform/permission_prompt.dart';
import '../../services/notifications/notification_sync.dart';
import '../../services/scheduler/schedule_countdown.dart';
import '../../services/scheduler/schedule_fire_helper.dart';
import '../../services/scheduler/schedule_last_fired_store.dart';
import '../widgets/active_toggle.dart';
import 'widgets/home_ambience.dart';

enum _GreetingPeriod { morning, afternoon, evening }

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackSnapshotProvider);
    final snapshot = playback.valueOrNull ??
        const PlaybackSnapshot(state: AppPlaybackState.inactive);
    final isActive = snapshot.state != AppPlaybackState.inactive;

    final playlistsAsync = ref.watch(playlistsProvider);
    final clipsAsync = ref.watch(clipsProvider);
    final schedulesAsync = ref.watch(schedulesProvider);
    final theme = whisperTheme(context);
    final greetingPeriod = _greetingPeriod();

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: theme.isDark
                  ? [
                      AppColors.deep2,
                      AppColors.deep,
                      AppColors.ink,
                    ]
                  : [
                      AppColors.lightBg,
                      AppColors.lightBg2,
                      AppColors.lightBg3,
                    ],
            ),
          ),
        ),
        RepaintBoundary(
          child: HomeAmbience(isActive: isActive),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final r = context.responsive;
              final viewportHeight = constraints.maxHeight;

              // The home page is structured into THREE regions, top to
              // bottom:
              //
              //   1. HEADER ZONE (fixed)
              //        - app title + date
              //        - greeting card ("Good morning")
              //        - scheduling setup chip (if Active)
              //      These NEVER scroll away. The QA-reported "GOOD morning
              //      and the finish setup button is scrollable and they
              //      become hidden on scroll down" was caused by putting
              //      these in a scrollable region — they are now pinned.
              //
              //   2. TOGGLE ZONE (centered in remaining space)
              //        - waveform
              //        - master Active power button
              //        - pedestal
              //        - status pill
              //      Vertically centered in the leftover viewport so the
              //      power button sits comfortably in the middle of the
              //      visible area, not "inclined upward".
              //
              //   3. STATS ZONE (scrollable, only if overflow)
              //        - quick stats
              //        - next-whisper card (if Active)
              //        - sleep/prayer mode chip
              //      Sits below the toggle. On normal phones every region
              //      fits without scrolling; only when the user has many
              //      mode chips visible does this region scroll — and even
              //      then, the toggle and header stay anchored.
              //
              // This was the "I think the power button should be a little
              // bit lower" + "GOOD morning ... is scrollable" QA report
              // from the last round. Both are resolved by pinning header +
              // greeting, vertically centering the toggle, and making only
              // the bottom stats region scrollable.

              final headerZone = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _HomeHeader(theme: theme),
                  SizedBox(height: r.isFlipCover ? 10 : 14),
                  _GreetingCard(
                    theme: theme,
                    playlistCount: playlistsAsync.valueOrNull?.length ?? 0,
                    greetingPeriod: greetingPeriod,
                  ),
                  if (isActive) ...[
                    SizedBox(height: r.isFlipCover ? 8 : 10),
                    Center(
                      child: _SchedulingSetupChip(
                        isActive: isActive,
                        theme: theme,
                      ),
                    ),
                  ],
                ],
              );

              final toggleZone = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: DepthScene(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: r.isFlipCover ? 10 : 16),
                          ActiveToggle(
                            isActive: isActive,
                            onToggle: () {
                              // Whole tap path runs inside try/catch so a
                              // failure in the permission wizard or the
                              // notification refresh never crashes the
                              // user's tap. The global zone guard is a
                              // safety net; this is the per-tap belt.
                              unawaited(() async {
                                try {
                                  await ref
                                      .read(playbackCoordinatorProvider)
                                      .toggleActive();
                                  if (!context.mounted) return;
                                  final appState =
                                      ref.read(appStateRepositoryProvider);
                                  final nowActive = await appState.isActive();

                                  if (nowActive && context.mounted) {
                                    // CRITICAL: run the permission wizard
                                    // FIRST so POST_NOTIFICATIONS and exact-
                                    // alarm are granted BEFORE we attempt to
                                    // post the persistent "active" status
                                    // notification. Previously the sync ran
                                    // first, the OS silently dropped the
                                    // notification because the runtime
                                    // permission was denied, and the user
                                    // saw no notification bar even after
                                    // granting the permission via the
                                    // wizard a moment later — there was no
                                    // re-sync afterwards.
                                    await runSchedulingSetupWizard(context);
                                    if (context.mounted &&
                                        !whisperAudioServiceBound) {
                                      await showAudioServiceUnavailableDialog(
                                        context,
                                      );
                                    }
                                  }

                                  // Sync notifications AFTER the wizard so
                                  // newly-granted permissions take effect
                                  // on the very first attempt to post the
                                  // status / schedule alarms. Runs for
                                  // both ON and OFF transitions (OFF
                                  // needs to cancel the ongoing card).
                                  if (context.mounted) {
                                    await syncWhisperNotifications(
                                      appState: appState,
                                      schedules:
                                          ref.read(scheduleRepositoryProvider),
                                      prayer:
                                          ref.read(prayerRepositoryProvider),
                                    );
                                  }
                                } catch (e, st) {
                                  debugPrint(
                                      'Active toggle tap failed (handled): $e\n$st');
                                }
                              }());
                            },
                          ),
                          const SizedBox(height: 10),
                          const DepthPedestal(),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: r.isFlipCover ? 8 : 10),
                  Center(
                    child: _StatusPill(isActive: isActive, theme: theme),
                  ),
                ],
              );

              final statsChildren = <Widget>[
                _QuickStats(
                  theme: theme,
                  playlistCount: playlistsAsync.valueOrNull?.length ?? 0,
                  clipCount: clipsAsync.valueOrNull?.length ?? 0,
                  scheduleCount: schedulesAsync.valueOrNull?.length ?? 0,
                ),
                if (isActive) ...[
                  const SizedBox(height: 14),
                  _NextWhisperCard(theme: theme),
                ],
                if (snapshot.state == AppPlaybackState.sleepPaused) ...[
                  const SizedBox(height: 14),
                  _ModeChip(
                    icon: AppIcons.bedtime,
                    label: context.l10n.sleepModeActive,
                    color: AppColors.brandLight,
                    theme: theme,
                  ),
                ],
                if (kAdhanFeatureEnabled &&
                    snapshot.state == AppPlaybackState.prayerPaused) ...[
                  const SizedBox(height: 14),
                  _ModeChip(
                    icon: AppIcons.prayer,
                    label: context.l10n.prayerPauseActive,
                    color: AppColors.gold,
                    theme: theme,
                  ),
                ],
                SizedBox(
                  height: ShellMetrics.scrollBottomInset(context, extra: 4),
                ),
              ];

              // Defensive fallback: on extremely short form factors (flip
              // covers, split-screen ~250px) the toggle alone may exceed
              // what's left after the header. Drop back to a single scroll
              // view that contains everything so the layout doesn't crash
              // with a negative Spacer. The user can still scroll to the
              // toggle and back; nothing is lost.
              final estimatedMinToggleHeight = r.isFlipCover ? 280.0 : 360.0;
              final estimatedHeaderHeight =
                  isActive ? (r.isFlipCover ? 170.0 : 200.0) : 130.0;
              final reservedForStats = r.isFlipCover ? 90.0 : 120.0;
              final canPinLayout = viewportHeight >=
                  (estimatedHeaderHeight +
                      estimatedMinToggleHeight +
                      reservedForStats);

              if (!canPinLayout) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: r.horizontalGutter),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        headerZone,
                        SizedBox(height: r.isFlipCover ? 14 : 20),
                        toggleZone,
                        SizedBox(height: r.isFlipCover ? 14 : 20),
                        ...statsChildren,
                      ],
                    ),
                  ),
                );
              }

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: r.horizontalGutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    headerZone,
                    Expanded(
                      child: Column(
                        children: [
                          // Centers the toggle vertically in the remaining
                          // viewport AFTER header + stats are reserved.
                          // The user no longer perceives the power button
                          // as "inclined upward" — it sits in the middle
                          // of the visible content area.
                          Expanded(
                            child: Align(
                              alignment: const Alignment(0, 0.38),
                              child: toggleZone,
                            ),
                          ),
                          // The stats region is bounded to a fraction of
                          // the viewport so it never starves the toggle
                          // zone. If stats overflow this bound (multiple
                          // mode chips, very small phone), they scroll
                          // inside the cap.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: viewportHeight * 0.42,
                            ),
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: statsChildren,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  _GreetingPeriod _greetingPeriod() {
    final hour = DateTime.now().hour;
    if (hour < 12) return _GreetingPeriod.morning;
    if (hour < 17) return _GreetingPeriod.afternoon;
    return _GreetingPeriod.evening;
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.theme});

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WhisperBack',
          style: GoogleFonts.fraunces(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: theme.foreground,
          ),
        ),
        Text(
          DateFormat('EEEE, MMM d', locale).format(now),
          style: TextStyle(fontSize: 12, color: theme.muted),
        ),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.theme,
    required this.playlistCount,
    required this.greetingPeriod,
  });

  final WhisperThemeExtension theme;
  final int playlistCount;
  final _GreetingPeriod greetingPeriod;

  IconData get _icon => switch (greetingPeriod) {
        _GreetingPeriod.morning => AppIcons.sun,
        _GreetingPeriod.afternoon => AppIcons.cloudSun,
        _ => AppIcons.moon,
      };

  String _greetingText(AppLocalizations l10n) => switch (greetingPeriod) {
        _GreetingPeriod.morning => l10n.goodMorning,
        _GreetingPeriod.afternoon => l10n.goodAfternoon,
        _ => l10n.goodEvening,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DepthSurface(
      radius: AppRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      tiltX: 0.025,
      lift: 6,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: theme.isDark
                    ? [
                        AppColors.cardElevated,
                        AppColors.ink,
                        const Color(0xFF040B1E)
                      ]
                    : [AppColors.brand, AppColors.ink],
                stops: theme.isDark ? const [0, 0.6, 1] : const [0, 1],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.isDark
                    ? const Color(0x28FFFFFF)
                    : AppColors.lightGlassBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: theme.isDark ? 0.35 : 0.14),
                  offset: const Offset(0, 4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(
              _icon,
              color: theme.isDark ? AppColors.brandLight : AppColors.lightBg,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greetingText(l10n),
                  style: GoogleFonts.fraunces(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: theme.foreground,
                  ),
                ),
                Text(
                  playlistCount > 0
                      ? l10n.playlistsReady(playlistCount)
                      : l10n.createPlaylistToStart,
                  style:
                      TextStyle(fontSize: 12, color: theme.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextWhisperCard extends ConsumerStatefulWidget {
  const _NextWhisperCard({required this.theme});

  final WhisperThemeExtension theme;

  @override
  ConsumerState<_NextWhisperCard> createState() => _NextWhisperCardState();
}

class _NextWhisperCardState extends ConsumerState<_NextWhisperCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final schedules = ref.watch(schedulesProvider).valueOrNull ?? [];
    final enabled = schedules.where((s) => s.enabled).toList(growable: false);
    final now = DateTime.now();
    final next = ScheduleFireHelper.nextUpcoming(
      enabled,
      now,
      lastFiredFor: ScheduleLastFiredStore.instance.completion,
      lastSlotFor: ScheduleLastFiredStore.instance.slot,
      // Home page surfaces this as "next at HH:mm" — never let a past
      // slot leak through even if the engine would still fire it
      // within its grace window.
      forDisplay: true,
    );

    final subtitle = next == null
        ? l10n.noSchedulesYet
        : '${next.schedule.playlistName} · ${ScheduleCountdown.untilTime(next.when, now)}';

    return GestureDetector(
      onTap: () => context.go('/schedule'),
      child: DepthSurface(
        radius: AppRadii.sm,
        padding: const EdgeInsets.all(14),
        tiltX: 0.02,
        lift: 4,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.theme.glass,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(AppIcons.schedule,
                  color: widget.theme.foreground, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.nextWhisper,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: widget.theme.foreground,
                    ),
                  ),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, color: widget.theme.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isActive, required this.theme});

  final bool isActive;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? AppColors.neon.withValues(alpha: 0.14) : theme.glass,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: isActive
              ? AppColors.neon.withValues(alpha: 0.45)
              : theme.glassBorder,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.neon.withValues(alpha: 0.22),
                  blurRadius: 22,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(active: isActive),
          const SizedBox(width: 10),
          Text(
            isActive ? l10n.activeWhispersPlaying : l10n.tapPowerToBegin,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.neonBright : theme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.active});

  final bool active;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.active ? AppColors.neonCyan : AppColors.muted2,
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: AppColors.neonCyan.withValues(
                        alpha: 0.4 + _c.value * 0.4,
                      ),
                      blurRadius: 6 + _c.value * 6,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({
    required this.theme,
    required this.playlistCount,
    required this.clipCount,
    required this.scheduleCount,
  });

  final WhisperThemeExtension theme;
  final int playlistCount;
  final int clipCount;
  final int scheduleCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _StatTile(
            theme: theme,
            icon: AppIcons.playlists,
            value: '$playlistCount',
            label: l10n.statPlaylists,
            accent: AppColors.neonBright,
            onTap: () => context.go('/playlists'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            theme: theme,
            icon: AppIcons.schedule,
            value: '$scheduleCount',
            label: l10n.statScheduled,
            accent: AppColors.gold,
            onTap: () => context.go('/schedule'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            theme: theme,
            icon: AppIcons.mic,
            value: '$clipCount',
            label: l10n.statClips,
            accent: AppColors.success,
            onTap: () => context.go('/clips'),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.theme,
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String value;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DepthTile(
      radius: AppRadii.sm,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 13),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: theme.isDark ? 0.30 : 0.22),
                  accent.withValues(alpha: theme.isDark ? 0.12 : 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: theme.isDark ? 0.30 : 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(height: 11),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1,
              color: theme.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.muted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulingSetupChip extends StatefulWidget {
  const _SchedulingSetupChip({
    required this.isActive,
    required this.theme,
  });

  final bool isActive;
  final WhisperThemeExtension theme;

  @override
  State<_SchedulingSetupChip> createState() => _SchedulingSetupChipState();
}

class _SchedulingSetupChipState extends State<_SchedulingSetupChip> {
  bool? _ready;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant _SchedulingSetupChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (!widget.isActive) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    final ready = await isSchedulingFullyReady();
    if (mounted) setState(() => _ready = ready);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready != false) return const SizedBox.shrink();

    final l10n = context.l10n;
    const color = AppColors.gold;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await runSchedulingSetupWizard(context);
          if (mounted) await _refresh();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.settings, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                l10n.schedulingFinishSetupAction,
                style: TextStyle(
                  color: widget.theme.foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final Color color;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: theme.foreground)),
        ],
      ),
    );
  }
}
