import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/layout/shell_messenger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_error_view.dart';
import '../../core/widgets/whisper_card.dart';
import '../../domain/entities/playback_schedule.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/schedule_l10n.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/notifications/notification_sync.dart';
import '../../services/scheduler/schedule_countdown.dart';
import '../../services/scheduler/schedule_fire_helper.dart';
import '../../services/scheduler/schedule_last_fired_store.dart';

class ScheduledOverviewScreen extends ConsumerWidget {
  const ScheduledOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(schedulesProvider);
    final isActiveAsync = ref.watch(isAppActiveProvider);
    final theme = whisperTheme(context);
    final locale = Localizations.localeOf(context).toString();
    final timeFmt = DateFormat.jm(locale);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: theme.isDark
                  ? [AppColors.deep2, AppColors.deep]
                  : [AppColors.lightBg, AppColors.lightBg2],
            ),
          ),
        ),
        _ScheduleAmbience(isDark: theme.isDark),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: schedulesAsync.when(
              data: (schedules) => _ScheduleBody(
                schedules: schedules,
                theme: theme,
                timeFmt: timeFmt,
                onResync: () => syncWhisperNotifications(
                  appState: ref.read(appStateRepositoryProvider),
                  schedules: ref.read(scheduleRepositoryProvider),
                  prayer: ref.read(prayerRepositoryProvider),
                ),
                // True when the user has at least one ENABLED schedule but
                // the master Active toggle is off — surfaces the banner that
                // explains why nothing is firing (the #1 production support
                // ticket).
                showActiveOffWarning: schedules.any((s) => s.enabled) &&
                    (isActiveAsync.valueOrNull == false),
                onCreate: () => context.go('/playlists'),
                onEdit: (id) => context.push('/schedule/build/$id'),
                onActivate: () async {
                  final coordinator = ref.read(playbackCoordinatorProvider);
                  await coordinator.toggleActive();
                  ref.invalidate(isAppActiveProvider);
                  if (!context.mounted) return;
                  context.showShellSnackBar(
                    context.l10n.schedulesActivatedSnackbar,
                    icon: AppIcons.checkCircle,
                  );
                },
                onToggle: (s, enabled) async {
                  await ref
                      .read(scheduleRepositoryProvider)
                      .setEnabled(s.playlistId, enabled);
                  // If the user disables a schedule whose clip is currently
                  // playing, stop immediately instead of waiting up to 5s
                  // for the next engine tick to notice and tear it down.
                  if (!enabled) {
                    final coordinator = ref.read(playbackCoordinatorProvider);
                    if (coordinator.activeScheduleId == s.id) {
                      await coordinator.stop();
                    }
                  }
                  ref.invalidate(schedulesProvider);
                  await syncWhisperNotifications(
                    appState: ref.read(appStateRepositoryProvider),
                    schedules: ref.read(scheduleRepositoryProvider),
                    prayer: ref.read(prayerRepositoryProvider),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AsyncErrorView(
                error: e,
                onRetry: () => ref.invalidate(schedulesProvider),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleAmbience extends StatelessWidget {
  const _ScheduleAmbience({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -20,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    AppColors.brandLight.withValues(alpha: isDark ? 0.1 : 0.06),
              ),
            ),
          ),
          Positioned(
            top: 140,
            left: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    AppColors.success.withValues(alpha: isDark ? 0.08 : 0.07),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleBody extends StatefulWidget {
  const _ScheduleBody({
    required this.schedules,
    required this.theme,
    required this.timeFmt,
    required this.onCreate,
    required this.onEdit,
    required this.onToggle,
    required this.showActiveOffWarning,
    required this.onActivate,
    required this.onResync,
  });

  final List<PlaybackSchedule> schedules;
  final WhisperThemeExtension theme;
  final DateFormat timeFmt;
  final VoidCallback onCreate;
  final ValueChanged<String> onEdit;
  final void Function(PlaybackSchedule schedule, bool enabled) onToggle;
  final bool showActiveOffWarning;
  final Future<void> Function() onActivate;
  // Re-syncs the persistent notification so the headline "next at"
  // matches the page's countdown. Called on initial frame so the
  // user never sees a stale time when they open this page.
  final Future<void> Function() onResync;

  @override
  State<_ScheduleBody> createState() => _ScheduleBodyState();
}

class _ScheduleBodyState extends State<_ScheduleBody> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Force an immediate notification re-sync when this page is first
    // opened so the headline "next at" stamp on the persistent
    // notification matches whatever the page now displays. Without
    // this, the user routinely sees a 30-60s drift between the two
    // surfaces (notification was last synced when the engine ticked
    // ~5 minutes ago; the page is computing live).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        unawaited(widget.onResync());
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  int get _alarmCount => widget.schedules.where((s) => s.alarmEnabled).length;

  int get _activeCount => widget.schedules.where((s) => s.enabled).length;

  String _countdownFor(PlaybackSchedule schedule, AppLocalizations l10n) {
    if (!schedule.enabled) return l10n.paused;
    final now = DateTime.now();
    final store = ScheduleLastFiredStore.instance;
    // forDisplay: true ensures we never show a past time as the "next"
    // countdown — the engine's lateness grace window made that surface
    // through previously and the user reported "schedule page says next
    // in 1:18 but it's already 1:20". Passing both slot + completion
    // lets the helper do real interval-from-end math.
    final next = ScheduleFireHelper.nextFireTime(
      schedule,
      now,
      lastFired: store.completion(schedule.id),
      lastSlot: store.slot(schedule.id),
      forDisplay: true,
    );
    return ScheduleCountdown.untilTime(next, now);
  }

  String _globalNextCountdown() {
    final now = DateTime.now();
    final enabled =
        widget.schedules.where((s) => s.enabled).toList(growable: false);
    final store = ScheduleLastFiredStore.instance;
    DateTime? best;
    for (final s in enabled) {
      final when = ScheduleFireHelper.nextFireTime(
        s,
        now,
        lastFired: store.completion(s.id),
        lastSlot: store.slot(s.id),
        forDisplay: true,
      );
      if (when == null) continue;
      if (best == null || when.isBefore(best)) best = when;
    }
    return ScheduleCountdown.untilTime(best, now);
  }

  /// Up to 5 upcoming fires across all schedules, sorted chronologically.
  /// Round 19: surfaces the table the user asked for so the schedule page
  /// shows the FULL upcoming queue instead of just the single next slot.
  List<({DateTime when, String playlistName})> _upcomingFires() {
    final store = ScheduleLastFiredStore.instance;
    return ScheduleFireHelper.upcomingEvents(
      widget.schedules,
      DateTime.now(),
      lastFiredFor: (id) => store.completion(id),
      lastSlotFor: (id) => store.slot(id),
      limit: 5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final schedules = widget.schedules;
    final theme = widget.theme;
    final timeFmt = widget.timeFmt;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.schedules,
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: theme.foreground,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  schedules.isEmpty
                      ? l10n.noSchedulesYet
                      : '$_activeCount ${l10n.active.toLowerCase()} · $_alarmCount ${l10n.alarms.toLowerCase()}',
                  style: TextStyle(fontSize: 13, color: theme.muted),
                ),
                const SizedBox(height: 18),
                if (schedules.isNotEmpty)
                  _StatsRow(
                    theme: theme,
                    active: _activeCount,
                    alarms: _alarmCount,
                    nextLabel: _globalNextCountdown(),
                  ),
                if (_upcomingFires().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _UpcomingFiresList(
                    theme: theme,
                    timeFmt: timeFmt,
                    upcoming: _upcomingFires(),
                  ),
                ],
                if (schedules.isNotEmpty) const SizedBox(height: 16),
                // High-visibility banner: enabled schedules exist but the
                // master Active toggle is OFF, so the engine is silently
                // skipping every tick. Without this, users assume the
                // scheduling code is broken and file support tickets.
                if (widget.showActiveOffWarning) ...[
                  _ActiveOffBanner(
                    theme: theme,
                    onActivate: widget.onActivate,
                  ),
                  const SizedBox(height: 16),
                ],
                _CustomizeAction(theme: theme, onTap: widget.onCreate),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.yourSchedules,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.35,
                        color: theme.muted,
                      ),
                    ),
                    if (schedules.isNotEmpty)
                      Text(
                        l10n.itemsCount(schedules.length),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.muted.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (schedules.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.schedule, size: 48, color: theme.muted),
                  const SizedBox(height: 16),
                  Text(
                    l10n.planYourWhispers,
                    style: GoogleFonts.fraunces(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: theme.foreground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.customizeScheduleSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: theme.muted, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, context.shellScrollPadding.bottom),
            sliver: SliverList.separated(
              itemCount: schedules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = schedules[i];
                return _ScheduleCard(
                  schedule: s,
                  theme: theme,
                  timeFmt: timeFmt,
                  nextCountdown: _countdownFor(s, l10n),
                  onEdit: () => widget.onEdit(s.playlistId),
                  onToggle: (v) => widget.onToggle(s, v),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.theme,
    required this.active,
    required this.alarms,
    required this.nextLabel,
  });

  final WhisperThemeExtension theme;
  final int active;
  final int alarms;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _StatCell(
            theme: theme,
            icon: AppIcons.schedule,
            value: '$active',
            label: l10n.active,
            iconColor: AppColors.brandLight,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCell(
            theme: theme,
            icon: AppIcons.alarm,
            value: '$alarms',
            label: l10n.alarms,
            iconColor: AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCell(
            theme: theme,
            icon: AppIcons.play,
            value: nextLabel,
            label: l10n.next,
            iconColor: AppColors.success,
            valueColor: AppColors.success,
            compactValue: true,
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.theme,
    required this.icon,
    required this.value,
    required this.label,
    required this.iconColor,
    this.valueColor,
    this.compactValue = false,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;
  final Color? valueColor;
  final bool compactValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.glassBorder),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compactValue ? 15 : 17,
              fontWeight: FontWeight.w800,
              color: valueColor ?? theme.foreground,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, color: theme.muted)),
        ],
      ),
    );
  }
}

class _CustomizeAction extends StatelessWidget {
  const _CustomizeAction({required this.theme, required this.onTap});

  final WhisperThemeExtension theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            color: theme.isDark ? theme.glass : Colors.white,
            border: Border.all(
              color: theme.isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : theme.glassBorder,
            ),
            boxShadow: theme.isDark
                ? null
                : [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: theme.isDark
                        ? [AppColors.brand, AppColors.brandDark]
                        : [AppColors.ink, AppColors.inkSecondary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(
                        alpha: theme.isDark ? 0.2 : 0.18,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  AppIcons.add,
                  color: theme.isDark ? AppColors.deep : AppColors.lightBg,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.customizeSchedule,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: theme.foreground,
                      ),
                    ),
                    Text(
                      l10n.customizeScheduleSubtitle,
                      style: TextStyle(fontSize: 12, color: theme.muted),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, color: theme.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.theme,
    required this.timeFmt,
    required this.nextCountdown,
    required this.onEdit,
    required this.onToggle,
  });

  final PlaybackSchedule schedule;
  final WhisperThemeExtension theme;
  final DateFormat timeFmt;
  final String nextCountdown;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final endLabel =
        schedule.endTime != null ? timeFmt.format(schedule.endTime!) : null;
    final timeLine =
        '${timeFmt.format(schedule.startTime)}${endLabel != null ? ' – $endLabel' : ''} · ${schedule.intervalLabelL10n(context)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.isDark ? theme.glass : Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(
              color: schedule.enabled
                  ? AppColors.success.withValues(alpha: 0.28)
                  : theme.glassBorder,
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
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: theme.isDark
                              ? [AppColors.brand, AppColors.brandDark]
                              : [AppColors.ink, AppColors.inkSecondary],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(
                              alpha: theme.isDark ? 0.2 : 0.18,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        AppIcons.playlists,
                        color:
                            theme.isDark ? AppColors.deep : AppColors.lightBg,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            schedule.playlistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: theme.foreground,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            timeLine,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: schedule.enabled,
                      onChanged: onToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    WhisperBadge(
                      label: schedule.daysLabelL10n(context),
                      variant: WhisperBadgeVariant.brand,
                    ),
                    if (schedule.alarmEnabled)
                      WhisperBadge(
                        label: l10n.alarmOn,
                        variant: WhisperBadgeVariant.gold,
                      ),
                    if (schedule.shuffleEnabled)
                      WhisperBadge(
                        label: l10n.shuffle,
                        variant: WhisperBadgeVariant.gold,
                      ),
                  ],
                ),
                Divider(height: 25, color: theme.glassBorder),
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 12, color: theme.muted),
                          children: [
                            TextSpan(text: l10n.nextWhisperIn),
                            TextSpan(
                              text: nextCountdown,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: theme.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onEdit,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.edit,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.isDark
                                  ? AppColors.brandLight
                                  : AppColors.ink,
                            ),
                          ),
                          Icon(
                            AppIcons.chevronRight,
                            size: 14,
                            color: theme.isDark
                                ? AppColors.brandLight
                                : AppColors.ink,
                          ),
                        ],
                      ),
                    ),
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

