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

  test('picking returns the copy path and the original name', () async {
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

  test('cancelling the pick returns null', () async {
    messenger.setMockMethodCallHandler(_methods, (_) async => null);
    expect(await AndroidIncomingFiles().pickFile(), isNull);
  });

  test('a copy error while picking reaches the caller', () async {
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

  test('a file from another app arrives through the EventChannel', () async {
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

  test('a late subscription receives the cold-start file exactly once', () async {
    // The fake Android has already copied the file before the Dart object is created and holds
    // the event until listen; Dart must not open the channel before a subscriber exists.
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

  test('an incoming copy error is not lost and does not close the stream', () async {
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
