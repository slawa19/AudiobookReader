import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/tts/segments.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FileLibrary library;

  Future<void> start() async {
    library = FileLibrary(
      root,
      settings: AppSettings(voice: 'default', modelId: 'model'),
    );
    await library.ready;
  }

  Future<void> restart() async {
    await library.flush();
    library.dispose();
    await start();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library-txt-');
    await start();
  });
  tearDown(() async {
    await library.flush();
    library.dispose();
    await root.delete(recursive: true);
  });

  test('FR-B5/L2: TXT добавляется, открывается, делится для речи и сохраняет позицию', () async {
    final bytes = utf8.encode('Первый\nабзац.\n\nВторой абзац.\n\n***');
    final source = await File('${root.path}/provider-copy.tmp')
        .writeAsBytes(bytes);
    final entry = (await library.addFile(source.path, 'Моя.книга.TXT'))!;
    expect(library.shelf.single.id, entry.id);
    expect(entry.title, 'Моя.книга');
    expect(entry.author, '');
    expect(library.addJobs, isEmpty);
    final book = await library.loadBook(entry.id);
    invariants(book);
    expect(book.title, entry.title);
    expect(book.author, '');
    expect(chapters(book), [('', 1, 0, 3)]);
    expect(book.blocks.map((b) => b.text), [
      'Первый абзац.',
      'Второй абзац.',
      '***',
    ]);
    expect(
      await File('${root.path}/books/${entry.id}/original.txt').readAsBytes(),
      bytes,
    );

    final chapter = book.chapters.single;
    final segments = chapterSegments(
      book.blocks.sublist(chapter.firstBlock, chapter.endBlock),
    );
    expect(segments.map((s) => s.text).join(), 'Первый абзац.\nВторой абзац.');
    final mappings = segments.expand((s) => s.mappings).toList();
    expect(mappings.map((m) => m.block).toSet(), {0, 1});
    for (final segment in segments) {
      for (final mapping in segment.mappings) {
        expect(
          segment.text.substring(mapping.start, mapping.end),
          book.blocks[mapping.block].text.substring(
            mapping.blockStart,
            mapping.blockEnd,
          ),
        );
      }
    }

    library.markOpened(entry.id);
    library.savePosition(entry.id, const ReadingPosition(1, 3));
    await restart();
    expect(library.shelf.single.title, 'Моя.книга');
    expect(library.shelf.single.chapterTitle, '');
    expect(library.shelf.single.opened, isTrue);
    expect(library.shelf.single.fraction, book.fractionAt(1, 3));
    expect((await library.loadBook(entry.id)).title, 'Моя.книга');
    final saved = library.positionOf(entry.id)!;
    expect(
      (saved.block, saved.offset, saved.charsBefore, saved.anchorText),
      (1, 3, book.charsBefore(1), book.blocks[1].text),
    );
    expect((await library.addFile(source.path, 'Другое.txt'))!.id, entry.id);
    expect(library.shelf, hasLength(1));
    expect(library.shelf.single.title, 'Моя.книга');

    // Переразбор читает original.txt, но название должно остаться именем от провайдера.
    final modelFile = File('${root.path}/books/${entry.id}/book.json');
    final model =
        jsonDecode(await modelFile.readAsString()) as Map<String, Object?>;
    model['parserVersion'] = 0;
    await modelFile.writeAsString(jsonEncode(model));
    await restart();
    expect((await library.loadBook(entry.id)).title, 'Моя.книга');
    expect(library.positionOf(entry.id)!.offset, 3);
    expect(library.shelf.single.title, 'Моя.книга');
  });

  test('FR-B2/L2: имя .txt не разрешает двоичные данные; текст с другим именем принимается', () async {
    final source = File('${root.path}/input.txt');
    for (var byte = 0; byte <= 8; byte++) {
      await source.writeAsBytes([...utf8.encode('Текст'), byte]);
      expect(await library.addFile(source.path, 'binary.txt'), isNull);
      expect(library.addJobs.first.failure, AddFailure.unsupported);
      expect(library.shelf, isEmpty);
    }
    await source.writeAsBytes(utf8.encode('Настоящий текст.'));
    final entry = (await library.addFile(source.path, 'Книга.bin'))!;
    expect(entry.title, 'Книга');
    expect(
      (await library.loadBook(entry.id)).blocks.single.text,
      'Настоящий текст.',
    );
    expect(
      await File('${root.path}/books/${entry.id}/original.txt').exists(),
      isTrue,
    );
  });

  test(
    'FR-B6: пустой TXT даёт обычный отказ unreadable и не попадает на полку',
    () async {
      final source = await File('${root.path}/empty.txt')
          .writeAsBytes(utf8.encode(' \n\r\n\t'));
      expect(await library.addFile(source.path, 'empty.txt'), isNull);
      expect(library.addJobs.single.failure, AddFailure.unreadable);
      expect(library.shelf, isEmpty);
      expect(await Directory('${root.path}/tmp').list().isEmpty, isTrue);
      await source.writeAsBytes(utf8.encode('Один абзац.'));
      expect(await library.addFile(source.path, 'Без расширения'), isNotNull);
      expect(library.shelf.single.title, 'Без расширения');
    },
  );

  test(
    'название FB2 по-прежнему берётся из метаданных, а не из имени файла',
    () async {
      final source = await File('${root.path}/input.txt').writeAsBytes(
        utf8.encode(
          '<FictionBook><body><section><p>Текст.</p></section></body></FictionBook>',
        ),
      );
      final entry = (await library.addFile(source.path, 'Название.txt'))!;
      expect(entry.title, '');
      expect((await library.loadBook(entry.id)).title, '');
    },
  );
}
