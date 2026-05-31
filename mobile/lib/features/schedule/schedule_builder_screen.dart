import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/premium_screen_background.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/settings_provider.dart';

class ScheduleBuilderScreen extends ConsumerStatefulWidget {
  const ScheduleBuilderScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<ScheduleBuilderScreen> createState() => _ScheduleBuilderScreenState();
}

class _ScheduleBuilderScreenState extends ConsumerState<ScheduleBuilderScreen> {
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? _endTime = const TimeOfDay(hour: 21, minute: 0);
  int _intervalMinutes = 30;
  bool _shuffle = false;
  bool _alarm = true;
  int _daysMask = 127;
  bool _loading = true;
  String _playlistName = '';

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
    setState(() {
      _playlistName = playlist?.name ?? l10n.playlist;
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
        final prefs = await ref.read(sharedPreferencesProvider.future);
        _alarm = prefs.getBool('default_alarm') ?? true;
        _intervalMinutes = prefs.getInt('default_interval') ?? 30;
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
    final start = _todayAt(_startTime);
    final end = _endTime != null ? _todayAt(_endTime!) : null;

    try {
      await ref.read(scheduleRepositoryProvider).save(
            playlistId: widget.playlistId,
            startTime: start,
            endTime: end,
            intervalMinutes: _intervalMinutes,
            shuffleEnabled: _shuffle,
            alarmEnabled: _alarm,
            daysMask: _daysMask,
          );
      ref.invalidate(schedulesProvider);
      ref.invalidate(playlistsProvider);
      if (mounted) {
        final l10n = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_alarm ? l10n.scheduleSavedWithAlarm : l10n.scheduleSaved),
          ),
        );
        context.pop();
      }
    } on ScheduleConflictException catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.scheduleConflict),
          content: Text(l10n.scheduleConflictMessage(e.existingPlaylistName)),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.ok)),
          ],
        ),
      );
    }
  }

  Future<void> _remove() async {
    await ref.read(scheduleRepositoryProvider).remove(widget.playlistId);
    ref.invalidate(schedulesProvider);
    ref.invalidate(playlistsProvider);
    if (mounted) context.pop();
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
              child: Text(l10n.remove, style: TextStyle(color: AppColors.error)),
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
                    child: Material(
                      color: on ? AppColors.brand : theme.glass,
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
              children: _intervalPresets.map((m) {
                final selected = _intervalMinutes == m;
                final label = l10n.intervalLabel(m);
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _intervalMinutes = m),
                  selectedColor: AppColors.brandLight.withValues(alpha: 0.25),
                  backgroundColor: theme.glass,
                  side: BorderSide(
                    color: selected ? AppColors.brandLight : theme.glassBorder,
                  ),
                );
              }).toList(),
            ),
            Slider(
              value: _intervalMinutes.toDouble(),
              min: 5,
              max: 180,
              divisions: 35,
              label: l10n.durationMin(_intervalMinutes),
              onChanged: (v) => setState(() => _intervalMinutes = v.round()),
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
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(l10n.saveSchedule),
            ),
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
              Icon(icon, color: AppColors.gold, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: theme.muted)),
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
          secondary: Icon(icon, color: AppColors.brandLight),
          title: Text(title, style: TextStyle(color: theme.foreground, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: theme.muted)),
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.brandLight,
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
