import '../../domain/entities/playback_schedule.dart';

/// Computes when schedules should fire and when the next whisper is due.
abstract final class ScheduleFireHelper {
  /// Max lateness after a grid slot before we skip to the next interval.
  ///
  /// Previously 90s — too short for "user backgrounds the app, OS pauses
  /// the engine, user opens the app 2 minutes later, expected schedule
  /// hasn't fired". The QA report "the schedule page showed next whisper
  /// is NOW but no audio played" matched this exactly: the UI told the
  /// truth (slot was due) but `slotToFire` returned null because the
  /// engine missed the 90s window. 5 minutes gives the engine room to
  /// recover from a typical foreground/background bounce without
  /// silently skipping a slot.
  static const maxLateness = Duration(minutes: 5);

  /// Whether [now] falls inside today's start/end window for [schedule].
  static bool isInWindow(PlaybackSchedule schedule, DateTime now) {
    if (!schedule.enabled) return false;

    if (_isOvernight(schedule)) {
      final previousDay = now.subtract(const Duration(days: 1));
      if (schedule.runsOnWeekday(previousDay.weekday)) {
        final prevStart = _startOnDay(schedule, previousDay);
        final morningEnd = DateTime(
          now.year,
          now.month,
          now.day,
          schedule.endTime!.hour,
          schedule.endTime!.minute,
        );
        if (!now.isBefore(prevStart) && now.isBefore(morningEnd)) {
          return true;
        }
      }
    }

    if (!schedule.runsOnWeekday(now.weekday)) return false;

    final startToday = _startOnDay(schedule, now);
    if (now.isBefore(startToday)) return false;

    final endToday = _endOnDay(schedule, now);
    if (endToday != null && now.isAfter(endToday)) return false;
    return true;
  }

  static bool _isOvernight(PlaybackSchedule schedule) {
    if (schedule.endTime == null) return false;
    final startMinutes =
        schedule.startTime.hour * 60 + schedule.startTime.minute;
    final endMinutes = schedule.endTime!.hour * 60 + schedule.endTime!.minute;
    return endMinutes <= startMinutes;
  }

  static DateTime _startOnDay(PlaybackSchedule schedule, DateTime day) {
    return DateTime(
      day.year,
      day.month,
      day.day,
      schedule.startTime.hour,
      schedule.startTime.minute,
    );
  }

  static DateTime? _endOnDay(PlaybackSchedule schedule, DateTime day) {
    if (schedule.endTime == null) return null;
    final end = DateTime(
      day.year,
      day.month,
      day.day,
      schedule.endTime!.hour,
      schedule.endTime!.minute,
    );
    if (_isOvernight(schedule)) {
      return end.add(const Duration(days: 1));
    }
    return end;
  }

  /// Next grid slot after [lastFired], or [startToday] if never fired today.
  static DateTime? nextSlotAfter(
    PlaybackSchedule schedule,
    DateTime now, {
    DateTime? lastFired,
  }) {
    if (!schedule.enabled) return null;

    for (var dayOffset = 0; dayOffset < 14; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      if (!schedule.runsOnWeekday(day.weekday)) continue;

      final start = _startOnDay(schedule, day);
      final end = _endOnDay(schedule, day);

      var slot = start;
      if (lastFired != null) {
        final lastDay = DateTime(
          lastFired.year,
          lastFired.month,
          lastFired.day,
        );
        final onSameDay = lastDay.year == day.year &&
            lastDay.month == day.month &&
            lastDay.day == day.day;
        if (onSameDay && !lastFired.isBefore(start)) {
          slot = lastFired.add(Duration(minutes: schedule.intervalMinutes));
        }
      }

      while (true) {
        if (end != null && slot.isAfter(end)) break;
        if (dayOffset == 0 && slot.isBefore(now)) {
          // Skip slots we missed by too much — jump to next grid line.
          if (now.difference(slot) > maxLateness) {
            slot = slot.add(Duration(minutes: schedule.intervalMinutes));
            continue;
          }
        }
        if (dayOffset > 0 || !slot.isBefore(now)) {
          return slot;
        }
        if (now.difference(slot) <= maxLateness) return slot;
        slot = slot.add(Duration(minutes: schedule.intervalMinutes));
      }
    }
    return null;
  }

