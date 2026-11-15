import 'package:audiobook_reader/main.dart' as entry;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ошибка запуска показана как есть вместо вечной заставки', (tester) async {
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
    expect(escaped, isNull, reason: 'runApp должен показать ошибку, а не оборваться до первого кадра');
    await tester.pumpAndSettle();
    expect(find.textContaining('storage denied verbatim'), findsOneWidget);
  });
}
