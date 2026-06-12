import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whisperback/app.dart';
import 'package:whisperback/services/scheduler/schedule_last_fired_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ScheduleLastFiredStore.ensureLoaded();
  });

  testWidgets('WhisperBackApp builds', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: WhisperBackApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
