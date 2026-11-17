import 'package:audiobook_reader/main.dart' as entry;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a startup error is shown as is instead of an endless splash screen', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'denied', message: 'storage denied verbatim');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    Object? escaped;
    await tester.runAsync(() async {
      try {
        await entry.main();
      } catch (error) {
        escaped = error;
      }
    });
    expect(escaped, isNull, reason: 'runApp must show the error, not abort before the first frame');
    await tester.pumpAndSettle();
    expect(find.textContaining('storage denied verbatim'), findsOneWidget);
  });
}
