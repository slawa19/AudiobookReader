import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audiobook_reader/audio/file_audio_store.dart';
import 'package:audiobook_reader/audio/wav_audio_encoder.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';
import 'support/library_time.dart';

List<int> sample([String name = 'fb2_sections.xml']) =>
    utf8.encode(fixture(name));
AppSettings defaults() => AppSettings(voice: 'default', modelId: 'model');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FileLibrary library;
  late LibraryTime time;

  Future<void> start({LibraryParser? parser}) async {
    library = FileLibrary(
      root,
      settings: defaults(),
      clock: time.call,
      timer: time.timer,
      parser: parser,
    );
    await library.ready;
  }

  Future<String> add([List<int>? bytes]) async =>
      (await library.addTestBytes(bytes ?? sample(), 'book.fb2'))!.id;

  File stateFile(String id) => File('${root.path}/books/$id/state.json');
  Map<String, Object?> read(File file) =>
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

  Future<void> restart() async {
    await library.flush();
    library.dispose();
    await start();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library-');
    time = LibraryTime();
    await start();
  });
  tearDown(() async {
    await library.flush();
    library.dispose();
    await root.delete(recursive: true);
  });

  for (final withAudio in [false, true]) {
    test('FR-1: размер книги после перезапуска, озвучка=$withAudio', () async {
      final id = await add();
      final before = library.shelf.single.bookBytes;
      expect(before, greaterThan(0));
      if (withAudio) {
        final audio = FileAudioStore(root, encoder: const WavAudioEncoder());
        addTearDown(audio.dispose);
        await audio.put('segment', Uint8List.fromList([0, 0, 1, 0]), 24000, bookId: id);
        expect(audio.bytesForBook(id), greaterThan(0));
      }
      await restart();
      expect(library.shelf.single.bookBytes, before);
    });
  }

  for (final damaged in ['missing-meta', 'missing-state', 'empty', 'broken', 'empty-state', 'broken-state', 'empty-dir']) {
    test('повреждённая книга $damaged не мешает здоровой и сохраняет исходник', () async {
      final good = await add();
      final bad = await add(sample('fb2_plain.xml'));
      final dir = Directory('${root.path}/books/$bad');
      library.dispose();
      if (damaged == 'empty-dir') {
        await dir.delete(recursive: true);
        await dir.create();
      } else {
        final file = File('${dir.path}/${damaged.endsWith('state') ? 'state' : 'meta'}.json');
        if (damaged.startsWith('missing')) {
          await file.delete();
        } else {
          await file.writeAsString(damaged.startsWith('empty') ? '' : '{broken');
        }
      }
      await start();
      expect(library.shelf.map((e) => e.id), [good]);
      expect(await dir.exists(), isTrue);
      if (damaged != 'empty-dir') {
        expect(await File('${dir.path}/original.fb2').readAsBytes(), sample('fb2_plain.xml'));
      }
    });
  }

  for (final config in ['', '{broken', '{}', '{"theme":"dark"}', '[]', 'null', '{"theme":"unknown","fontStep":"bad","speed":false,"voice":7}']) {
    test('настройки с неполным или битым JSON: $config', () async {
      library.dispose();
      await File('${root.path}/settings.json').writeAsString(config);
      await start();
      expect(library.settings.theme, config.contains('dark') ? ThemeChoice.dark : ThemeChoice.system);
      expect(library.settings.fontStep, defaultFontStep);
      expect(library.settings.speed, 1);
      expect(library.settings.voice, 'default');
      expect(library.settings.modelId, 'model');
    });
  }

  test('удаление сначала переносит в tmp: сбой переноса сохраняет живую книгу', () async {
    final id = await add();
    final tmp = Directory('${root.path}/tmp');
    await tmp.delete(recursive: true);
    await File(tmp.path).writeAsString('занято');
    try {
      await expectLater(library.deleteBook(id), throwsA(isA<FileSystemException>()));
      expect(library.shelf.single.id, id);
      expect(await File('${root.path}/books/$id/original.fb2').exists(), isTrue);
    } finally {
      await File(tmp.path).delete();
      await tmp.create();
    }
    await library.deleteBook(id);
    expect(library.shelf, isEmpty);
    expect(await Directory('${root.path}/books/$id').exists(), isFalse);
  });

  test('ошибка записи отдаётся один раз, позиция и настройки дописываются без нового изменения', () async {
    final id = await add();
    await library.loadBook(id);
    await library.flush();
    final blocked = Directory('${stateFile(id).path}.new');
    await blocked.create();
    library.savePosition(id, const ReadingPosition(1, 1));
    await expectLater(library.flush(), throwsA(isA<FileSystemException>()));
    await blocked.delete();
    await library.flush();
    expect((read(stateFile(id))['position']! as Map)['block'], 1);
    final blockedSettings = Directory('${root.path}/settings.json.new');
    await blockedSettings.create();
    library.settings.theme = ThemeChoice.dark;
    await expectLater(library.flush(), throwsA(isA<FileSystemException>()));
    await blockedSettings.delete();
    await library.flush();
    expect(read(File('${root.path}/settings.json'))['theme'], 'dark');
    await library.flush();
  });

  test('FR-L1,L6: запуск чистит tmp, но сохраняет готовую книгу', () async {
    final id = await add();
    final abandoned = File('${root.path}/tmp/abandoned/source');
    await abandoned.create(recursive: true);
    await abandoned.writeAsBytes(sample());
    expect(await abandoned.exists(), isTrue);
    await restart();
    expect(await Directory('${root.path}/tmp').list().isEmpty, isTrue);
    expect(library.shelf.single.id, id);
    expect((await library.loadBook(id)).blocks, isNotEmpty);
  });

  test(
    'SC-1: прерывание добавления до переименования не оставляет книги',
    () async {
      library.dispose();
      final entered = Completer<void>();
      final parsed = Completer<ParsedBook>();
      await start(
        parser: (bytes) {
          entered.complete();
          return parsed.future;
        },
      );
      final old = library;
      final adding = library.addTestBytes(sample(), 'interrupted.fb2');
      await entered.future;
      expect(library.addJobs.single.status, AddJobStatus.adding);
      expect(library.shelf, isEmpty);
      expect(
        await Directory('${root.path}/tmp')
            .list(recursive: true)
            .where((f) => f is File)
            .length,
        1,
      );
      old.dispose();
      await start();
      expect(library.shelf, isEmpty);
      expect(await Directory('${root.path}/tmp').list().isEmpty, isTrue);
      parsed.complete(parseBook(sample()));
      expect(await adding, isNull);
      expect(library.shelf, isEmpty);
      // Контроль: завершённое добавление после перезапуска видно и переживает ещё один запуск.
      final id = await add();
      await restart();
      expect(library.shelf.single.id, id);
    },
  );

  test('FR-L2,L3: строка до конца разбора, два одновременных добавления — один разбор', () async {
    library.dispose();
    final entered = Completer<void>();
    final release = Completer<ParsedBook>();
    var calls = 0;
    await start(
      parser: (bytes) {
        calls++;
        entered.complete();
        return release.future;
      },
    );
    final one = library.addTestBytes(sample(), 'one.fb2');
    await entered.future;
    final two = library.addTestBytes(sample(), 'renamed.bin');
    expect(library.addJobs.single.status, AddJobStatus.adding);
    expect(library.shelf, isEmpty);
    release.complete(parseBook(sample()));
    final results = await Future.wait([one, two]);
    expect(results[0]!.id, results[1]!.id);
    expect(calls, 1);
    expect(library.shelf, hasLength(1));
    expect(library.addJobs, isEmpty);
    expect((await library.addTestBytes(sample(), 'again.fb2'))!.id, results[0]!.id);
    expect(calls, 1);
  });

  test('добавление по пути сохраняет свою копию и не удаляет источник', () async {
    final source = await File('${root.path}/input.fb2').writeAsBytes(sample());
    final id = (await library.addFile(source.path, 'copy.fb2'))!.id;
    expect(
      await File('${root.path}/books/$id/original.fb2').readAsBytes(),
      sample(),
    );
    expect(await source.exists(), isTrue);
    await source.delete();
    expect((await library.loadBook(id)).blocks, isNotEmpty);
  });

  test('слишком большой файл отклоняется до разбора; обычная книга принимается', () async {
    var calls = 0;
    library.dispose();
    await start(parser: (path) async {
      calls++;
      return parseBook(await File(path).readAsBytes());
    });
    final source = File('${root.path}/huge.zip');
    final handle = await source.open(mode: FileMode.write);
    await handle.truncate(maxBookFileBytes + 1);
    await handle.close();
    expect(await library.addFile(source.path, 'huge.zip'), isNull);
    expect(library.addJobs.single.failure, AddFailure.unsupported);
    expect(calls, 0);
    expect(library.shelf, isEmpty);
    expect(await Directory('${root.path}/tmp').list().isEmpty, isTrue);
    expect(await add(), isNotEmpty);
    expect(calls, 1);
  });

  for (final (reason, bytes) in [
    (AddFailure.unsupported, utf8.encode('%PDF-1.7')),
    (AddFailure.protected, epub(encryption: 'OPS/text.xhtml')),
    (AddFailure.unreadable, sample('fb2_bad_attribute.xml')),
  ]) {
    test(
      'FR-B2,B6: отказ ${reason.name} и техническая строка как у разборщика',
      () async {
        late BookParseException expected;
        try {
          parseBook(bytes);
        } on BookParseException catch (e) {
          expected = e;
        }
        expect(await library.addTestBytes(bytes, 'bad.file'), isNull);
        expect(library.shelf, isEmpty);
        final job = library.addJobs.single;
        expect(job.status, AddJobStatus.failed);
        expect(job.failure, reason);
        expect(job.technical, expected.technical);
        if (reason == AddFailure.unreadable) expect(job.technical, isNotEmpty);
        expect(await Directory('${root.path}/tmp').list().isEmpty, isTrue);
        library.dismissAddJob(job);
        expect(library.addJobs, isEmpty);
        expect(await add(), isNotEmpty);
      },
    );
  }

  test(
    'FR-L3,L5: удаление всей папки и повторное добавление новой книгой',
    () async {
      final id = await add();
      await library.loadBook(id);
      library.markOpened(id);
      library.setFinished(id, true);
      library.setBookVoice(id, 'custom');
      await library.flush();
      final dir = Directory('${root.path}/books/$id');
      final extra = File('${dir.path}/nested/test.bin');
      await extra.create(recursive: true);
      await extra.writeAsBytes(List.filled(137, 1));
      await library.deleteBook(id);
      expect(await dir.exists(), isFalse);
      expect(await extra.exists(), isFalse);
      expect(library.shelf, isEmpty);
      expect(await add(), id);
      expect(library.entry(id).opened, isFalse);
      expect(library.isFinished(id), isFalse);
      expect(library.bookVoice(id), isNull);
    },
  );

  test('FR-L4: карточка последней открытой, новые не забирают её; порядок переживает запуск', () async {
    final first = await add();
    time.advance(const Duration(seconds: 1));
    final second = await add(sample('fb2_metadata.xml'));
    expect(library.shelf.map((e) => e.id), [second, first]);
    expect(library.shelf.every((e) => !e.opened && e.fraction == null), isTrue);
    library.markOpened(first);
    time.advance(const Duration(seconds: 1));
    library.markOpened(second);
    time.advance(const Duration(seconds: 1));
    final fresh = await add(sample('fb2_plain.xml'));
    expect(library.shelf.first.id, second);
    // Интерфейс берёт открытые для карточки, неоткрытые — первыми под ней.
    expect(library.shelf.where((e) => !e.opened).single.id, fresh);
    expect(library.shelf.where((e) => e.opened).map((e) => e.id), [
      second,
      first,
    ]);
    await restart();
    expect(library.shelf.map((e) => e.id), [second, first, fresh]);
  });

  test(
    'FR-L4: доля, глава и явный факт дочитывания независимы от двух позиций',
    () async {
      final id = await add();
      final book = await library.loadBook(id);
      expect(book.chapters, hasLength(2));
      library.markOpened(id);
      expect(library.entry(id).chapterTitle, isEmpty);
      final block = book.chapters[1].firstBlock;
      library.savePosition(
        id,
        ReadingPosition(block, 1),
        fraction: 0,
      );
      expect(library.entry(id).fraction, book.fractionAt(block, 1));
      expect(library.entry(id).chapterTitle, book.chapters[1].title);
      library.saveListeningPosition(id, const ReadingPosition(0, 0));
      expect(library.entry(id).chapterTitle, book.chapters[1].title);
      await restart();
      expect(library.entry(id).chapterTitle, book.chapters[1].title);
      await library.loadBook(id);
      library.setFinished(id, true);
      library.savePosition(id, const ReadingPosition(0, 0));
      expect(library.entry(id).fraction, 1);
      await restart();
      expect(library.isFinished(id), isTrue);
      expect(library.entry(id).fraction, 1);
      library.setFinished(id, false);
      expect(library.entry(id).fraction, 0);
      await restart();
      expect(library.isFinished(id), isFalse);
    },
  );

  test('FR-L1,R7: flush сохраняет последнее из частых изменений, оба места и голос', () async {
    final id = await add();
    final book = await library.loadBook(id);
    library.markOpened(id);
    await library.flush();
    for (var i = 0; i < 20; i++) {
      library.savePosition(id, ReadingPosition(i % book.blocks.length, 1));
      library.saveListeningPosition(id, const ReadingPosition(1, 2));
      library.setBookVoice(id, 'voice-$i');
    }
    expect(time.activeTimers, 1);
    expect(
      read(stateFile(id))['position'],
      isNull,
      reason: 'до flush запись отложена',
    );
    await library.flush();
    expect(time.activeTimers, 0);
    final saved = read(stateFile(id));
    final pos = saved['position']! as Map<String, Object?>;
    expect(pos['block'], 19 % book.blocks.length);
    expect(pos['offset'], 1);
    expect(pos['charsBefore'], book.charsBefore(19 % book.blocks.length));
    expect(pos['anchorText'], book.blocks[19 % book.blocks.length].text);
    expect((saved['listeningPosition']! as Map)['offset'], 2);
    expect(saved['voice'], 'voice-19');
    await restart();
    expect(library.positionOf(id), ReadingPosition(19 % book.blocks.length, 1));
    expect(library.listeningPositionOf(id), const ReadingPosition(1, 2));
    expect(library.bookVoice(id), 'voice-19');
    // Обратная сторона: запись только места прослушивания сохраняет прежнюю позицию чтения.
    await library.loadBook(id);
    library.saveListeningPosition(id, const ReadingPosition(0, 0));
    await restart();
    expect(library.positionOf(id), ReadingPosition(19 % book.blocks.length, 1));
    expect(library.listeningPositionOf(id), const ReadingPosition(0, 0));
  });

  test('писатель ограничивает частоту и сам дописывает хвост через подставную секунду', () async {
    final id = await add();
    await library.loadBook(id);
    library.savePosition(id, const ReadingPosition(0, 1));
    await library.flush();
    library.savePosition(id, const ReadingPosition(1, 1));
    time.advance(const Duration(milliseconds: 999));
    expect((read(stateFile(id))['position']! as Map)['block'], 0);
    library.savePosition(id, const ReadingPosition(2, 1));
    time.advance(const Duration(milliseconds: 1));
    // Дожидаемся файловой записи, не вызывая flush и не двигая часы ещё на секунду.
    await _until(() => (read(stateFile(id))['position']! as Map)['block'] == 2);
    expect(time.activeTimers, 0);
    expect((read(stateFile(id))['position']! as Map)['block'], 2);
  });

  test('полка и обложка читаются из meta/state без book.json; книга декодируется при открытии', () async {
    final id = await add(epub());
    expect(library.entry(id).cover, isA<FileImage>());
    expect(await File('${root.path}/books/$id/cover.jpg').readAsBytes(), [
      1,
      2,
      3,
    ]);
    final file = File('${root.path}/books/$id/book.json');
    final good = await file.readAsString();
    await file.writeAsString('не JSON');
    await restart();
    expect(library.shelf.single.id, id);
    await expectLater(library.loadBook(id), throwsFormatException);
    await file.writeAsString(good);
    expect((await library.loadBook(id)).id, id);
    expect(library.image(id, 'OPS/pic.png'), isA<FileImage>());
  });

  test(
    'настройки переживают запуск, ключ в settings.json не попадает',
    () async {
      library.settings
        ..theme = ThemeChoice.sepia
        ..fontStep = 4
        ..language = 'pl'
        ..speed = 1.5
        ..voice = 'custom'
        ..modelId = 'other'
        ..apiKey = 'secret-test';
      await library.flush();
      final saved = await File('${root.path}/settings.json').readAsString();
      expect(saved, isNot(contains('secret-test')));
      expect(saved, isNot(contains('apiKey')));
      await restart();
      expect(library.settings.theme, ThemeChoice.sepia);
      expect(library.settings.fontStep, 4);
      expect(library.settings.language, 'pl');
      expect(library.settings.speed, 1.5);
      expect(library.settings.voice, 'custom');
      expect(library.settings.modelId, 'other');
      expect(library.settings.hasApiKey, isFalse);
      library.settings.language = null;
      library.settings.theme = ThemeChoice.system;
      await restart();
      expect(library.settings.language, isNull);
      expect(library.settings.theme, ThemeChoice.system);
    },
  );

  test('картинки и обложка — файлы, размеры доступны после запуска без загрузки книги', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(7, 5);
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    image.dispose();
    picture.dispose();
    final id = await add(
      epub(
        content: fixture('epub_inline_image.xhtml'),
        raw: {'OPS/pic.png': png},
      ),
    );
    expect(library.imageSizes(id), {'OPS/pic.png': const ui.Size(7, 5)});
    final provider = library.image(id, 'OPS/pic.png') as FileImage;
    expect(await provider.file.readAsBytes(), png);
    expect(
      await (library.entry(id).cover! as FileImage).file.readAsBytes(),
      png,
    );
    await restart();
    expect(library.imageSizes(id), {'OPS/pic.png': const ui.Size(7, 5)});
  });

  for (final interrupted in [false, true]) {
    for (final anchorFound in [true, false]) {
      test(
        'FR-R7: переразбор${interrupted ? ' прерван после book.json' : ''}, якорь ${anchorFound ? 'найден, ближайший' : 'не найден, charsBefore'}',
        () async {
          final id = await add(
            anchorFound
                ? utf8.encode(
                    fixture('fb2_sections.xml').replaceFirst('Один.', 'Два.'),
                  )
                : sample(),
          );
          final book = await library.loadBook(id);
          library.markOpened(id);
          library.setBookVoice(id, 'custom');
          library.setFinished(id, true);
          library.savePosition(id, const ReadingPosition(1, 2));
          library.saveListeningPosition(id, const ReadingPosition(3, 1));
          await library.flush();
          final path = File('${root.path}/books/$id/book.json');
          final older = read(path)
            ..['parserVersion'] = interrupted
                ? currentParserVersion
                : currentParserVersion - 1;
          await path.writeAsString(jsonEncode(older));
          final state = read(stateFile(id));
          state['parserVersion'] = currentParserVersion - 1;
          final target = book.blocks[3].text;
          final expectedBlock = anchorFound ? 3 : 1;
          state['position'] = {
            'block': 0,
            'offset': 2,
            'charsBefore': book.charsBefore(expectedBlock),
            'anchorText': anchorFound ? target : 'Такого начала здесь нет',
          };
          final listeningBlock = anchorFound ? 1 : 3;
          state['listeningPosition'] = {
            'block': 0,
            'offset': 1,
            'charsBefore': book.charsBefore(listeningBlock),
            'anchorText': anchorFound
                ? book.blocks[1].text
                : 'Другого начала здесь тоже нет',
          };
          await stateFile(id).writeAsString(jsonEncode(state));
          library.dispose();
          await start();
          final reparsed = await library.loadBook(id);
          expect(reparsed.parserVersion, currentParserVersion);
          expect(read(path)['parserVersion'], currentParserVersion);
          expect(library.positionOf(id)!.block, expectedBlock);
          expect(library.positionOf(id)!.offset, 2);
          expect(
            library.positionOf(id)!.anchorText,
            reparsed.blocks[expectedBlock].text,
          );
          expect(library.listeningPositionOf(id)!.block, listeningBlock);
          expect(library.listeningPositionOf(id)!.offset, 1);
          expect(
            library.listeningPositionOf(id)!.charsBefore,
            reparsed.charsBefore(listeningBlock),
          );
          expect(
            library.listeningPositionOf(id)!.anchorText,
            reparsed.blocks[listeningBlock].text,
          );
          expect(read(stateFile(id))['parserVersion'], currentParserVersion);
          expect(library.bookVoice(id), 'custom');
          expect(library.isFinished(id), isTrue);
          await restart();
          expect(library.positionOf(id)!.block, expectedBlock);
        },
      );
    }
  }

  test('актуальная версия не запускает повторный разбор', () async {
    final id = await add();
    library.dispose();
    await start(
      parser: (_) => throw StateError('Повторного разбора быть не должно'),
    );
    final book = await library.loadBook(id);
    expect(book.parserVersion, currentParserVersion);
    expect(book.blocks, isNotEmpty);
  });

  test(
    'позиция хранит ровно первые 64 кодовые единицы, короткий блок целиком',
    () async {
      final text = List.filled(20, 'Текст😀').join();
      final id = await add(
        utf8.encode(fixture('fb2_plain.xml').replaceFirst('Заголовок', text)),
      );
      final book = await library.loadBook(id);
      library.savePosition(id, const ReadingPosition(0, 10));
      library.saveListeningPosition(id, const ReadingPosition(1, 2));
      await library.flush();
      final saved = read(stateFile(id));
      expect((saved['position']! as Map)['anchorText'], text.substring(0, 64));
      expect(
        (saved['listeningPosition']! as Map)['anchorText'],
        book.blocks[1].text,
      );
      await restart();
      expect(library.positionOf(id)!.anchorText.length, 64);
      expect(library.positionOf(id)!.offset, 10);
    },
  );

  test(
    'одинаковые показания часов сохраняют порядок добавлений и открытий',
    () async {
      final first = await add();
      final second = await add(sample('fb2_plain.xml'));
      expect(library.shelf.map((e) => e.id), [second, first]);
      library.markOpened(first);
      library.markOpened(second);
      expect(library.shelf.first.id, second);
      await restart();
      expect(library.shelf.map((e) => e.id), [second, first]);
    },
  );

  test(
    'FB2.ZIP: настоящий разбор и декодирование сохранённой модели',
    () async {
      // Настоящий путь без подставного parser: модель проходит границу изолята и хранится на диске.
      // Повторное создание ZIP получает новую временную метку; сравниваем с точным входом.
      final input = zip({'nested/book.fb2': sample()});
      final id = await add(input);
      expect(
        await File('${root.path}/books/$id/original.fb2.zip').readAsBytes(),
        input,
      );
      expect((await library.loadBook(id)).blocks.map((b) => b.text), [
        'А',
        'Один.',
        'Б',
        'Два.',
      ]);
    },
  );
}

/// Даём реальной файловой системе завершить операцию; это не часы ограничения записи.
Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('Запись на диск не завершилась');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
