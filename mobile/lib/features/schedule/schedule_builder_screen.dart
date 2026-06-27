import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/shell_messenger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/premium_screen_background.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/notifications/notification_sync.dart';

class ScheduleBuilderScreen extends ConsumerStatefulWidget {
  const ScheduleBuilderScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<ScheduleBuilderScreen> createState() =>
      _ScheduleBuilderScreenState();
}

class _ScheduleBuilderScreenState extends ConsumerState<ScheduleBuilderScreen> {
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? _endTime = const TimeOfDay(hour: 21, minute: 0);
  int _intervalMinutes = 30;
  bool _shuffle = false;
  bool _alarm = true;
  int _daysMask = 127;
  bool _loading = true;
  bool _saving = false;
  String _playlistName = '';
  String? _existingScheduleId;

  static const _intervalPresets = [15, 30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final repo = ref.read(scheduleRepositoryProvider);
    final playlistRepo = ref.read(playlistRepositoryProvider);
    final playlist = await playlistRepo.getById(widget.playlistId);
    final existing = await repo.getForPlaylist(widget.playlistId);
    if (!mounted) return;
    final l10n = context.l10n;
    var alarm = true;
    var intervalMinutes = 30;
    if (existing == null) {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      alarm = prefs.getBool('default_alarm') ?? true;
      intervalMinutes = prefs.getInt('default_interval') ?? 30;
    }
    setState(() {
      _playlistName = playlist?.name ?? l10n.playlist;
      _existingScheduleId = existing?.id;
      if (existing != null) {
        _startTime = TimeOfDay.fromDateTime(existing.startTime);
        _endTime = existing.endTime != null
            ? TimeOfDay.fromDateTime(existing.endTime!)
            : null;
        _intervalMinutes = existing.intervalMinutes;
        _shuffle = existing.shuffleEnabled;
        _alarm = existing.alarmEnabled;
        _daysMask = existing.daysMask;
      } else {
        _alarm = alarm;
        _intervalMinutes = intervalMinutes;
      }
      _loading = false;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startTime : (_endTime ?? _startTime);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  /// Opens a small text-input dialog so the user can type ANY interval
  /// between 1 and 720 minutes. Validates client-side so the picker can
  /// never produce a value the schedule engine rejects.
  Future<void> _pickCustomInterval() async {
    final l10n = context.l10n;
    final theme = whisperTheme(context);
    final controller = TextEditingController(text: _intervalMinutes.toString());
    final formKey = GlobalKey<FormState>();

    // Build a SOLID background colour. `theme.surface` was a 10%-alpha
    // tint over the deep gradient on the main scaffold — fine inside a
    // glass card, but when an `AlertDialog` paints it ABOVE the dim
    // barrier you can see straight through to the home screen, which
    // the QA reported as "the popup is transparent". Use the same
    // opaque dialog surface the rest of the app uses (the
    // `audio_service_warning_banner` dialog and others).
    final dialogBg = theme.isDark ? AppColors.deep2 : Colors.white;
    final borderColor = theme.glassBorder;

    final picked = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: dialogBg,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderColor, width: 1),
          ),
          title: Text(
            l10n.customInterval,
            style: TextStyle(
              color: theme.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(color: theme.foreground),
              decoration: InputDecoration(
                labelText: l10n.intervalBetweenWhispers,
                labelStyle: TextStyle(color: theme.muted),
                helperText: l10n.customIntervalHelp,
                helperStyle: TextStyle(color: theme.muted, fontSize: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.neon,
                    width: 1.5,
                  ),
                ),
                suffixText: l10n.minutesUnit,
                suffixStyle: TextStyle(color: theme.muted),
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null) return l10n.customIntervalInvalid;
                if (n < 1) return l10n.customIntervalTooSmall;
                if (n > 720) return l10n.customIntervalTooLarge;
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(foregroundColor: theme.muted),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final n = int.parse(controller.text.trim());
                Navigator.of(ctx).pop(n);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.neon,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _intervalMinutes = picked);
    }
  }

  void _toggleDay(int bit) {
    setState(() {
      if ((_daysMask & (1 << bit)) != 0) {
        _daysMask &= ~(1 << bit);
        if (_daysMask == 0) _daysMask = 1 << bit;
      } else {
        _daysMask |= 1 << bit;
      }
    });
  }

  DateTime _todayAt(TimeOfDay t) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final start = _todayAt(_startTime);
    final end = _endTime != null ? _todayAt(_endTime!) : null;

