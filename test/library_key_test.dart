import 'dart:async';
import 'dart:io';

import 'package:audiobook_reader/app/native_application.dart';
import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/secret_store.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/library_time.dart';
import 'support/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late TestSecretStore store;
  late FileLibrary library;

  Future<void> start() async {
    final time = LibraryTime();
    library = FileLibrary(
      root,
      settings: AppSettings(
        voice: 'voice',
        modelId: 'model',
        secretStore: store,
      ),
      clock: time.call,
      timer: time.timer,
    );
    await library.ready;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library-key-');
    store = TestSecretStore('test-initial-secret');
    await start();
  });

  tearDown(() async {
    await library.flush();
    library.dispose();
    library.settings.dispose();
    await root.delete(recursive: true);
  });

  test('key input removes whitespace and invisible characters inside; ASCII and visible characters are kept', () async {
    for (final invisible in [' ', '\n', '\r', '\t', '\u00a0', '\u200b', '\ufeff', '\u202f', '\u2060', '\u034f', '\ufe0f']) {
      library.settings.apiKey = '${invisible}fake$invisible-key$invisible';
      await library.flush();
      expect(library.settings.apiKey, 'fake-key');
      expect(store.value, 'fake-key');
    }
    for (final visible in ['fake-ASCII_09+~', 'fake-é-key']) {
      library.settings.apiKey = visible;
      await library.flush();
      expect(library.settings.apiKey, visible);
      expect(store.value, visible);
    }
    library.settings.apiKey = '\n\u200b\ufeff\u00a0';
    await library.flush();
    expect(library.settings.hasApiKey, isFalse);
    expect(store.value, 'fake-é-key');
  });

  test('the key is read before ready; startup does not write it back', () {
    expect(store.reads, 1);
    expect(store.writes, isEmpty);
    expect(library.settings.hasApiKey, isTrue);
    expect(library.settings.apiKey, 'test-initial-secret');
    expect(library.settings.apiKeyTail, 'cret');
  });

  test(
    'a change writes the secret and survives a new library on the same folder',
    () async {
      library.settings.apiKey = '  test-replacement-secret  ';
      await library.flush();
      expect(store.writes, ['test-replacement-secret']);
      expect(store.value, 'test-replacement-secret');
      library.dispose();
      library.settings.dispose();
      await start();
      expect(library.settings.apiKey, 'test-replacement-secret');
      expect(store.reads, 2);
      expect(store.writes, hasLength(1));
    },
  );

  test('the key does not reach settings.json and toString; ordinary settings are kept', () async {
    library.settings
      ..apiKey = 'test-unique-secret'
      ..voice = 'new-voice';
    await library.flush();
    final json = await File('${root.path}/settings.json').readAsString();
    expect(json, contains('new-voice'));
    expect(json, isNot(contains('test-unique-secret')));
    expect(json, isNot(contains('apiKey')));
    expect(
      library.settings.toJson().values,
      isNot(contains('test-unique-secret')),
    );
    expect(library.settings.toString(), isNot(contains('test-unique-secret')));
    expect(library.toString(), isNot(contains('test-unique-secret')));
    expect(store.toString(), isNot(contains('test-unique-secret')));
  });

  test(
    'a read error does not crash startup, the key is empty and allows re-entry',
    () async {
      library.dispose();
      library.settings.dispose();
      store.readError = StateError('test-initial-secret');
      await start();
      expect(library.settings.hasApiKey, isFalse);
      expect(library.settings.apiKey, isNull);
      expect(library.settings.apiKeyTail, isEmpty);
      library.settings.apiKey = 'test-new-secret';
      await library.flush();
      expect(store.value, 'test-new-secret');
    },
  );

  test('a missing secret and an empty store give an empty key', () async {
    for (final value in [null, '', '  ']) {
      library.dispose();
      library.settings.dispose();
      store.value = value;
      await start();
      expect(library.settings.hasApiKey, isFalse);
      expect(library.settings.apiKey, isNull);
    }
  });

  test(
    'flush waits for secrets; rapid changes are written in order',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeWrite = (value) async {
        if (value == 'test-first-secret') {
          entered.complete();
          await release.future;
        }
      };
      library.settings.apiKey = 'test-first-secret';
      await entered.future;
      library.settings.apiKey = 'test-second-secret';
      var completed = false;
      final flushing = library.flush().then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(store.writes, isEmpty);
      release.complete();
      await flushing;
      expect(store.writes, ['test-first-secret', 'test-second-secret']);
      expect(store.value, 'test-second-secret');
    },
  );

  test(
    'a write error does not contain the key and does not poison later writes',
    () async {
      store.writeError = StateError('test-sensitive-error-value');
      library.settings.apiKey = 'test-sensitive-error-value';
      library.settings.voice = 'voice-with-failed-secret';
      await expectLater(
        library.flush(),
        throwsA(
          isA<SecretStoreException>().having(
            (error) => error.toString(),
            'текст',
            isNot(contains('test-sensitive-error-value')),
          ),
        ),
      );
      expect(store.value, 'test-initial-secret');
      expect(
        await File('${root.path}/settings.json').readAsString(),
        contains('voice-with-failed-secret'),
        reason: 'a secret error must not cancel writing the rest of the data',
      );
      store.writeError = null;
      library.settings.apiKey = 'test-recovered-secret';
      await library.flush();
      expect(store.value, 'test-recovered-secret');
    },
  );

  test('the build root accepts the key store and reads it before returning', () async {
    // A separate directory: two library instances must not write to one folder.
    final app = await NativeApplication.create(
      root: Directory('${root.path}/native'),
      secretStore: store,
    );
    try {
      expect(app.settings.apiKey, 'test-initial-secret');
      app.settings.apiKey = 'test-native-secret';
      await app.flush();
      expect(store.value, 'test-native-secret');
    } finally {
      app.services.narration.dispose();
      app.services.downloads.dispose();
      app.services.sampler.dispose();
      app.library.dispose();
      app.settings.dispose();
    }
  });
}
