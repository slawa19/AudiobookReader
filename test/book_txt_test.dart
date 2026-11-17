import 'dart:convert';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

void main() {
  List<String> texts(List<int> bytes) =>
      checked(bytes).book.blocks.map((b) => b.text).toList();

  test('FR-B5: UTF-8 with and without BOM; Cyrillic and other alphabets are preserved', () {
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

  test('FR-B5: invalid UTF-8 is read entirely as windows-1251', () {
    // Привет, Ёж! № 1 — «да». — bytes that do not depend on the application decoder.
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
    // The same sequence is valid in UTF-8: UTF-8 takes priority.
    expect(texts([208, 144]), ['А']);
    expect(texts([208, 144, 32, 255]), ['Рђ я']);
  });

  test(
    'FR-B5: an XML declaration in a plain TXT does not select the encoding and is not removed',
    () {
      const text = '<?xml encoding="windows-1251"?>\nПривет';
      expect(texts(utf8.encode(text)), [
        '<?xml encoding="windows-1251"?>',
        'Привет',
      ]);
    },
  );

  test(
    'FR-B5: an empty line enables merging, without one every line is a paragraph',
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

  test('FR-B5: empty lines only at the edges do not enable merging', () {
    expect(texts(utf8.encode('\n \nОдин\nдва\n\t\n')), ['Один', 'два']);
    expect(texts(utf8.encode('\n \nОдин\nдва\n\nТри\n\t\n')), [
      'Один два',
      'Три',
    ]);
    expect(texts(utf8.encode('Единственная\n')), ['Единственная']);
  });

  test('FR-B5: CRLF, CR and LF are equivalent, including within one file', () {
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
    'FR-B5: whitespace-only lines are separators, spaces inside text are not',
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
    'FR-B5/B6: an empty file and only empty lines are rejected, a single block is not',
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

  test('FR-B5: one chapter without a title, paragraphs only, no heuristics and no XML markup', () {
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
