import '../../domain/entities/playback_schedule.dart';

/// Computes when schedules should fire and when the next whisper is due.
abstract final class ScheduleFireHelper {
  /// Max lateness after a grid slot before we skip to the next interval.
  ///
  /// Round 19: dropped from 15 minutes back to 2 minutes. The wider
  /// window introduced in Round 17 caused the user's exact QA report
  /// "7 minutes remaining for next whisper but after 1 minute the clip
  /// played automatically — must have been a missed previous slot".
  /// With a 15-minute window, ANY slot the engine missed in the last
  /// 15 minutes still fires the moment the user opens the app, which
  /// from the user's perspective feels like the schedule went off at
  /// random.
  ///
  /// 2 minutes is the sweet spot: long enough to absorb a 30-60 s engine
  /// stutter (audio_service rebind, brief Doze) without skipping the slot,
  /// short enough that re-opening the app well after a missed fire
  /// doesn't cause a "phantom" surprise play.
  ///
  /// The QA scenario that originally pushed this to 15 (alarm fires →
  /// user taps several minutes later → schedule skipped) is now
  /// addressed by `fireNow()` from the notification action: the engine
  /// re-evaluates and fires the slot synchronously when the user taps
  /// the alarm body, regardless of lateness.
  static const maxLateness = Duration(minutes: 2);

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
  /// Returns the next slot at or after [now]. If [forDisplay] is true, the
  /// function will NEVER return a past slot even if it's within the
  /// `maxLateness` grace window — it always advances to the strictly-
  /// future grid line.
  ///
  /// Background: the engine uses the lateness grace ("a slot that's 2
  /// minutes in the past is still firable") to avoid skipping fires when
  /// the device was throttled. But that same path is wrong for display:
  /// the user sees the notification headline "Next at 1:18" when it's
  /// actually 1:20 already, and that's misleading. The schedule overview
  /// screen and notification headline both pass `forDisplay: true` so
  /// the timestamp shown is always in the future. `slotToFire` /
  /// `shouldFireNow` continue to use the grace window (forDisplay: false,
  /// the default) so engine firing logic is unchanged.
  ///
  /// [lastSlot] is the wall-clock start of the previous fire. [lastFired]
  /// is the actual completion (or null if not completed yet). When both
  /// are provided, the helper picks the larger of `lastFired` and
  /// `lastSlot + playlistDuration` as the projected end and computes
  /// `next = projectedEnd + interval`. When only [lastFired] is
  /// provided, the projection falls back to `lastFired + duration +
  /// interval` (best-effort; matches the engine's "still firing"
  /// expectation).
  static DateTime? nextSlotAfter(
    PlaybackSchedule schedule,
    DateTime now, {
    DateTime? lastFired,
    DateTime? lastSlot,
    bool forDisplay = false,
    bool force = false,
  }) {
    if (!schedule.enabled) return null;

    for (var dayOffset = 0; dayOffset < 14; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      if (!schedule.runsOnWeekday(day.weekday)) continue;

      final start = _startOnDay(schedule, day);
      final end = _endOnDay(schedule, day);

      var slot = start;
      // Pick the more authoritative reference for "end of previous fire".
      final referenceFired = lastFired ?? lastSlot;
      if (referenceFired != null) {
        final lastDay = DateTime(
          referenceFired.year,
          referenceFired.month,
          referenceFired.day,
        );
        final onSameDay = lastDay.year == day.year &&
            lastDay.month == day.month &&
            lastDay.day == day.day;
        if (onSameDay && !referenceFired.isBefore(start)) {
          // Interval-from-end semantics: the user's expectation is
          // "wait `intervalMinutes` AFTER the previous playlist
          // finishes, not after it starts".
          //
          // Two cases:
          //   1. Previous fire completed cleanly. `lastFired` is the
          //      actual completion time, which is approximately
          //      `lastSlot + playlistDuration` (possibly slightly
          //      later due to load/OS jitter). We use `lastFired` as
          //      the projected end directly.
          //   2. Previous fire still in flight. `lastFired` equals
          //      `lastSlot` (the engine writes that placeholder at
          //      fire start). We need to project: end ≈ slot + duration.
          //
          // Detection rule:
          //   - If `lastFired != null` AND `lastFired > (lastSlot ?? 0)`
          //     by at least a few seconds, treat case 1.
          //   - Else (lastFired == lastSlot, or only lastSlot given),
          //     treat case 2 — project end.
          DateTime projectedEnd;
          const placeholderTolerance = Duration(seconds: 5);
          if (lastFired != null &&
              lastSlot != null &&
              lastFired.difference(lastSlot) > placeholderTolerance) {
            // Case 1: real completion known.
            projectedEnd = lastFired;
          } else {
            // Case 2: still playing or only the slot stamp exists.
            final base = referenceFired;
            projectedEnd = base.add(
              Duration(milliseconds: schedule.playlistDurationMs),
            );
          }
          slot = projectedEnd.add(Duration(minutes: schedule.intervalMinutes));
        }
      }

      // Round 15: step between grid slots = playlistDuration + interval.
      // This is the same effective step used by `intervalAlarmSlots`
      // so the engine, alarm scheduler, and display all agree on what
      // the next grid line is.
      final stepDuration = Duration(minutes: effectiveStepMinutes(schedule));

      while (true) {
        if (end != null && slot.isAfter(end)) break;
        if (dayOffset == 0 && slot.isBefore(now)) {
          // Skip past slots: under display mode, always advance; under
          // engine mode, only skip slots beyond the grace window.
          // Round 19: when `force` is set, also keep past slots so the
          // alarm-tap path can recover a slot the OS missed by minutes.
          if (forDisplay || (!force && now.difference(slot) > maxLateness)) {
            slot = slot.add(stepDuration);
            continue;
          }
        }
        if (dayOffset > 0 || !slot.isBefore(now)) {
          return slot;
        }
        if (!forDisplay && (force || now.difference(slot) <= maxLateness)) {
          return slot;
        }
        slot = slot.add(stepDuration);
      }
    }
    return null;
  }