/// Persistent banner shown on the schedule overview when at least one
/// schedule is enabled but the master Active toggle is OFF. Without this,
/// users assume "save succeeded" means "will play" and blame the scheduling
/// engine when nothing fires — they had no idea the foreground service was
/// gated behind a separate toggle on the Home tab.
class _ActiveOffBanner extends StatefulWidget {
  const _ActiveOffBanner({required this.theme, required this.onActivate});

  final WhisperThemeExtension theme;
  final Future<void> Function() onActivate;

  @override
  State<_ActiveOffBanner> createState() => _ActiveOffBannerState();
}

class _ActiveOffBannerState extends State<_ActiveOffBanner> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;
    // Bright amber so the banner reads as "needs attention" without
    // looking like a destructive error. Theming kept identical in light
    // and dark — accessibility constraints (4.5:1 against the foreground
    // text) are satisfied because we render copy in `theme.foreground`,
    // not on top of the accent fill.
    const accent = Color(0xFFE0A800);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        color: accent.withValues(alpha: theme.isDark ? 0.14 : 0.10),
        border: Border.all(
          color: accent.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(AppIcons.alertCircle, color: accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.schedulesActiveOffTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: theme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.schedulesActiveOffBody,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await widget.onActivate();
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.checkCircle, size: 16),
              label: Text(l10n.schedulesActiveOffActivate),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "next 5 fires" table shown above the per-schedule cards.
/// Round 19: user explicitly asked for a table of upcoming schedules,
/// not just the single next slot. We compute it from
/// [ScheduleFireHelper.upcomingEvents] (which already respects
/// interval-from-end semantics and per-schedule last-fired stamps),
/// then render compactly so the rest of the page remains scannable.
class _UpcomingFiresList extends StatelessWidget {
  const _UpcomingFiresList({
    required this.theme,
    required this.timeFmt,
    required this.upcoming,
  });

  final WhisperThemeExtension theme;
  final DateFormat timeFmt;
  final List<({DateTime when, String playlistName})> upcoming;

  @override
  Widget build(BuildContext context) {
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color:
            theme.isDark ? theme.glass : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: theme.glassBorder),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                AppIcons.schedule,
                size: 14,
                color: AppColors.brandLight,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.upcomingWhispers,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: theme.muted,
                ),
              ),
              const Spacer(),
              Text(
                l10n.itemsCount(upcoming.length),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.muted.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < upcoming.length; i++)
            _UpcomingFireRow(
              theme: theme,
              timeFmt: timeFmt,
              when: upcoming[i].when,
              playlistName: upcoming[i].playlistName,
              relativeFromNow: _relative(upcoming[i].when, now, l10n),
              isLast: i == upcoming.length - 1,
            ),
        ],
      ),
    );
  }

  String _relative(DateTime when, DateTime now, AppLocalizations l10n) {
    final delta = when.difference(now);
    if (delta.isNegative) return l10n.now;
    if (delta.inMinutes < 1) return l10n.inSeconds(delta.inSeconds);
    if (delta.inMinutes < 60) return l10n.inMinutes(delta.inMinutes);
    if (delta.inHours < 24) {
      final hours = delta.inHours;
      final mins = delta.inMinutes.remainder(60);
      if (mins == 0) return l10n.inHours(hours);
      return '${l10n.inHours(hours)} ${l10n.inMinutes(mins)}';
    }
    return l10n.inDays(delta.inDays);
  }
}

class _UpcomingFireRow extends StatelessWidget {
  const _UpcomingFireRow({
    required this.theme,
    required this.timeFmt,
    required this.when,
    required this.playlistName,
    required this.relativeFromNow,
    required this.isLast,
  });

  final WhisperThemeExtension theme;
  final DateFormat timeFmt;
  final DateTime when;
  final String playlistName;
  final String relativeFromNow;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.brandLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              timeFmt.format(when),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.brandLight,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.foreground,
                  ),
                ),
                Text(
                  relativeFromNow,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
