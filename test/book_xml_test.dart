import 'dart:convert';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

List<int> cp1251(String text) => [
  for (final c in text.runes)
    if (c >= 1040 && c <= 1103)
      c - 848
    else
      switch (c) {
        1025 => 168,
        1105 => 184,
        8470 => 185,
        8212 => 151,
        171 => 171,
        187 => 187,
        _ => c,
      },
];

void main() {
  test('FR-B6: the UTF-8 fallback also applies in an EPUB document', () {
    final b = checked(
      epub(raw: {'OPS/text.xhtml': cp1251(fixture('epub_encoding.xhtml'))}),
    ).book;
    expect(b.blocks.single.text, 'Привет, Ёж! № 1 — «да».');
    expect(chapters(b), [('Первая', 1, 0, 1)]);
    expect(b.notes, isEmpty);
  });
  test('FR-B6: closing by an ancestor and by the end of the file; closed tags do not swallow neighbours', () {
    final damaged = checked(utf8.encode(fixture('fb2_unclosed.xml'))).book;
    final good = checked(utf8.encode(fixture('fb2_closed.xml'))).book;
    for (final b in [damaged, good]) {
      expect(b.blocks.map((b) => b.text), ['До внутри', 'После.', 'Конец.']);
      expect(chapters(b), [('', 1, 0, 2), ('', 1, 2, 1)]);
      expect(b.notes, isEmpty);
      expect(b.blocks.first.spans.map((s) => (s.start, s.end, s.style)), [
        (3, 9, SpanStyle.italic),
      ]);
      expect(b.blocks[1].spans, isEmpty);
    }
  });
  test('FR-B6: an unknown entity is preserved, known and numeric ones are expanded', () {
    final b = checked(utf8.encode(fixture('fb2_entities.xml'))).book;
    expect(b.blocks.single.text, '& < > " \' A 😀 &unknown;');
    expect(chapters(b), [('', 1, 0, 1)]);
    expect(b.notes, isEmpty);
  });
  test('FR-B3/B6: windows-1251 from the declaration; only a declared UTF-8 allows the fallback', () {
    final source = fixture('fb2_encoding.xml');
    for (final bytes in [
      cp1251(source),
      cp1251(source.replaceFirst('windows-1251', 'UTF-8')),
      utf8.encode(source.replaceFirst('windows-1251', 'UTF-8')),
    ]) {
      final b = checked(bytes).book;
      expect(b.blocks.single.text, 'Привет, Ёж! № 1 — «да».');
      expect(chapters(b), [('', 1, 0, 1)]);
      expect(b.notes, isEmpty);
    }
    expect(
      () => parseBook(
        cp1251(
          source.replaceFirst(
            '<?xml version="1.0" encoding="windows-1251"?>',
            '',
          ),
        ),
      ),
      throwsA(
        isA<BookParseException>().having(
          (e) => e.reason,
          'reason',
          ParseFailure.unreadable,
        ),
      ),
    );
  });
  test('FR-B6: other XML errors and the absence of main text are rejected with a reason', () {
    for (final source in [
      fixture('fb2_bad_attribute.xml'),
      fixture('fb2_empty.xml'),
      for (final kind in [
        'closing',
        'duplicate',
        'entity',
        'character',
        'roots',
        'comment',
        'opening',
        'attribute',
        'namespace',
        'expanded_attribute',
        'pi',
        'comment_dash',
        'doctype',
      ])
        fixture('xml_bad_$kind.xml'),
    ]) {
      expect(
        () => parseBook(utf8.encode(source)),
        throwsA(
          isA<BookParseException>()
              .having((e) => e.reason, 'reason', ParseFailure.unreadable)
              .having((e) => e.technical, 'technical', isNotEmpty),
        ),
        reason: source,
      );
    }
  });
  test('FR-B6: a valid declaration, DTD, PI, CDATA, comment and namespace are not corruption', () {
    final b = checked(utf8.encode(fixture('xml_valid.xml'))).book;
    expect(b.blocks.single.text, 'Текст & < >. A');
    expect(chapters(b), [('', 1, 0, 1)]);
    expect(b.notes, isEmpty);
  });
  test(
    'FR-B6: the same corruption and the ban on empty text apply in EPUB XHTML',
    () {
      final b = checked(epub(content: fixture('epub_unclosed.xhtml'))).book;
      expect(b.blocks.map((b) => b.text), ['Один два', '&unknown;']);
      expect(chapters(b), [('Первая', 1, 0, 2)]);
      expect(b.notes, isEmpty);
      expect(
        () => parseBook(epub(content: fixture('epub_bad_attribute.xhtml'))),
        throwsA(
          isA<BookParseException>().having(
            (e) => e.reason,
            'reason',
            ParseFailure.unreadable,
          ),
        ),
      );
      expect(
        () => parseBook(epub(content: fixture('epub_empty.xhtml'))),
        throwsA(
          isA<BookParseException>().having(
            (e) => e.reason,
            'reason',
            ParseFailure.unreadable,
          ),
        ),
      );
    },
  );
}