  /// Grid slot that should fire now, or null if nothing is due.
  ///
  /// [lastFired] is the completion timestamp of the previous fire (or the
  /// slot start if playback never completed). [lastSlot] is the wall-clock
  /// start of the previous fire — passing it lets `nextSlotAfter` know
  /// whether the playback completed cleanly (lastFired > lastSlot) or
  /// whether `lastFired` is still a placeholder (lastFired == lastSlot).
  /// Without [lastSlot] the helper always falls into the "project end"
  /// branch and over-counts the gap by `playlistDurationMs` — the user's
  /// Round 19 QA report ("schedule shows next at 10:11 but it's 10:15 and
  /// nothing played") was the helper computing `next = completion +
  /// playlistDuration + interval` when it should have been `next =
  /// completion + interval`.
  ///
  /// When [force] is true, the [maxLateness] cap is ignored. Used by the
  /// alarm-tap path so a user who taps a scheduled alarm 10 minutes
  /// late still gets the audio they came for.
  static DateTime? slotToFire(
    PlaybackSchedule schedule,
    DateTime now,
    DateTime? lastFired, {
    DateTime? lastSlot,
    bool force = false,
  }) {
    if (!isInWindow(schedule, now)) return null;

    final slot = nextSlotAfter(
      schedule,
      now,
      lastFired: lastFired,
      lastSlot: lastSlot,
      force: force,
    );
    if (slot == null) return null;
    if (now.isBefore(slot)) return null;

    final end = _endOnDay(schedule, now);
    if (end != null && slot.isAfter(end)) return null;

    if (!force && now.difference(slot) > maxLateness) return null;

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
    DateTime? lastSlot,
    bool forDisplay = false,
  }) =>
      nextSlotAfter(
        schedule,
        now,
        lastFired: lastFired,
        lastSlot: lastSlot,
        forDisplay: forDisplay,
      );

  /// Earliest upcoming fire across all schedules.
  static ({DateTime when, PlaybackSchedule schedule})? nextUpcoming(
    List<PlaybackSchedule> schedules,
    DateTime now, {
    DateTime? Function(String scheduleId)? lastFiredFor,
    DateTime? Function(String scheduleId)? lastSlotFor,
    bool forDisplay = false,
  }) {
    ({DateTime when, PlaybackSchedule schedule})? best;
    for (final s in schedules) {
      if (!s.enabled) continue;
      final last = lastFiredFor?.call(s.id);
      final slot = lastSlotFor?.call(s.id);
      final when = nextFireTime(
        s,
        now,
        lastFired: last,
        lastSlot: slot,
        forDisplay: forDisplay,
      );
      if (when == null) continue;
      if (best == null || when.isBefore(best.when)) {
        best = (when: when, schedule: s);
      }
    }
    return best;
  }

  /// Upcoming grid fires across all schedules (sorted by time).
  ///
  /// Step between fires uses [effectiveStepMinutes] = `playlistDuration +
  /// intervalMinutes`. The previous implementation used `intervalMinutes`
  /// alone, which made the upcoming list overlap the playlist with the
  /// silent gap (a 5-min playlist on a 5-min interval predicted next at
  /// `now+5min` even though the playlist would still be playing).
  static List<({DateTime when, String playlistName})> upcomingEvents(
    List<PlaybackSchedule> schedules,
    DateTime now, {
    DateTime? Function(String scheduleId)? lastFiredFor,
    DateTime? Function(String scheduleId)? lastSlotFor,
    int limit = 4,
  }) {
    final events = <({DateTime when, String playlistName})>[];
    for (final s in schedules) {
      if (!s.enabled) continue;
      final last = lastFiredFor?.call(s.id);
      final lastSlot = lastSlotFor?.call(s.id);
      var slot = nextFireTime(
        s,
        now,
        lastFired: last,
        lastSlot: lastSlot,
        forDisplay: true,
      );
      var hops = 0;
      while (slot != null && hops < limit * 2) {
        events.add((
          when: slot,
          playlistName: s.playlistName.isEmpty ? 'WhisperBack' : s.playlistName,
        ));
        final step = Duration(minutes: effectiveStepMinutes(s));
        slot = slot.add(step);
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
  ///
  /// Round 15 contract change: gap between successive fires is
  /// `playlistDuration + intervalMinutes`, NOT just `intervalMinutes`.
  /// Example (user-reported): a 5-minute playlist with a 10-minute
  /// interval starting at 1:00 should fire at 1:00, 1:15, 1:30, …
  /// because each fire occupies 5 minutes and we want a 10-minute
  /// silent gap AFTER the playlist finishes. Previously this method
  /// produced 1:00, 1:10, 1:20 which overlapped the playlist with
  /// the "silent gap" the user explicitly configured.
  static Iterable<({int weekday, int hour, int minute, String label})>
      intervalAlarmSlots(PlaybackSchedule schedule) sync* {
    if (!schedule.enabled || !schedule.alarmEnabled) return;

    final stepMinutes = effectiveStepMinutes(schedule);
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
        slot = slot.add(Duration(minutes: stepMinutes));
      }
    }
  }

  /// Effective step between successive fires in minutes
  /// = `playlistDurationMinutes + intervalMinutes`, rounded UP.
  /// Falls back to `intervalMinutes` alone when the playlist
  /// duration is unknown / 0.
  static int effectiveStepMinutes(PlaybackSchedule schedule) {
    final durationMinutes = schedule.playlistDurationMs > 0
        ? ((schedule.playlistDurationMs + 59999) ~/ 60000)
        : 0;
    final step = schedule.intervalMinutes + durationMinutes;
    return step < 1 ? 1 : step;
  }
}
