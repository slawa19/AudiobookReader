import 'dart:io';

import 'package:audiobook_reader/app/native_application.dart';
import 'package:audiobook_reader/library/secret_store.dart';
import 'package:audiobook_reader/platform/secret_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'AndroidSecretStore reads and writes through the real Dart code of the package',
    () async {
      final calls = <MethodCall>[];
      String? saved;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(arguments['key'], 'gemini_api_key');
        if (call.method == 'read') return saved;
        if (call.method == 'write') {
          saved = arguments['value']! as String;
          return null;
        }
        fail('Unexpected channel method: ${call.method}');
      });
      final store = AndroidSecretStore();
      expect(await store.read(), isNull);
      await store.write('test-platform-secret');
      expect(await store.read(), 'test-platform-secret');
      expect(calls.map((call) => call.method), ['read', 'write', 'read']);
      expect(store.toString(), isNot(contains('test-platform-secret')));
    },
  );

  test('the native build wires up AndroidSecretStore by default', () async {
    final root = await Directory.systemTemp.createTemp('native-key-');
    String? saved = 'test-native-default-secret';
    messenger.setMockMethodCallHandler(channel, (call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments['key'], 'gemini_api_key');
      if (call.method == 'read') return saved;
      if (call.method == 'write') {
        saved = arguments['value']! as String;
        return null;
      }
      fail('Unexpected channel method: ${call.method}');
    });
    final app = await NativeApplication.create(root: root);
    try {
      expect(app.settings.apiKey, 'test-native-default-secret');
      app.settings.apiKey = 'test-native-default-replacement';
      await app.library.flush();
      expect(saved, 'test-native-default-replacement');
    } finally {
      app.services.narration.dispose();
      app.services.downloads.dispose();
      app.services.sampler.dispose();
      app.library.dispose();
      app.settings.dispose();
      await root.delete(recursive: true);
    }
  });

  for (final operation in ['read', 'write']) {
    test(
      'a platform error during $operation does not reveal the secret or details',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'test-secret-code',
            message: 'test-platform-secret',
            details: 'test-secret-details',
          );
        });
        final store = AndroidSecretStore();
        await expectLater(
          operation == 'read'
              ? store.read()
              : store.write('test-platform-secret'),
          throwsA(
            isA<SecretStoreException>().having(
              (error) => error.toString(),
              'safe text',
              allOf(
                isNot(contains('test-platform-secret')),
                isNot(contains('test-secret-details')),
              ),
            ),
          ),
        );
      },
    );
  }

  test('the secure storage package imports only platform', () {
    final imports = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              file.readAsStringSync().contains(
                'package:flutter_secure_storage/',
              ),
        )
        .toList();
    expect(
      imports,
      isNotEmpty,
      reason: 'the check must see the real implementation',
    );
    for (final file in imports) {
      expect(file.path.replaceAll('\\', '/'), startsWith('lib/platform/'));
    }
  });
}
