import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audiobook_reader/audio/audio_encoder.dart';
import 'package:audiobook_reader/audio/audio_store.dart';
import 'package:audiobook_reader/audio/file_audio_store.dart';
import 'package:audiobook_reader/audio/wav_audio_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledEncoder implements AudioEncoder {
  final started = Completer<void>();
  final finish = Completer<void>();
  Object? error;
  int calls = 0;

  @override
  String get extension => 'wav';
  @override
  String get formatId => 'controlled-wav';

  @override
  Future<void> encode({
    required String pcmPath,
    required String outputPath,
    required int sampleRate,
  }) async {
    calls++;
    // Даже частичный закодированный файл ещё не должен быть доступен читателю.
    await File(outputPath).writeAsBytes([1, 2, 3]);
    if (!started.isCompleted) started.complete();
    await finish.future;
    if (error case final Object error) throw error;
    await const WavAudioEncoder().encode(
      pcmPath: pcmPath,
      outputPath: outputPath,
      sampleRate: sampleRate,
    );
  }
}

void main() {
  late Directory root;
  final pcm = Uint8List.fromList([0, 0, 1, 0, 255, 127, 0, 128]);

  Directory book(String id) => Directory('${root.path}/books/$id');
  Directory audio(String id) => Directory('${book(id).path}/audio');
  Directory getSamples() => Directory('${root.path}/samples');
  List<File> temporaryFiles() =>
      Directory('${root.path}/tmp/audio').existsSync()
      ? Directory('${root.path}/tmp/audio')
            .listSync(recursive: true)
            .whereType<File>()
            .toList()
      : [];

  setUp(() {
    root = Directory.systemTemp.createTempSync('audio-store-');
    book('book-a').createSync(recursive: true);
    book('book-b').createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'отрезок виден только после завершения кодирования; PCM не меняется',
    () async {
      final encoder = ControlledEncoder();
      final store = FileAudioStore(root, encoder: encoder);
      final original = Uint8List.fromList(pcm);
      var notifications = 0;
      store.addListener(() => notifications++);
      final writing = store.put('hash-a', pcm, 24000, bookId: 'book-a');
      await encoder.started.future;
      expect(temporaryFiles(), hasLength(2));
      expect(store.has('hash-a', bookId: 'book-a'), isFalse);
      expect(store.file('hash-a', bookId: 'book-a'), isNull);
      expect(store.totalBytes, 0);
      expect(notifications, 0);
      encoder.finish.complete();
      final file = await writing;
      expect(file.path, '${audio('book-a').path}/hash-a.wav');
      expect(store.has('hash-a', bookId: 'book-a'), isTrue);
      expect(store.file('hash-a', bookId: 'book-a')!.path, file.path);
      expect(pcm, original);
      expect(notifications, 1);
      expect(temporaryFiles(), isEmpty);
    },
  );

  test(
    'ошибка кодека убирает частичный файл, повтор использует тот же PCM',
    () async {
      final encoder = ControlledEncoder()
        ..error = const FileSystemException('нет места');
      final store = FileAudioStore(root, encoder: encoder);
      final writing = store.put('hash-a', pcm, 24000, bookId: 'book-a');
      final failed = expectLater(writing, throwsA(isA<FileSystemException>()));
      await encoder.started.future;
      encoder.finish.complete();
      await failed;
      expect(store.has('hash-a', bookId: 'book-a'), isFalse);
      expect(audio('book-a').existsSync(), isFalse);
      expect(temporaryFiles(), isEmpty);
      expect(pcm, [0, 0, 1, 0, 255, 127, 0, 128]);
      encoder.error = null;
      await store.put('hash-a', pcm, 24000, bookId: 'book-a');
      expect(encoder.calls, 2);
      expect(store.bytesForBook('book-a'), pcm.length + 44);
    },
  );

  test(
    'ошибка записи PCM возвращается; повтор после устранения причины проходит',
    () async {
      final store = FileAudioStore(root, encoder: const WavAudioEncoder());
      Directory('${root.path}/tmp').createSync();
      final obstruction = File('${root.path}/tmp/audio')
        ..writeAsStringSync('занято');
      await expectLater(
        store.put('hash-a', pcm, 24000, bookId: 'book-a'),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.totalBytes, 0);
      expect(audio('book-a').existsSync(), isFalse);
      obstruction.deleteSync();
      await store.put('hash-a', pcm, 24000, bookId: 'book-a');
      expect(store.has('hash-a', bookId: 'book-a'), isTrue);
    },
  );

  test('место книги и всех проб; удаление и очистка сохраняют остальные файлы книги', () async {
    final store = FileAudioStore(root, encoder: const WavAudioEncoder());
    final original = File('${book('book-a').path}/book.json')
      ..writeAsStringSync('{}');
    await store.put('same', pcm, 24000, bookId: 'book-a');
    await store.put('same', pcm, 24000, bookId: 'book-b');
    await store.put('same', pcm, 24000);
    expect(store.formatId, const WavAudioEncoder().formatId);
    expect(store.file('same')!.path, '${getSamples().path}/same.wav');
    expect(store.bytesForBook('book-a'), 52);
    expect(store.totalBytes, 156);
    store.removeBook('book-a');
    expect(store.bytesForBook('book-a'), 0);
    expect(audio('book-a').existsSync(), isFalse);
    expect(store.has('same', bookId: 'book-b'), isTrue);
    expect(store.has('same'), isTrue);
    expect(store.totalBytes, 104);
    expect(original.existsSync(), isTrue);
    store.clearAll();
    expect(store.totalBytes, 0);
    expect(audio('book-b').existsSync(), isFalse);
    expect(getSamples().existsSync(), isFalse);
    expect(original.readAsStringSync(), '{}');
    // После очистки новый запрос снова может занять место (FR-D3).
    await store.put('same', pcm, 24000, bookId: 'book-a');
    await store.put('same', pcm, 24000);
    expect(store.totalBytes, 104);
    store.clearAll();
    expect(store.totalBytes, 0);
  });

  test(
    'перезапуск считает реальные файлы, замена отпечатка не удваивает место',
    () async {
      var store = FileAudioStore(root, encoder: const WavAudioEncoder());
      await store.put('hash', pcm, 24000, bookId: 'book-a');
      store.dispose();
      store = FileAudioStore(root, encoder: const WavAudioEncoder());
      expect(store.totalBytes, 52);
      expect(store.has('hash', bookId: 'book-a'), isTrue);
      await store.put('hash', Uint8List(20), 24000, bookId: 'book-a');
      expect(store.bytesForBook('book-a'), 64);
      expect(store.totalBytes, 64);
    },
  );

  for (final clear in [false, true]) {
    for (final sample in [false, true]) {
      if (!clear && sample) continue;
      test(
        'поздняя запись: clear=$clear, sample=$sample — папки не воскресают',
        () async {
          final encoder = ControlledEncoder();
          final store = FileAudioStore(root, encoder: encoder);
          final id = sample ? null : 'book-a';
          final writing = store.put('late', pcm, 24000, bookId: id);
          final cancelled = expectLater(
            writing,
            throwsA(isA<AudioWriteCancelled>()),
          );
          await encoder.started.future;
          if (clear) {
            store.clearAll();
          } else {
            store.removeBook('book-a');
            // Настоящее удаление самой книги принадлежит Library.
            book('book-a').deleteSync(recursive: true);
          }
          // Метод вернулся, хотя кодировщик всё ещё ждёт разрешения теста.
          expect(encoder.finish.isCompleted, isFalse);
          encoder.finish.complete();
          await cancelled;
          expect(store.totalBytes, 0);
          expect(store.file('late', bookId: id), isNull);
          expect(audio('book-a').existsSync(), isFalse);
          expect(getSamples().existsSync(), isFalse);
          if (!clear) expect(book('book-a').existsSync(), isFalse);
          expect(temporaryFiles(), isEmpty);
        },
      );
    }
  }

  test('удаление одной книги не отменяет запись другой и пробы', () async {
    final encoder = ControlledEncoder();
    final store = FileAudioStore(root, encoder: encoder);
    final other = store.put('other', pcm, 24000, bookId: 'book-b');
    final sample = store.put('sample', pcm, 24000);
    await encoder.started.future;
    store.removeBook('book-a');
    encoder.finish.complete();
    await Future.wait([other, sample]);
    expect(store.has('other', bookId: 'book-b'), isTrue);
    expect(store.has('sample'), isTrue);
    expect(store.totalBytes, 104);
  });

  test('новая запись после удаления выигрывает у запоздалой старой с тем же отпечатком', () async {
    final encoder = ControlledEncoder();
    final store = FileAudioStore(root, encoder: encoder);
    final old = store.put('same', pcm, 24000, bookId: 'book-a');
    final cancelled = expectLater(old, throwsA(isA<AudioWriteCancelled>()));
    await encoder.started.future;
    store.removeBook('book-a');
    final fresh = store.put('same', Uint8List(20), 24000, bookId: 'book-a');
    encoder.finish.complete();
    await cancelled;
    await fresh;
    expect(store.bytesForBook('book-a'), 64);
  });

  test(
    'внешнее удаление папки книги тоже не позволяет её воссоздать',
    () async {
      final encoder = ControlledEncoder();
      final store = FileAudioStore(root, encoder: encoder);
      final writing = store.put('hash', pcm, 24000, bookId: 'book-a');
      final cancelled = expectLater(
        writing,
        throwsA(isA<AudioWriteCancelled>()),
      );
      await encoder.started.future;
      book('book-a').deleteSync(recursive: true);
      encoder.finish.complete();
      await cancelled;
      expect(book('book-a').existsSync(), isFalse);
      await expectLater(
        store.put('hash', pcm, 24000, bookId: 'book-a'),
        throwsA(isA<AudioWriteCancelled>()),
      );
      expect(book('book-a').existsSync(), isFalse);
    },
  );

  test('при запуске удаляется недописанный звук; готовые файлы и чужие tmp не трогаются', () async {
    final store = FileAudioStore(root, encoder: const WavAudioEncoder());
    await store.put('ready', pcm, 24000, bookId: 'book-a');
    final unfinished = File('${root.path}/tmp/audio/write-killed/encoded.wav');
    unfinished.parent.createSync(recursive: true);
    unfinished.writeAsBytesSync([1, 2]);
    final incoming = File('${root.path}/tmp/import-book/source.fb2')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('исходник');
    final restarted = FileAudioStore(root, encoder: const WavAudioEncoder());
    expect(unfinished.existsSync(), isFalse);
    expect(restarted.has('ready', bookId: 'book-a'), isTrue);
    expect(incoming.existsSync(), isTrue);
    expect(restarted.totalBytes, 52);
  });

  test('неправильные компоненты пути и PCM отклоняются без записи', () async {
    final store = FileAudioStore(root, encoder: const WavAudioEncoder());
    for (final bad in ['../escape', '/absolute', '', 'a/b', 'a\\b', '..']) {
      expect(() => store.has(bad), throwsArgumentError);
      await expectLater(
        store.put('hash', pcm, 24000, bookId: bad),
        throwsArgumentError,
      );
    }
    await expectLater(
      store.put('hash', Uint8List(1), 24000),
      throwsArgumentError,
    );
    await expectLater(store.put('hash', pcm, 0), throwsArgumentError);
    expect(store.totalBytes, 0);
  });

  test('FakeAudioStore сохраняет старые операции и новые отпечатки', () async {
    final store = FakeAudioStore({'book-a': 100}, samplesBytes: 20);
    store.addBook('book-a', 10);
    store.addSamples(5);
    expect(store.totalBytes, 135);
    expect(store.has('hash', bookId: 'book-a'), isFalse);
    await store.put('hash', pcm, 24000, bookId: 'book-a');
    await store.put('hash', pcm, 24000, bookId: 'book-a');
    expect(store.totalBytes, 143);
    expect(store.file('hash', bookId: 'book-a'), isNotNull);
    store.removeBook('book-a');
    expect(store.has('hash', bookId: 'book-a'), isFalse);
    expect(store.totalBytes, 25);
    await store.put('sample', pcm, 24000);
    store.clearAll();
    expect(store.has('sample'), isFalse);
    expect(store.totalBytes, 0);
  });
}
