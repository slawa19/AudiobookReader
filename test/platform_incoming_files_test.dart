import 'dart:async';

import 'package:audiobook_reader/library/incoming_files.dart';
import 'package:audiobook_reader/platform/platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _methods = MethodChannel('audiobook_reader/incoming_files');
const _events = MethodChannel('audiobook_reader/incoming_files/events');
const _codec = StandardMethodCodec();
const _file = {'path': '/cache/incoming_books/book-123.tmp', 'name': 'Книга.fb2.zip'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> send(ByteData envelope) async {
    final handled = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(_events.name, envelope, (_) => handled.complete());
    await handled.future;
  }

  setUp(() {
    messenger.setMockMethodCallHandler(_events, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMethodCallHandler(_events, null);
  });

  test('выбор возвращает путь копии и исходное имя', () async {
    messenger.setMockMethodCallHandler(_methods, (call) async {
      expect(call.method, 'pickFile');
      expect(call.arguments, isNull);
      return _file;
    });
    final IncomingFiles files = AndroidIncomingFiles();
    final file = await files.pickFile();
    expect(file?.path, _file['path']);
    expect(file?.name, _file['name']);
  });

  test('отмена выбора возвращает null', () async {
    messenger.setMockMethodCallHandler(_methods, (_) async => null);
    expect(await AndroidIncomingFiles().pickFile(), isNull);
  });

  test('ошибка копирования при выборе доходит до вызывающего', () async {
    messenger.setMockMethodCallHandler(_methods, (_) async {
      throw PlatformException(code: 'copy_failed', message: 'Недостаточно места');
    });
    await expectLater(
      AndroidIncomingFiles().pickFile(),
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'copy_failed')
          .having((error) => error.message, 'message', 'Недостаточно места')),
    );
  });

  test('файл другого приложения поступает через EventChannel', () async {
    final listening = Completer<void>();
    messenger.setMockMethodCallHandler(_events, (call) async {
      if (call.method == 'listen') listening.complete();
      return null;
    });
    final received = AndroidIncomingFiles().incomingFiles.first;
    await listening.future;
    await send(_codec.encodeSuccessEnvelope(_file));
    final file = await received;
    expect(file.path, _file['path']);
    expect(file.name, _file['name']);
  });

  test('поздняя подписка получает файл холодного запуска ровно один раз', () async {
    // Подставной Android уже скопировал файл до создания Dart-объекта и держит
    // событие до listen; Dart не должен открывать канал раньше подписчика.
    final pending = [_file];
    var listens = 0;
    messenger.setMockMethodCallHandler(_events, (call) async {
      if (call.method == 'listen') {
        listens++;
        for (final file in pending) {
          await send(_codec.encodeSuccessEnvelope(file));
        }
        pending.clear();
      }
      return null;
    });
    final files = AndroidIncomingFiles();
    final stream = files.incomingFiles;
    await Future<void>.delayed(Duration.zero);
    expect(listens, 0);

    final received = <IncomingFile>[];
    final ready = Completer<void>();
    final subscription = stream.listen((file) {
      received.add(file);
      ready.complete();
    });
    await ready.future;
    await Future<void>.delayed(Duration.zero);
    expect(listens, 1);
    expect(received, hasLength(1));
    expect(received.single.name, _file['name']);
    expect(pending, isEmpty);
    await subscription.cancel();
  });

  test('ошибка входящего копирования не теряется и не закрывает поток', () async {
    final listening = Completer<void>();
    messenger.setMockMethodCallHandler(_events, (call) async {
      if (call.method == 'listen') listening.complete();
      return null;
    });
    final errors = <Object>[];
    final received = Completer<IncomingFile>();
    final subscription = AndroidIncomingFiles().incomingFiles.listen(received.complete, onError: errors.add);
    await listening.future;
    await send(_codec.encodeErrorEnvelope(code: 'copy_failed', message: 'Источник недоступен'));
    await send(_codec.encodeSuccessEnvelope(_file));
    expect((await received.future).path, _file['path']);
    expect(errors, hasLength(1));
    expect(errors.single, isA<PlatformException>()
        .having((error) => error.code, 'code', 'copy_failed')
        .having((error) => error.message, 'message', 'Источник недоступен'));
    await subscription.cancel();
  });
}