    // Step 1 — persist the schedule. Only this DB write may legitimately fail
    // with a user-visible error (e.g. overlap with another schedule).
    bool persisted = false;
    try {
      await ref.read(scheduleRepositoryProvider).save(
            id: _existingScheduleId,
            playlistId: widget.playlistId,
            startTime: start,
            endTime: end,
            intervalMinutes: _intervalMinutes,
            shuffleEnabled: _shuffle,
            alarmEnabled: _alarm,
            daysMask: _daysMask,
          );
      persisted = true;
    } on ScheduleConflictException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final l10n = context.l10n;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.scheduleConflict),
          content: Text(l10n.scheduleConflictMessage(e.existingPlaylistName)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Always show an error toast — silent failure was the original
      // "save schedule notification doesn't pop up" report.
      context.showShellSnackBar(
        context.l10n.genericErrorTryAgain,
        icon: AppIcons.alertCircle,
      );
      if (kDebugMode) {
        debugPrint('Schedule save failed: $e');
      }
      return;
    }

    // `persisted` exists for symmetry / future hooks but cannot be false here
    // because every catch branch above returns.
    assert(persisted);

    // Step 2 — refresh derived state. These are best-effort: a missing
    // notification permission or geolocator hiccup must NOT roll back the
    // save the user just made. `syncWhisperNotifications` already swallows
    // its own errors; we double-guard here so an unrelated exception in the
    // refresh path never surfaces a false "Something went wrong" toast.
    ref.invalidate(schedulesProvider);
    ref.invalidate(playlistsProvider);
    ref.invalidate(isAppActiveProvider);
    try {
      await syncWhisperNotifications(
        appState: ref.read(appStateRepositoryProvider),
        schedules: ref.read(scheduleRepositoryProvider),
        prayer: ref.read(prayerRepositoryProvider),
      );
    } catch (_) {
      // Already logged by syncWhisperNotifications; swallow here.
    }

    if (!mounted) {
      _saving = false;
      return;
    }
    setState(() => _saving = false);
    final l10n = context.l10n;

    // Branch: if Active is OFF, the user just saved a schedule that will not
    // fire. A fleeting snackbar (the previous behaviour) was easy to miss —
    // we hard-stop them with a dialog so the connection between "saved" and
    // "Active toggle" is impossible to miss. If Active is ON, fall back to
    // the quick snackbar so the save flow stays snappy.
    bool isActive = false;
    try {
      isActive = await ref.read(appStateRepositoryProvider).isActive();
    } catch (_) {
      // If we can't read the toggle, assume OFF so the user still sees the
      // explainer dialog rather than a silent return.
      isActive = false;
    }
    if (!mounted) return;
    if (!isActive) {
      final shouldActivate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.scheduleSavedDialogTitle),
          content: Text(l10n.scheduleSavedDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.scheduleSavedDialogLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.scheduleSavedDialogActivate),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (shouldActivate == true) {
        try {
          await ref.read(playbackCoordinatorProvider).toggleActive();
        } catch (_) {
          // Toggle failed — fall through so the user can retry from Home.
        }
        ref.invalidate(isAppActiveProvider);
        if (!mounted) return;
        context.showShellSnackBar(
          l10n.schedulesActivatedSnackbar,
          icon: AppIcons.checkCircle,
        );
      }
      if (mounted) context.pop();
      return;
    }

    context.pop();
    context.showShellSnackBar(
      l10n.scheduleSavedActiveOn,
      icon: AppIcons.checkCircle,
    );
  }

  Future<void> _remove() async {
    await ref.read(scheduleRepositoryProvider).remove(widget.playlistId);
    ref.invalidate(schedulesProvider);
    ref.invalidate(playlistsProvider);
    await syncWhisperNotifications(
      appState: ref.read(appStateRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
      prayer: ref.read(prayerRepositoryProvider),
    );
    if (mounted) {
      final l10n = context.l10n;
      context.pop();
      context.showShellSnackBar(l10n.scheduleRemoved,
          icon: AppIcons.checkCircle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = whisperTheme(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PremiumScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            l10n.customize,
            style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton(
              onPressed: _remove,
              child: Text(l10n.remove,
                  style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text(
              _playlistName,
              style: GoogleFonts.fraunces(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: theme.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.setWhenWhispersPlay,
              style: TextStyle(color: theme.muted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.timeWindow, theme: theme),
            const SizedBox(height: 10),
            _TimeTile(
              theme: theme,
              label: l10n.startTime,
              value: _startTime.format(context),
              icon: AppIcons.sun,
              onTap: () => _pickTime(isStart: true),
            ),
            const SizedBox(height: 8),
            _TimeTile(
              theme: theme,
              label: l10n.endTime,
              value: _endTime?.format(context) ?? l10n.noEnd,
              icon: AppIcons.moon,
              onTap: () => _pickTime(isStart: false),
              trailing: _endTime != null
                  ? IconButton(
                      icon: Icon(AppIcons.close, size: 18, color: theme.muted),
                      onPressed: () => setState(() => _endTime = null),
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.repeatDays, theme: theme),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final labels = l10n.weekdayShortLabels;
                final on = (_daysMask & (1 << i)) != 0;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 6 ? 6 : 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: on ? AppColors.neonGradient : null,
                        color: on ? null : theme.glass,
                        border: Border.all(
                          color: on
                              ? Colors.white.withValues(alpha: 0.25)
                              : theme.glassBorder,
                        ),
                        boxShadow: on
                            ? [
                                BoxShadow(
                                  color: AppColors.neon.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _toggleDay(i),
                          child: SizedBox(
                            height: 40,
                            child: Center(
                              child: Text(
                                labels[i],
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: on ? Colors.white : theme.muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _PresetChip(
                  label: l10n.everyDay,
                  onTap: () => setState(() => _daysMask = 127),
                ),
                _PresetChip(
                  label: l10n.weekdays,
                  onTap: () => setState(() => _daysMask = 31),
                ),
                _PresetChip(
                  label: l10n.weekends,
                  onTap: () => setState(() => _daysMask = 96),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.intervalBetweenWhispers, theme: theme),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._intervalPresets.map((m) {
                  final selected = _intervalMinutes == m;
                  final label = l10n.intervalLabel(m);
                  return ChoiceChip(
                    label: Text(label),
                    labelStyle: TextStyle(
                      color: selected ? AppColors.neonBright : theme.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _intervalMinutes = m),
                    selectedColor: AppColors.neon.withValues(alpha: 0.18),
                    backgroundColor: theme.glass,
                    side: BorderSide(
                      color: selected ? AppColors.neon : theme.glassBorder,
                    ),
                  );
                }),
                // Explicit "Custom" chip opens a text-input dialog so the
                // user can type any value 1–720 min. The slider below is
                // still there for quick fine-tuning, but the dialog gives
                // a clear "I want a specific minute" affordance the user
                // asked for ("no option for custom time").
                ActionChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.edit,
                        size: 14,
                        color: !_intervalPresets.contains(_intervalMinutes)
                            ? AppColors.neonBright
                            : theme.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        !_intervalPresets.contains(_intervalMinutes)
                            ? l10n.intervalLabel(_intervalMinutes)
                            : l10n.customInterval,
                        style: TextStyle(
                          color: !_intervalPresets.contains(_intervalMinutes)
                              ? AppColors.neonBright
                              : theme.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  onPressed: _pickCustomInterval,
                  backgroundColor: !_intervalPresets.contains(_intervalMinutes)
                      ? AppColors.neon.withValues(alpha: 0.18)
                      : theme.glass,
                  side: BorderSide(
                    color: !_intervalPresets.contains(_intervalMinutes)
                        ? AppColors.neon
                        : theme.glassBorder,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Slider for fine-tuning. Keeps the dial visible so the user
            // sees the current value at a glance + can drag without
            // opening a dialog.
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _intervalMinutes.toDouble().clamp(1, 180),
                    min: 1,
                    max: 180,
                    divisions: 179,
                    label: l10n.durationMin(_intervalMinutes),
                    onChanged: (v) =>
                        setState(() => _intervalMinutes = v.round()),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.glass,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.glassBorder),
                  ),
                  child: Text(
                    l10n.durationMin(_intervalMinutes),
                    style: TextStyle(
                      color: theme.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionTitle(l10n.playbackAndAlarms, theme: theme),
            const SizedBox(height: 8),
            _SwitchTile(
              theme: theme,
              icon: AppIcons.shuffle,
              title: l10n.shuffleClips,
              subtitle: l10n.shuffleClipsSubtitle,
              value: _shuffle,
              onChanged: (v) => setState(() => _shuffle = v),
            ),
            _SwitchTile(
              theme: theme,
              icon: AppIcons.alarm,
              title: l10n.alarmNotification,
              subtitle: l10n.alarmNotificationSubtitle,
              value: _alarm,
              onChanged: (v) => setState(() => _alarm = v),
            ),
            const SizedBox(height: 28),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _saving ? 0.85 : 1.0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.neonGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neon
                          .withValues(alpha: _saving ? 0.25 : 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_saving) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(l10n.savingSchedule),
                      ] else ...[
                        const Icon(AppIcons.checkCircle,
                            size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(l10n.saveSchedule),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.theme});

  final String text;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: theme.muted,
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.theme,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  final WhisperThemeExtension theme;
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.glassBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.neonBright, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(fontSize: 12, color: theme.muted)),
                    Text(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: theme.foreground,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              Icon(AppIcons.chevronRight, color: theme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.glassBorder),
        ),
        child: SwitchListTile(
          secondary: Icon(icon, color: AppColors.neonBright),
          title: Text(title,
              style: TextStyle(
                  color: theme.foreground, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle,
              style: TextStyle(fontSize: 12, color: theme.muted)),
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.neon,
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppColors.glass,
      side: const BorderSide(color: AppColors.glassBorder),
    );
  }
}
