/// Human-readable countdown labels for schedule UI (SC-05).
abstract final class ScheduleCountdown {
  static Duration? until(DateTime? when, [DateTime? now]) {
    if (when == null) return null;
    final reference = now ?? DateTime.now();
    return when.difference(reference);
  }

  /// e.g. `~12 min`, `~1h 5m`, `now`, `—`
  static String label(Duration? remaining) {
    if (remaining == null) return '—';
    if (remaining.inSeconds <= 0) return 'now';
    final mins = remaining.inMinutes;
    if (mins < 1) return '<1 min';
    if (mins < 60) return '~$mins min';
    final hours = mins ~/ 60;
    final rem = mins % 60;
    if (rem == 0) return '~${hours}h';
    return '~${hours}h ${rem}m';
  }

  static String untilTime(DateTime? when, [DateTime? now]) =>
      label(until(when, now));
}