  /// Grid slot that should fire now, or null if nothing is due.
  static DateTime? slotToFire(
    PlaybackSchedule schedule,
    DateTime now,
    DateTime? lastFired,
  ) {
    if (!isInWindow(schedule, now)) return null;

    final slot = nextSlotAfter(schedule, now, lastFired: lastFired);
    if (slot == null) return null;
    if (now.isBefore(slot)) return null;

    final end = _endOnDay(schedule, now);
    if (end != null && slot.isAfter(end)) return null;

    if (now.difference(slot) > maxLateness) return null;

    if (lastFired != null && !slot.isAfter(lastFired)) return null;

    return slot;
  }

  static bool shouldFireNow(
    PlaybackSchedule schedule,
    DateTime now,
    DateTime? lastFired,
  ) =>
      slotToFire(schedule, now, lastFired) != null;

  /// Alias kept for callers that used [currentSlot].
  static DateTime? currentSlot(
    PlaybackSchedule schedule,
    DateTime now,
  ) =>
      slotToFire(schedule, now, null);

  /// Next fire time for one schedule (respects [lastFired]).
  static DateTime? nextFireTime(
    PlaybackSchedule schedule,
    DateTime now, {
    DateTime? lastFired,
  }) =>
      nextSlotAfter(schedule, now, lastFired: lastFired);

  /// Earliest upcoming fire across all schedules.
  static ({DateTime when, PlaybackSchedule schedule})? nextUpcoming(
    List<PlaybackSchedule> schedules,
    DateTime now, {
    DateTime? Function(String scheduleId)? lastFiredFor,
  }) {
    ({DateTime when, PlaybackSchedule schedule})? best;
    for (final s in schedules) {
      if (!s.enabled) continue;
      final last = lastFiredFor?.call(s.id);
      final when = nextFireTime(s, now, lastFired: last);
      if (when == null) continue;
      if (best == null || when.isBefore(best.when)) {
        best = (when: when, schedule: s);
      }
    }
    return best;
  }

  /// Upcoming grid fires across all schedules (sorted, de-duplicated by time).
  static List<({DateTime when, String playlistName})> upcomingEvents(
    List<PlaybackSchedule> schedules,
    DateTime now, {
    DateTime? Function(String scheduleId)? lastFiredFor,
    int limit = 4,
  }) {
    final events = <({DateTime when, String playlistName})>[];
    for (final s in schedules) {
      if (!s.enabled) continue;
      final last = lastFiredFor?.call(s.id);
      var slot = nextFireTime(s, now, lastFired: last);
      var hops = 0;
      while (slot != null && hops < limit * 2) {
        events.add((
          when: slot,
          playlistName: s.playlistName.isEmpty ? 'WhisperBack' : s.playlistName,
        ));
        slot = slot.add(Duration(minutes: s.intervalMinutes));
        final end = _endOnDay(s, slot);
        if (end != null && slot.isAfter(end)) break;
        hops++;
      }
    }
    events.sort((a, b) => a.when.compareTo(b.when));
    if (events.length <= limit) return events;
    return events.sublist(0, limit);
  }

  /// All weekly alarm slots (hour/minute) for notification scheduling.
  static Iterable<({int weekday, int hour, int minute, String label})>
      intervalAlarmSlots(PlaybackSchedule schedule) sync* {
    if (!schedule.enabled || !schedule.alarmEnabled) return;

    for (var weekday = 1; weekday <= 7; weekday++) {
      if (!schedule.runsOnWeekday(weekday)) continue;

      var slot = DateTime(
        2020,
        1,
        6 + weekday,
        schedule.startTime.hour,
        schedule.startTime.minute,
      );
      final end = schedule.endTime != null
          ? (_isOvernight(schedule)
              ? DateTime(
                  slot.year,
                  slot.month,
                  slot.day,
                  schedule.endTime!.hour,
                  schedule.endTime!.minute,
                ).add(const Duration(days: 1))
              : DateTime(
                  slot.year,
                  slot.month,
                  slot.day,
                  schedule.endTime!.hour,
                  schedule.endTime!.minute,
                ))
          : slot.add(const Duration(hours: 23, minutes: 59));

      while (!slot.isAfter(end)) {
        yield (
          weekday: weekday,
          hour: slot.hour,
          minute: slot.minute,
          label: schedule.playlistName,
        );
        slot = slot.add(Duration(minutes: schedule.intervalMinutes));
      }
    }
  }
}
