import 'package:flutter_test/flutter_test.dart';
import 'package:whisperback/services/scheduler/schedule_countdown.dart';

void main() {
  test('formats sub-minute countdown', () {
    expect(ScheduleCountdown.label(const Duration(seconds: 30)), '<1 min');
  });

  test('formats minute countdown', () {
    expect(ScheduleCountdown.label(const Duration(minutes: 12)), '~12 min');
  });

  test('formats hour countdown', () {
    expect(ScheduleCountdown.label(const Duration(hours: 1, minutes: 5)),
        '~1h 5m');
  });

  test('shows now for elapsed slots', () {
    expect(ScheduleCountdown.label(Duration.zero), 'now');
  });
}
