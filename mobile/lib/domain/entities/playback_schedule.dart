import 'package:equatable/equatable.dart';

class PlaybackSchedule extends Equatable {
  const PlaybackSchedule({
    required this.id,
    required this.playlistId,
    required this.startTime,
    required this.intervalMinutes,
    this.endTime,
    this.shuffleEnabled = false,
    this.alarmEnabled = true,
    this.daysMask = 127,
    this.enabled = true,
    this.playlistName = '',
  });

  final String id;
  final String playlistId;
  final DateTime startTime;
  final DateTime? endTime;
  final int intervalMinutes;
  final bool shuffleEnabled;
  final bool alarmEnabled;

  /// Bit mask: bit 0 = Monday … bit 6 = Sunday. 127 = every day.
  final int daysMask;
  final bool enabled;
  final String playlistName;

  static const weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  String get daysLabel {
    if (daysMask == 127) return 'Every day';
    if (daysMask == 31) return 'Weekdays';
    if (daysMask == 96) return 'Weekends';
    final parts = <String>[];
    for (var i = 0; i < 7; i++) {
      if ((daysMask & (1 << i)) != 0) parts.add(weekdayLabels[i]);
    }
    return parts.join(' · ');
  }

  String get intervalLabel {
    if (intervalMinutes >= 60 && intervalMinutes % 60 == 0) {
      final h = intervalMinutes ~/ 60;
      return h == 1 ? '1 hour' : '$h hours';
    }
    return '$intervalMinutes min';
  }

  bool runsOnWeekday(int weekday) => (daysMask & (1 << (weekday - 1))) != 0;

  PlaybackSchedule copyWith({
    DateTime? endTime,
    int? intervalMinutes,
    bool? shuffleEnabled,
    bool? alarmEnabled,
    int? daysMask,
    bool? enabled,
  }) {
    return PlaybackSchedule(
      id: id,
      playlistId: playlistId,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      daysMask: daysMask ?? this.daysMask,
      enabled: enabled ?? this.enabled,
      playlistName: playlistName,
    );
  }

  @override
  List<Object?> get props => [
        id,
        playlistId,
        startTime,
        endTime,
        intervalMinutes,
        shuffleEnabled,
        alarmEnabled,
        daysMask,
        enabled,
        playlistName,
      ];
}
