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
  /// [lastSlot] is the wall-clock start of the previous fire — the
  /// anchor used to project the next one. [lastFired] is the actual
  /// completion time when known; it's used as a fallback anchor only
  /// when [lastSlot] wasn't supplied (some legacy call sites only track
  /// completion).
  ///
  /// Round 36: START-TO-START interval semantics. `intervalMinutes` is
  /// the gap between successive whisper START times — `next = lastSlot +
  /// effectiveStep(schedule)`, where `effectiveStep` is `max(interval,
  /// playlistDuration)`. A shorter-than-interval playlist (the common
  /// case) fires exactly on the user's configured cadence. A playlist
  /// that runs LONGER than the interval still can't overlap itself, so
  /// the next fire waits for it to finish instead.
  ///
  /// (Earlier rounds used "interval-from-end" semantics — next =
  /// completion + interval, i.e. every fire cost `interval +
  /// playlistDuration` — which is why a "15-minute" schedule used to
  /// land 18-19 minutes apart for a few-minutes-long playlist. That
  /// didn't match what users configure when they type "15 minutes".)
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
      // Prefer the previous fire's actual START time; fall back to the
      // completion stamp only when no slot stamp was tracked.
      final referenceStart = lastSlot ?? lastFired;
      if (referenceStart != null) {
        final lastDay = DateTime(
          referenceStart.year,
          referenceStart.month,
          referenceStart.day,
        );
        final onSameDay = lastDay.year == day.year &&
            lastDay.month == day.month &&
            lastDay.day == day.day;
        if (onSameDay && !referenceStart.isBefore(start)) {
          slot = referenceStart.add(effectiveStep(schedule));
        }
      }

      // Round 15 / Round 34 / Round 36: step between grid slots must
      // match the same millisecond-precise `effectiveStep` used above —
      // minute-rounding made later fires drift vs the NEXT SCHEDULES UI.
      final stepDuration = effectiveStep(schedule);

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
  /// [lastFired] is the completion timestamp of the previous fire (used as
  /// a fallback anchor). [lastSlot] is the wall-clock START of the
  /// previous fire — the preferred anchor for the start-to-start
  /// `effectiveStep` projection in `nextSlotAfter` (Round 36).
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
  /// Step between fires uses [effectiveStep] = `max(intervalMinutes,
  /// playlistDuration)` (Round 36) — start-to-start on the configured
  /// cadence, falling back to the playlist's own length only when it
  /// would otherwise overlap itself.
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
        final step = effectiveStep(s);
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
  /// Round 36: gap between successive fires is `max(playlistDuration,
  /// intervalMinutes)` — start-to-start on the configured interval.
  /// Example: a 5-minute playlist with a 10-minute interval starting at
  /// 1:00 fires at 1:00, 1:10, 1:20, … (interval wins, playlist is
  /// shorter). A 15-minute playlist on that same 10-minute interval
  /// fires at 1:00, 1:15, 1:30, … (playlist wins — the next fire can't
  /// start before the current one finishes).
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

  /// Effective step between successive fires (start-to-start), in
  /// millisecond precision.
  ///
  /// Round 36: `max(intervalMinutes, playlistDuration)` — NOT the sum.
  /// The interval the user configures is the gap between whisper START
  /// times. A playlist shorter than the interval (the common case) fires
  /// exactly on the configured cadence; a playlist LONGER than the
  /// interval still can't start the next fire before it finishes, so we
  /// fall back to the playlist's own length for that one step.
  ///
  /// Falls back to a 60s placeholder duration when the playlist length is
  /// still unknown (Round 34) so a step is never computed as 0.
  static Duration effectiveStep(PlaybackSchedule schedule) {
    final durationMs = schedule.playlistDurationMs > 0
        ? schedule.playlistDurationMs
        : 60 * 1000; // unknown length — conservative 1 minute
    final interval = Duration(minutes: schedule.intervalMinutes);
    final duration = Duration(milliseconds: durationMs);
    final step = interval > duration ? interval : duration;
    return step < const Duration(minutes: 1)
        ? const Duration(minutes: 1)
        : step;
  }

  /// Effective step between successive fires in whole minutes
  /// (ceil). Prefer [effectiveStep] for alarm / next-fire math.
  static int effectiveStepMinutes(PlaybackSchedule schedule) {
    final ms = effectiveStep(schedule).inMilliseconds;
    final minutes = (ms + 59999) ~/ 60000;
    return minutes < 1 ? 1 : minutes;
  }
}
