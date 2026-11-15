import 'dart:convert';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

void main() {
  List<String> texts(List<int> bytes) =>
      checked(bytes).book.blocks.map((b) => b.text).toList();

  test('FR-B5: UTF-8 с BOM и без; кириллица и другие алфавиты сохраняются', () {
    const text = 'Привет, Ёж! № 1 — «да». Łódź 日本 😀';
    for (final bytes in [
      utf8.encode(text),
      [239, 187, 191, ...utf8.encode(text)],
    ]) {
      expect(texts(bytes), [text]);
    }
    expect(texts(utf8.encode('Внутри \uFEFF текста')), [
      'Внутри \uFEFF текста',
    ]);
  });

  test('FR-B5: невалидный UTF-8 целиком читается как windows-1251', () {
    // Привет, Ёж! № 1 — «да». — байты, не зависящие от декодера приложения.
    final bytes = [
      207,
      240,
      232,
      226,
      229,
      242,
      44,
      32,
      168,
      230,
      33,
      32,
      185,
      32,
      49,
      32,
      151,
      32,
      171,
      228,
      224,
      187,
      46,
    ];
    expect(texts(bytes), ['Привет, Ёж! № 1 — «да».']);
    expect(texts([239, 187, 191, ...bytes]), ['Привет, Ёж! № 1 — «да».']);
    // Одна и та же последовательность валидна в UTF-8: приоритет у UTF-8.
    expect(texts([208, 144]), ['А']);
    expect(texts([208, 144, 32, 255]), ['Рђ я']);
  });

  test(
    'FR-B5: декларация XML у обычного TXT не выбирает кодировку и не удаляется',
    () {
      const text = '<?xml encoding="windows-1251"?>\nПривет';
      expect(texts(utf8.encode(text)), [
        '<?xml encoding="windows-1251"?>',
        'Привет',
      ]);
    },
  );

  test(
    'FR-B5: пустая строка включает склейку, без неё каждая строка — абзац',
    () {
      expect(texts(utf8.encode('Один\nдва\n\nТри\nчетыре')), [
        'Один два',
        'Три четыре',
      ]);
      expect(texts(utf8.encode('Один\nдва\nТри\nчетыре')), [
        'Один',
        'два',
        'Три',
        'четыре',
      ]);
    },
  );

  test('FR-B5: пустые строки только по краям не включают склейку', () {
    expect(texts(utf8.encode('\n \nОдин\nдва\n\t\n')), ['Один', 'два']);
    expect(texts(utf8.encode('\n \nОдин\nдва\n\nТри\n\t\n')), [
      'Один два',
      'Три',
    ]);
    expect(texts(utf8.encode('Единственная\n')), ['Единственная']);
  });

  test('FR-B5: CRLF, CR и LF равноправны, в том числе в одном файле', () {
    for (final end in ['\r\n', '\r', '\n']) {
      expect(texts(utf8.encode(['Один', 'два', '', 'Три'].join(end))), [
        'Один два',
        'Три',
      ]);
      expect(texts(utf8.encode(['Один', 'два'].join(end))), ['Один', 'два']);
    }
    expect(texts(utf8.encode('Один\r\nдва\r\rТри\nчетыре')), [
      'Один два',
      'Три четыре',
    ]);
    expect(texts(utf8.encode('Один\r\nдва\rТри\nчетыре')), [
      'Один',
      'два',
      'Три',
      'четыре',
    ]);
  });

  test(
    'FR-B5: пробельные строки — разделители, пробелы внутри текста — нет',
    () {
      expect(texts(utf8.encode('  Один  \n\tдва\t\n \t\u00a0 \nТри')), [
        'Один два',
        'Три',
      ]);
      expect(texts(utf8.encode('Один  два\n\tтри четыре')), [
        'Один  два',
        'три четыре',
      ]);
      expect(texts(utf8.encode('Один\n . \nдва')), ['Один', '.', 'два']);
    },
  );

  test(
    'FR-B5/B6: пустой файл и одни пустые строки отклоняются, один блок — нет',
    () {
      for (final bytes in [
        <int>[],
        [239, 187, 191],
        utf8.encode('\r\n\r\n'),
        utf8.encode(' \t\n\u00a0\r\n \r'),
      ]) {
        expect(
          () => parseBook(bytes),
          throwsA(
            isA<BookParseException>().having(
              (e) => e.reason,
              'reason',
              ParseFailure.unreadable,
            ),
          ),
        );
      }
      expect(texts(utf8.encode(' \nА\n ')), ['А']);
      expect(texts(utf8.encode('...')), ['...']);
    },
  );

  test('FR-B5: одна глава без названия, только абзацы, без эвристик и XML-разметки', () {
    const text = 'Глава 1\nПере-\nнос\n\n<p>Текст &amp; [1]</p>\n***';
    final result = checked(utf8.encode(text));
    final book = result.book;
    expect(book.blocks.map((b) => b.text), [
      'Глава 1 Пере- нос',
      '<p>Текст &amp; [1]</p> ***',
    ]);
    expect(
      book.blocks.every(
        (b) => b.kind == BlockKind.paragraph && b.spans.isEmpty,
      ),
      isTrue,
    );
    expect(chapters(book), [('', 1, 0, 2)]);
    expect(book.title, '');
    expect(book.author, '');
    expect(book.language, '');
    expect(book.notes, isEmpty);
    expect(book.parserVersion, currentParserVersion);
    expect(result.images, isEmpty);
    expect(result.cover, isNull);
  });
}
