import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisperback/main.dart' as app;

/// Device-matrix tests — run on physical devices:
/// `flutter test integration_test/app_test.dart -d device_id`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('WhisperBack critical paths', () {
    testWidgets('app launches to home', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('WhisperBack'), findsWidgets);
    });
  });
}
