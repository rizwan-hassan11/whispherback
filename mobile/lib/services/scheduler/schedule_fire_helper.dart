import '../../domain/entities/playback_schedule.dart';

/// Computes when schedules should fire and when the next whisper is due.
abstract final class ScheduleFireHelper {
  /// Whether [now] falls inside today's start/end window for [schedule].
  static bool isInWindow(PlaybackSchedule schedule, DateTime now) {
    if (!schedule.enabled) return false;
    if (!schedule.runsOnWeekday(now.weekday)) return false;

    final startToday = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.startTime.hour,
      schedule.startTime.minute,
    );
    if (now.isBefore(startToday)) return false;

    if (schedule.endTime != null) {
      final endToday = DateTime(
        now.year,
        now.month,
        now.day,
        schedule.endTime!.hour,
        schedule.endTime!.minute,
      );
      if (now.isAfter(endToday)) return false;
    }
    return true;
  }

  /// Start of the current interval slot (aligned to start + k×interval).
  static DateTime? currentSlot(PlaybackSchedule schedule, DateTime now) {
    if (!isInWindow(schedule, now)) return null;

    final startToday = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.startTime.hour,
      schedule.startTime.minute,
    );
    final elapsedMin = now.difference(startToday).inMinutes;
    if (elapsedMin < 0) return null;

    final slotIndex = elapsedMin ~/ schedule.intervalMinutes;
    return startToday.add(
      Duration(minutes: slotIndex * schedule.intervalMinutes),
    );
  }

  /// True when a whisper should fire now (grid-aligned, respects [lastFired]).
  static bool shouldFireNow(
    PlaybackSchedule schedule,
    DateTime now,
    DateTime? lastFired,
  ) {
    final slot = currentSlot(schedule, now);
    if (slot == null) return false;
    if (now.isBefore(slot)) return false;

    // Already handled this slot.
    if (lastFired != null && !lastFired.isBefore(slot)) return false;

    // Grace window: engine polls every 10s — allow catching the slot for ~12 min
    // so a slow poll doesn't skip an entire interval.
    if (now.difference(slot).inMinutes > schedule.intervalMinutes + 2) {
      return false;
    }
    return true;
  }

  /// Next fire time for one schedule (today or a future weekday).
  static DateTime? nextFireTime(PlaybackSchedule schedule, DateTime now) {
    if (!schedule.enabled) return null;

    for (var dayOffset = 0; dayOffset < 14; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      if (!schedule.runsOnWeekday(day.weekday)) continue;

      final startToday = DateTime(
        day.year,
        day.month,
        day.day,
        schedule.startTime.hour,
        schedule.startTime.minute,
      );

      DateTime? endToday;
      if (schedule.endTime != null) {
        endToday = DateTime(
          day.year,
          day.month,
          day.day,
          schedule.endTime!.hour,
          schedule.endTime!.minute,
        );
      }

      var slot = startToday;
      while (true) {
        if (endToday != null && slot.isAfter(endToday)) break;
        if (slot.isAfter(now) || slot.isAtSameMomentAs(now)) {
          return slot;
        }
        slot = slot.add(Duration(minutes: schedule.intervalMinutes));
        if (endToday == null && slot.day != day.day) break;
      }
    }
    return null;
  }

  /// Earliest upcoming fire across all schedules.
  static ({DateTime when, PlaybackSchedule schedule})? nextUpcoming(
    List<PlaybackSchedule> schedules,
    DateTime now,
  ) {
    ({DateTime when, PlaybackSchedule schedule})? best;
    for (final s in schedules) {
      if (!s.enabled) continue;
      final when = nextFireTime(s, now);
      if (when == null) continue;
      if (best == null || when.isBefore(best.when)) {
        best = (when: when, schedule: s);
      }
    }
    return best;
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
          ? DateTime(
              slot.year,
              slot.month,
              slot.day,
              schedule.endTime!.hour,
              schedule.endTime!.minute,
            )
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
