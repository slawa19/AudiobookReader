import 'dart:convert';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

String navTo(String href) =>
    fixture('epub_single_nav.xhtml').replaceAll('HREF', href);

const defaultEpubText = [
  'До.',
  'Заголовок',
  'В контейнере.',
  'После якоря.',
  'Начало. Ещё.',
  'До середины.',
  'Последний.',
];

void main() {
  test('BF01: HTML entities decode, unknown names and escaped entities stay literal', () {
    for (final fb2 in [false, true]) {
      final source = fixture(
        fb2 ? 'fb2_html_entities.xml' : 'epub_html_entities.xhtml',
      );
      final b = checked(
        fb2
            ? utf8.encode(source)
            : epub(content: source, nav: navTo('../text.xhtml')),
      ).book;
      expect(b.blocks.map((b) => b.text), [
        'Он сказал — «да»…',
        '&name; &nbsp; α € ≂̸',
      ]);
      expect(chapters(b), [(fb2 ? '' : 'Глава', 1, 0, 2)]);
      expect(b.notes, isEmpty);
      expect(b.parserVersion, greaterThan(1));
    }
  });

  for (final tag in ['br', 'hr', 'img', 'empty-line', 'image']) {
    test('BF02: unclosed $tag preserves children as siblings', () {
      final fb2 = tag == 'empty-line' || tag == 'image';
      for (final closed in [false, true]) {
        final source = fixture(fb2 ? 'fb2_void.xml' : 'epub_void.xhtml')
            .replaceAll('BR', tag == 'br' ? '<brCLOSE>' : ' ')
            .replaceAll('VOID', tag == 'br' ? '' : '<TAG src="pic.png"CLOSE>')
            .replaceAll('TAG', tag)
            .replaceAll('CLOSE', closed ? '/' : '');
        final b = checked(
          fb2
              ? utf8.encode(source)
              : epub(content: source, nav: navTo('../text.xhtml')),
        ).book;
        expect(b.blocks.map((b) => (b.kind, b.text)), [
          (BlockKind.paragraph, tag == 'br' ? 'Один\nдва' : 'Один два'),
          if (tag == 'hr' || tag == 'empty-line') (BlockKind.separator, ''),
          if (tag == 'img' || tag == 'image') (BlockKind.image, ''),
          (BlockKind.paragraph, 'Три.'),
          (BlockKind.paragraph, 'Четыре.'),
        ]);
        expect(chapters(b), [(fb2 ? '' : 'Глава', 1, 0, tag == 'br' ? 3 : 4)]);
        expect(b.notes, isEmpty);
      }
    });
  }

  for (final data in ['QUJDRA', 'QUJ!RA==']) {
    test(
      'BF03: invalid binary $data is absent, wrapped base64 remains valid',
      () {
        final r = checked(
          utf8.encode(
            fixture('fb2_bad_binary.xml').replaceAll('BAD_DATA', data),
          ),
        );
        expect(r.book.blocks.map((b) => (b.kind, b.text)), [
          (BlockKind.paragraph, 'Текст.'),
          (BlockKind.image, ''),
        ]);
        expect(r.book.blocks.last.imageId, 'good');
        expect(r.images.keys, ['good']);
        expect(r.images['good'], [65, 66, 67, 68]);
        expect(r.cover, isNull);
        expect(chapters(r.book), [('', 1, 0, 2)]);
        expect(r.notes, isEmpty);
      },
    );
  }

  test('BF04: chapter title joins paragraphs and omits only actual note references', () {
    final b = checked(utf8.encode(fixture('fb2_title_parts.xml'))).book;
    expect(chapters(b), [
      ('Глава первая Начало пути?', 1, 0, 3),
      ('Обычное название', 1, 3, 2),
    ]);
    expect(b.blocks.map((b) => b.text), [
      'Глава первая*',
      'Начало пути?',
      'Текст.',
      'Обычное название',
      'Конец.',
    ]);
    expect(b.blocks.take(2).map((b) => b.kind), [
      BlockKind.heading,
      BlockKind.heading,
    ]);
    expect(
      b.blocks.first.spans
          .where((s) => s.style == SpanStyle.noteRef)
          .single
          .noteId,
      'n',
    );
    expect(b.blocks[1].spans, isEmpty);
    expect(b.notes['n']!.blocks.single.text, 'Сноска.');
  });

  test('BF05: mimetype trims edges, not internal whitespace or wrong type', () {
    for (final mime in ['application/epub+zip', fixture('epub_mimetype.txt')]) {
      final bytes = epub(extra: {'mimetype': mime});
      expect(detectFormat(bytes), SourceFormat.epub);
      final b = checked(bytes).book;
      expect(b.blocks.map((b) => b.text), defaultEpubText);
      expect(chapters(b), [
        ('', 1, 0, 1),
        ('Первая', 1, 1, 1),
        ('Вложенная', 2, 2, 5),
      ]);
      expect(b.notes, isEmpty);
    }
    for (final mime in ['application/epub+ zip', 'application/zip']) {
      expect(
        () => detectFormat(epub(extra: {'mimetype': mime})),
        throwsA(
          isA<BookParseException>().having(
            (e) => e.reason,
            'reason',
            ParseFailure.unsupported,
          ),
        ),
      );
    }
  });

  test('BF06: only HTML block elements split mixed container text', () {
    final b = checked(
      epub(
        content: fixture('epub_inline_tags.xhtml'),
        nav: navTo('../text.xhtml'),
      ),
    ).book;
    expect(b.blocks.map((b) => b.text), [
      'Он очень хотел МАЛО и x, цитата…',
      'Пункт раз два.',
      'Ячейка раз два.',
      'До',
      'Внутри',
      'После',
      'Раздел',
      'Конец',
      'Жирный курсив x2 H2O',
    ]);
    expect(b.blocks.first.spans, isEmpty);
    expect(b.blocks.last.spans.map((s) => s.style), [
      SpanStyle.bold,
      SpanStyle.italic,
      SpanStyle.sup,
      SpanStyle.sub,
    ]);
    expect(chapters(b), [('Глава', 1, 0, 9)]);
    expect(b.notes, isEmpty);
  });

  test('BF07: empty TOC document cannot name next chapter, true duplicate keeps first', () {
    for (final coverHasText in [false, true]) {
      final b = checked(
        epub(
          content: fixture('epub_cover_only.xhtml'),
          nav: fixture('epub_empty_document_nav.xhtml'),
          spine: ['text', 'second', 'notes'],
          extra: {
            if (coverHasText)
              'OPS/text.xhtml': fixture('epub_cover_text.xhtml'),
            'OPS/second.xhtml': fixture('epub_chapter_one.xhtml'),
            'OPS/notes.xhtml': fixture('epub_chapter_two.xhtml'),
          },
        ),
      ).book;
      expect(b.blocks.map((b) => b.text), [
        if (coverHasText) 'Обложка с текстом.',
        'Один.',
        'Два.',
      ]);
      final offset = coverHasText ? 1 : 0;
      expect(chapters(b), [
        if (coverHasText) ('Обложка', 1, 0, 1),
        ('Глава 1', 1, offset, 1),
        ('Глава 2', 1, offset + 1, 1),
      ]);
      expect(b.notes, isEmpty);
    }
  });

  for (final ncx in [false, true]) {
    test('BF08: external TOC entries skipped in ${ncx ? 'NCX' : 'nav'}', () {
      final b = checked(
        epub(
          ncx: ncx,
          spine: const ['text'],
          nav: fixture(
            ncx ? 'epub_external_toc.ncx' : 'epub_external_nav.xhtml',
          ),
        ),
      ).book;
      expect(b.blocks.map((b) => b.text), defaultEpubText);
      expect(chapters(b), [('Местная', 1, 0, 7)]);
      expect(b.notes, isEmpty);
    });
  }

  test('BF09: Unicode and percent-encoded fragments find anchors, missing uses document start', () {
    for (final fragment in [
      'глава1',
      '%D0%B3%D0%BB%D0%B0%D0%B2%D0%B01',
      'absent',
    ]) {
      final b = checked(
        epub(
          content: fixture('epub_unicode_anchor.xhtml'),
          nav: navTo('../text.xhtml#$fragment'),
        ),
      ).book;
      expect(b.blocks.map((b) => b.text), ['До.', 'Начало.']);
      expect(
        chapters(b),
        fragment == 'absent'
            ? [('Глава', 1, 0, 2)]
            : [('', 1, 0, 1), ('Глава', 1, 1, 1)],
      );
      expect(b.notes, isEmpty);
    }
  });

  for (final encoding in ['windows-1250', 'windows-1252']) {
    test(
      'BF10: declared $encoding decodes European text, UTF-8 remains UTF-8',
      () {
        final source = fixture('fb2_$encoding.xml');
        final page = encoding == 'windows-1250'
            ? {
                0x17c: 0xbf,
                0xf3: 0xf3,
                0x142: 0xb3,
                0x107: 0xe6,
                0x119: 0xea,
                0x15b: 0x9c,
                0x105: 0xb9,
                0x17a: 0x9f,
                0x144: 0xf1,
              }
            : {
                0x20ac: 0x80,
                0x201e: 0x84,
                0x201c: 0x93,
                0xfc: 0xfc,
                0xdf: 0xdf,
                0xe4: 0xe4,
                0xf6: 0xf6,
              };
        for (final bytes in [
          source.runes.map((c) => page[c] ?? c).toList(),
          utf8.encode(source.replaceAll(encoding, 'UTF-8')),
        ]) {
          final b = checked(bytes).book;
          expect(
            b.blocks.single.text,
            encoding == 'windows-1250' ? 'Zażółć gęślą jaźń.' : '„Grüße“ € äö.',
          );
          expect(chapters(b), [('', 1, 0, 1)]);
          expect(b.notes, isEmpty);
        }
      },
    );
  }

  for (final type in ['footnote', 'endnote', 'rearnote']) {
    test(
      'BF11: unmarked link to $type is noteRef, ordinary target is text',
      () {
        final b = checked(
          epub(
            content: fixture('epub_unmarked_note.xhtml')
                .replaceAll('TYPE', type),
            nav: navTo('../text.xhtml'),
          ),
        ).book;
        expect(b.blocks.map((b) => b.text), ['Текст1234.', 'Обычный.']);
        expect(
          b.blocks.first.spans.map((s) => (s.start, s.end, s.style, s.noteId)),
          [
            (5, 6, SpanStyle.noteRef, 'OPS/text.xhtml#n'),
            (8, 9, SpanStyle.noteRef, 'OPS/notes.xhtml#r'),
          ],
        );
        expect(chapters(b), [('Глава', 1, 0, 2)]);
        expect(
          b.notes.map(
            (id, n) => MapEntry(id, n.blocks.map((b) => b.text).toList()),
          ),
          {
            'OPS/text.xhtml#n': ['Сноска.'],
            'OPS/notes.xhtml#n': ['Концевая.'],
            'OPS/notes.xhtml#r': ['Примечание.'],
          },
        );
      },
    );
  }

  for (final tag in ['p', 'pre']) {
    test(
      'BF12: whitespace after br disappears in $tag, ordinary spaces remain',
      () {
        final b = checked(
          epub(
            content: fixture('epub_br_space.xhtml').replaceAll('TAG', tag),
            nav: navTo('../text.xhtml'),
          ),
        ).book;
        expect(b.blocks.map((b) => b.text), [
          'Первая\nвторая\nтретья',
          'Первая вторая',
        ]);
        expect(b.blocks.first.spans.map((s) => (s.start, s.end, s.style)), [
          (7, 13, SpanStyle.italic),
        ]);
        expect(chapters(b), [('Глава', 1, 0, 2)]);
        expect(b.notes, isEmpty);
      },
    );
  }
}
