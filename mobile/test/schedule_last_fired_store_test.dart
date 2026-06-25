import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisperback/services/scheduler/schedule_last_fired_store.dart';

/// Pins the two-stamp model that replaced the legacy single-key store.
///
/// Why it matters: `_slotTakenByOtherSchedule` dedup compares grid slot times
/// (e.g. 09:00), while `nextSlotAfter` needs the completion time (e.g. 09:04)
/// so interval-from-end works for a 4-minute playlist on a 5-minute interval.
/// Storing them in the same key caused both behaviors to silently break after
/// the first scheduled run completed.
void main() {
  test('slot and completion can be set independently', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    final store = await ScheduleLastFiredStore.ensureLoaded();
    final slot = DateTime(2026, 1, 1, 9, 0);
    final completion = DateTime(2026, 1, 1, 9, 4, 12);
    await store.setSlot('s1', slot);
    await store.setCompletion('s1', completion);
    expect(store.slot('s1'), slot);
    expect(store.completion('s1'), completion);
  });

  test('get() returns the completion stamp when both are set', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    final store = await ScheduleLastFiredStore.ensureLoaded();
    await store.setSlot('s1', DateTime(2026, 1, 1, 9, 0));
    await store.setCompletion('s1', DateTime(2026, 1, 1, 9, 4));
    expect(store.get('s1'), DateTime(2026, 1, 1, 9, 4));
  });

  test('legacy combined set() writes both stamps for backwards compat',
      () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    final store = await ScheduleLastFiredStore.ensureLoaded();
    final when = DateTime(2026, 1, 1, 9, 0);
    await store.set('s1', when);
    expect(store.slot('s1'), when);
    expect(store.completion('s1'), when);
  });

  test('clear removes every key (slot + completion + legacy)', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    final store = await ScheduleLastFiredStore.ensureLoaded();
    await store.setSlot('s1', DateTime(2026, 1, 1, 9, 0));
    await store.setCompletion('s1', DateTime(2026, 1, 1, 9, 4));
    await store.clear('s1');
    expect(store.slot('s1'), isNull);
    expect(store.completion('s1'), isNull);
    expect(store.get('s1'), isNull);
  });

  test(
      'migration: legacy schedule_last_fired_ key is readable via slot() and '
      'completion() so an upgrade does not lose dedup state', () async {
    final iso = DateTime(2026, 1, 1, 9, 0).toIso8601String();
    SharedPreferences.setMockInitialValues(
      {'schedule_last_fired_legacy-id': iso},
    );
    // Force a fresh cache because ensureLoaded() caches the store reference.
    await SharedPreferences.getInstance();
    final store = ScheduleLastFiredStore(await SharedPreferences.getInstance());
    expect(store.slot('legacy-id'), DateTime(2026, 1, 1, 9, 0));
    expect(store.completion('legacy-id'), DateTime(2026, 1, 1, 9, 0));
  });
}
