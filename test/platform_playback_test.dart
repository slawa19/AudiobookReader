import 'package:audiobook_reader/app/screen_awake.dart';
import 'package:audiobook_reader/platform/external_links.dart';
import 'package:audiobook_reader/platform/media_service.dart';
import 'package:audiobook_reader/platform/screen_awake.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test('удержание экрана передаётся каналом по порядку, ошибка видна корню', () async {
    final values = <bool>[];
    final errors = <Object>[];
    messenger.setMockMethodCallHandler(AndroidScreenAwake.channel, (call) async {
      expect(call.method, 'setEnabled');
      values.add((call.arguments as Map)['enabled'] as bool);
      if (values.length == 2) throw PlatformException(code: 'test_failure');
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(AndroidScreenAwake.channel, null));
    final port = NativeScreenAwake(errors.add);
    port.setEnabled(true);
    port.setEnabled(false);
    port.setEnabled(true);
    await port.flush();
    expect(values, [true, false, true]);
    expect(errors, hasLength(1));
  });
  test('служба подтверждается платформой, ссылка передаётся в системное действие', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(AndroidMediaService.channel, (call) async {
      calls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(AndroidExternalLinks.channel, (call) async {
      calls.add(call.method);
      expect(call.arguments, {'url': 'https://aistudio.google.com/billing'});
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(AndroidMediaService.channel, null);
      messenger.setMockMethodCallHandler(AndroidExternalLinks.channel, null);
    });
    await AndroidMediaService.awaitForeground();
    await AndroidExternalLinks.open('https://aistudio.google.com/billing');
    expect(calls, ['awaitForeground', 'open']);
  });
}
