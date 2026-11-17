import 'package:audiobook_reader/book/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

const expectedText = [
  'До.',
  'Заголовок',
  'В контейнере.',
  'После якоря.',
  'Начало. Ещё.',
  'До середины.',
  'Последний.',
];
String singleNav(String href) =>
    fixture('epub_single_nav.xhtml').replaceAll('HREF', href);

void main() {
  test('FR-B4/B6: a missing note resource and a missing document are ordinary links', () {
    final b = checked(
      epub(
        content: fixture('epub_missing_note_resource.xhtml'),
        nav: singleNav('../text.xhtml'),
      ),
    ).book;
    expect(b.blocks.single.text, 'А123.');
    expect(b.blocks.single.spans, isEmpty);
    expect(chapters(b), [('Глава', 1, 0, 1)]);
    expect(b.notes, isEmpty);
  });
  test('FR-B4: pre keeps line breaks, an ordinary paragraph normalizes them', () {
    final b = checked(
      epub(content: fixture('epub_pre.xhtml'), nav: singleNav('../text.xhtml')),
    ).book;
    expect(b.blocks.map((b) => (b.kind, b.text)), [
      (BlockKind.verse, 'Первая строка\nВторая строка'),
      (BlockKind.paragraph, 'Первая строка Вторая строка'),
    ]);
    expect(chapters(b), [('Глава', 1, 0, 2)]);
    expect(b.notes, isEmpty);
  });
  test('FR-B4: a table row by row separates nested paragraphs; code and styles are not text', () {
    final b = checked(
      epub(
        content: fixture('epub_table.xhtml'),
        nav: singleNav('../text.xhtml'),
      ),
    ).book;
    expect(b.blocks.map((b) => b.text), [
      'Один Два Три',
      'Четыре Пять',
      'До после.',
    ]);
    expect(chapters(b), [('Глава', 1, 0, 3)]);
    expect(b.notes, isEmpty);
  });
  test('FR-B4: paragraphs inside a list are not merged, inline styling does not split the line', () {
    final b = checked(
      epub(
        content: fixture('epub_list.xhtml'),
        nav: singleNav('../text.xhtml'),
      ),
    ).book;
    expect(b.blocks.map((b) => b.text), ['Один.', 'Два.', 'Три слова.']);
    expect(b.blocks.last.spans.map((s) => (s.start, s.end, s.style)), [
      (4, 9, SpanStyle.italic),
    ]);
    expect(chapters(b), [('Глава', 1, 0, 3)]);
    expect(b.notes, isEmpty);
  });
  test(
    'FR-B4: styling is preserved on both sides of an inline image',
    () {
      final b = checked(
        epub(
          content: fixture('epub_inline_image.xhtml'),
          nav: singleNav('../text.xhtml'),
        ),
      ).book;
      expect(b.blocks.map((b) => (b.kind, b.text)), [
        (BlockKind.paragraph, 'А до'),
        (BlockKind.image, ''),
        (BlockKind.paragraph, 'после Б.'),
      ]);
      expect(b.blocks.first.spans.map((s) => (s.start, s.end, s.style)), [
        (2, 4, SpanStyle.italic),
      ]);
      expect(b.blocks.last.spans.map((s) => (s.start, s.end, s.style)), [
        (0, 5, SpanStyle.italic),
      ]);
      expect(chapters(b), [('Глава', 1, 0, 3)]);
      expect(b.notes, isEmpty);
    },
  );
  for (final ncx in [false, true]) {
    test(
      'FR-B4: EPUB ${ncx ? 2 : 3}, relative path from the table of contents, levels, metadata and cover',
      () {
        final r = checked(
          epub(ncx: ncx, cover3: !ncx, spine: ncx ? ['text'] : ['text', 'nav']),
        );
        final b = r.book;
        expect((b.title, b.author, b.language), ('Книга EPUB', 'Автор', 'pl'));
        expect(b.blocks.map((b) => b.text), expectedText);
        expect(chapters(b), [
          ('', 1, 0, 1),
          ('Первая', 1, 1, 1),
          ('Вложенная', 2, 2, 5),
        ]);
        expect(b.notes, isEmpty);
        expect(r.cover!.bytes, [1, 2, 3]);
        expect(r.cover!.mediaType, 'image/png');
      },
    );
  }
  final anchors = <String, int>{
    '': 0,
    '#heading': 1,
    '#container': 2,
    '#empty': 3,
    '#first': 4,
    '#middle': 6,
    '#missing': 0,
  };
  for (final e in anchors.entries) {
    test('FR-B4: boundary ${e.key.isEmpty ? 'without fragment' : e.key}', () {
      final b = checked(epub(nav: singleNav('../text.xhtml${e.key}'))).book;
      expect(b.blocks.map((b) => b.text), expectedText);
      expect(chapters(b), [
        if (e.value > 0) ('', 1, 0, e.value),
        ('Глава', 1, e.value, 7 - e.value),
      ]);
      expect(b.notes, isEmpty);
    });
  }
  test('FR-B4: duplicate boundaries keep the first entry, a different anchor gives a different chapter', () {
    final nav = singleNav('../text.xhtml#heading').replaceFirst(
      '</li></ol>',
      '</li><li><a href="../text.xhtml#heading">Дубликат</a></li><li><a href="../text.xhtml#container">Другая</a></li></ol>',
    );
    final b = checked(epub(nav: nav)).book;
    expect(b.blocks.map((b) => b.text), expectedText);
    expect(chapters(b), [
      ('', 1, 0, 1),
      ('Глава', 1, 1, 1),
      ('Другая', 1, 2, 5),
    ]);
    expect(b.notes, isEmpty);
  });
  test(
    'FR-B4: a spine document without an entry continues the chapter; an entry creates a boundary',
    () {
      final nav = singleNav('../text.xhtml');
      final continued = checked(epub(nav: nav, spine: ['text', 'second'])).book;
      expect(continued.blocks.map((b) => b.text), [
        ...expectedText,
        'Продолжение.',
      ]);
      expect(chapters(continued), [('Глава', 1, 0, 8)]);
      final split = checked(
        epub(
          nav: nav.replaceFirst(
            '</li></ol>',
            '</li><li><a href="../second.xhtml">Новая</a></li></ol>',
          ),
          spine: ['text', 'second'],
        ),
      ).book;
      expect(split.blocks.map((b) => b.text), [
        ...expectedText,
        'Продолжение.',
      ]);
      expect(chapters(split), [('Глава', 1, 0, 7), ('Новая', 1, 7, 1)]);
      expect(split.notes, isEmpty);
    },
  );
  test('FR-B4: spine order takes precedence over manifest and table-of-contents order', () {
    final b = checked(
      epub(nav: singleNav('../text.xhtml'), spine: ['second', 'text']),
    ).book;
    expect(b.blocks.map((b) => b.text), ['Продолжение.', ...expectedText]);
    expect(chapters(b), [('', 1, 0, 1), ('Глава', 1, 1, 7)]);
    expect(b.notes, isEmpty);
  });
  test('FR-B4: structural markers of notes, table of contents, caption and similar ordinary text', () {
    final r = checked(
      epub(
        content: fixture('epub_structures.xhtml'),
        nav: singleNav('../text.xhtml'),
      ),
    );
    final b = r.book;
    expect(b.blocks.map((b) => b.text), [
      'Заголовок',
      'Текст курсив жирный x2 H2O[1][2][3].',
      'Обычный aside.',
      'Обычный класс.',
      'Обычный nav.',
      'Подпись картинки.',
      'Обычный абзац.',
      'Цитата.',
      'Стих\nСтрока',
      '',
      'А Б',
      'В',
    ]);
    expect(b.blocks.map((b) => b.kind), [
      BlockKind.heading,
      BlockKind.paragraph,
      BlockKind.paragraph,
      BlockKind.paragraph,
      BlockKind.paragraph,
      BlockKind.image,
      BlockKind.paragraph,
      BlockKind.cite,
      BlockKind.verse,
      BlockKind.separator,
      BlockKind.paragraph,
      BlockKind.paragraph,
    ]);
    expect(chapters(b), [('Глава', 1, 0, 12)]);
    expect(b.notes.keys, ['OPS/text.xhtml#n']);
    expect(b.notes.values.single.blocks.map((b) => b.text), ['Сноска.']);
    final refs = b.blocks[1].spans
        .where((s) => s.style == SpanStyle.noteRef)
        .toList();
    expect(
      refs.map((s) => (b.blocks[1].text.substring(s.start, s.end), s.noteId)),
      [('[1]', 'OPS/text.xhtml#n'), ('[3]', 'OPS/text.xhtml#n')],
    );
    expect(b.blocks[5].spans.map((s) => (s.start, s.end, s.style)), [
      (8, 16, SpanStyle.italic),
    ]);
    expect(b.blocks[5].imageId, 'OPS/pic.png');
    expect(r.images['OPS/pic.png'], [1, 2, 3]);
  });
  for (final type in ['footnote', 'endnote', 'rearnote']) {
    test(
      'FR-B4: type $type on aside and on another element; without a type it is main text',
      () {
        for (final tag in ['aside', 'div']) {
          final content = fixture('epub_note_type.xhtml')
              .replaceAll('TAG', tag)
              .replaceAll('TYPE', type);
          final b = checked(
            epub(content: content, nav: singleNav('../text.xhtml')),
          ).book;
          expect(b.blocks.map((b) => b.text), ['Текст*.', 'Обычный.']);
          expect(chapters(b), [('Глава', 1, 0, 2)]);
          expect(b.notes.values.single.blocks.map((b) => b.text), ['Сноска.']);
          expect(b.blocks.first.spans.single.noteId, 'OPS/text.xhtml#n');
        }
      },
    );
  }
  test('FR-B4: noteId includes the document, notes outside the spine are available, an empty link is ordinary', () {
    final source = fixture('epub_note_documents.xhtml');
    final b = checked(epub(content: source, nav: singleNav('../text.xhtml')))
        .book;
    expect(b.blocks.map((b) => b.text), ['А1234.']);
    expect(chapters(b), [('Глава', 1, 0, 1)]);
    expect(
      b.notes.map(
        (id, note) => MapEntry(id, note.blocks.map((b) => b.text).toList()),
      ),
      {
        'OPS/text.xhtml#n': ['Местная.'],
        'OPS/notes.xhtml#n': ['Концевая.'],
        'OPS/notes.xhtml#r': ['Примечание.'],
      },
    );
    expect(b.blocks.single.spans.map((s) => s.noteId), [
      'OPS/text.xhtml#n',
      'OPS/notes.xhtml#n',
      'OPS/notes.xhtml#r',
    ]);
  });
  test('FR-B4: figcaption gives a caption, class caption stays a paragraph', () {
    final source = fixture('epub_plain_caption.xhtml');
    final b = checked(epub(content: source, nav: singleNav('../text.xhtml')))
        .book;
    expect(b.blocks.map((b) => (b.kind, b.text)), [
      (BlockKind.image, ''),
      (BlockKind.paragraph, 'Обычная.'),
      (BlockKind.paragraph, 'Текст.'),
    ]);
    expect(chapters(b), [('Глава', 1, 0, 3)]);
    expect(b.notes, isEmpty);
  });
  test('FR-B4: images inside a figure container keep the order and all the images', () {
    final b = checked(
      epub(
        content: fixture('epub_mixed_figure.xhtml'),
        nav: singleNav('../text.xhtml'),
      ),
    ).book;
    expect(b.blocks.map((b) => (b.kind, b.text)), [
      (BlockKind.paragraph, 'До.'),
      (BlockKind.image, 'Подпись.'),
      (BlockKind.image, ''),
      (BlockKind.paragraph, 'После.'),
    ]);
    expect(chapters(b), [('Глава', 1, 0, 4)]);
    expect(b.notes, isEmpty);
  });
}
