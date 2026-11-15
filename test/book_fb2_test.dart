import 'dart:convert';

import 'package:audiobook_reader/book/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

void main() {
  test('FR-B3: несколько авторов и nickname, отсутствующие метаданные не выдумываются', () {
    final result = checked(utf8.encode(fixture('fb2_metadata.xml')));
    final b = result.book;
    expect(
      (b.title, b.author, b.language),
      ('Краткая', 'Псевдоним, Иван Тестов', 'en'),
    );
    expect(b.blocks.single.text, 'Один.');
    expect(chapters(b), [('', 1, 0, 1)]);
    expect(b.notes, isEmpty);
    expect(result.cover, isNull);
    final absent = checked(utf8.encode(fixture('fb2_plain.xml')));
    expect(
      (absent.book.title, absent.book.author, absent.book.language),
      ('', '', ''),
    );
    expect(absent.cover, isNull);
  });
  test(
    'FR-B3: метаданные, линейные вложенные главы, все блоки, обложка и binary',
    () {
      final result = checked(utf8.encode(fixture('fb2_structure.xml')));
      final b = result.book;
      expect(
        (b.title, b.author, b.language),
        ('Малая книга', 'Анна Ивановна Тестова', 'ru'),
      );
      expect(b.blocks.map((b) => b.text), [
        'До раздела.',
        'Часть',
        'Эпиграф.',
        'Автор.',
        'Вступление.',
        'Первая',
        'Текст.',
        'Строка один.',
        'Строка два.',
        'Цитата.',
        '',
        '',
        'А Б',
        'В',
        'Вторая',
        'Конец.',
        'Послесловие части.',
      ]);
      expect(b.blocks.map((b) => b.kind), [
        BlockKind.paragraph,
        BlockKind.heading,
        BlockKind.cite,
        BlockKind.cite,
        BlockKind.paragraph,
        BlockKind.heading,
        BlockKind.paragraph,
        BlockKind.verse,
        BlockKind.verse,
        BlockKind.cite,
        BlockKind.separator,
        BlockKind.image,
        BlockKind.paragraph,
        BlockKind.paragraph,
        BlockKind.heading,
        BlockKind.paragraph,
        BlockKind.paragraph,
      ]);
      expect(chapters(b), [
        ('', 1, 0, 1),
        ('Часть', 1, 1, 4),
        ('Первая', 2, 5, 9),
        ('Вторая', 2, 14, 2),
        ('Часть', 1, 16, 1),
      ]);
      expect(b.notes, isEmpty);
      expect(result.cover!.mediaType, 'image/png');
      expect(result.cover!.bytes, [1, 2, 3]);
      expect(result.images['pic'], [4, 5, 6]);
      expect(b.blocks[11].imageId, 'pic');
    },
  );
  test('FR-B3: без структуры нет заголовков, стихов, цитат и разделителей', () {
    final b = checked(utf8.encode(fixture('fb2_plain.xml'))).book;
    expect(b.blocks.map((b) => (b.kind, b.text)), [
      (BlockKind.paragraph, 'Заголовок'),
      (BlockKind.paragraph, 'Строка.'),
      (BlockKind.paragraph, 'Цитата.'),
      (BlockKind.paragraph, '***'),
    ]);
    expect(chapters(b), [('', 1, 0, 4)]);
    expect(b.notes, isEmpty);
  });
  test(
    'FR-B3: пустой родитель не даёт главы, соседние секции сохраняют названия',
    () {
      final b = checked(utf8.encode(fixture('fb2_sections.xml'))).book;
      expect(b.blocks.map((b) => b.text), ['А', 'Один.', 'Б', 'Два.']);
      expect(chapters(b), [('А', 2, 0, 2), ('Б', 2, 2, 2)]);
      expect(b.notes, isEmpty);
    },
  );
  test(
    'FR-B3/B6: диапазоны начертаний, сноска и два похожих обычных якоря',
    () {
      final b = checked(utf8.encode(fixture('fb2_inline.xml'))).book;
      expect(b.blocks.single.text, '😀 тихо громко x2 H2O[1][2][3][4].');
      expect(chapters(b), [('', 1, 0, 1)]);
      expect(
        b.blocks.single.spans.map((s) => (s.start, s.end, s.style, s.noteId)),
        [
          (8, 14, SpanStyle.bold, null),
          (3, 14, SpanStyle.italic, null),
          (16, 17, SpanStyle.sup, null),
          (19, 20, SpanStyle.sub, null),
          (21, 24, SpanStyle.noteRef, 'n'),
          (27, 30, SpanStyle.noteRef, 'n'),
        ],
      );
      expect(b.notes.keys, ['n']);
      expect(b.notes['n']!.blocks.map((b) => b.text), ['Сноска один.']);
      expect(
        b.notes['n']!.blocks.single.spans.map((s) => (s.start, s.end, s.style)),
        [(7, 11, SpanStyle.italic)],
      );
    },
  );
  test('FR-B3: body без имени notes остаётся основным текстом', () {
    final b = checked(utf8.encode(fixture('fb2_other_body.xml'))).book;
    expect(b.blocks.map((b) => b.text), ['Не сноска.']);
    expect(b.notes, isEmpty);
    expect(chapters(b), [('', 1, 0, 1)]);
  });
}
