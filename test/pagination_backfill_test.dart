import 'dart:async';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/reader/page_style.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pagination_test.dart' show awkwardBook, checkRenderedHeights, column, imageSizes, styleFor;
import 'reader_position_navigation_test.dart' show chaptersBook, pieces;
import 'support/pagination.dart';

int insideLine(Book book, PageStyle style, Size col, int block, int offset) {
  final tp = piecePainter(style, book.blocks[block], 0, book.blocks[block].text.length, width: col.width);
  final start = tp.getLineBoundary(TextPosition(offset: offset)).start - (hasIndent(book.blocks[block], 0) ? 1 : 0);
  tp.dispose();
  return start;
}

void full(BookPageLayout page, PageStyle style, Size col) {
  final last = page.fragments.last;
  expect(last.top + last.height, lessThanOrEqualTo(col.height + 0.5));
  expect(last.top + last.height + style.lineHeight, greaterThan(col.height));
}

void main() {
  for (final narrow in [false, true]) {
    test('backward pages are full, overlap only at the chapter start; narrow screen $narrow', () async {
      final book = chaptersBook();
      final style = styleFor(narrow ? 5 : 2, narrow ? 1.3 : 1);
      final col = column(narrow ? const Size(320, 640) : const Size(360, 800));
      final reference = await paginate(book: book, style: style, column: col);
      addTearDown(reference.dispose);
      final offset = insideLine(book, style, col, 1, 2350);
      final layout = await paginate(book: book, style: style, column: col, block: 1, offset: offset);
      addTearDown(layout.dispose);
      final suffix = layout.pages.toList();
      final count = await layout.loadPrevious();
      expect(count, greaterThan(1));
      expect(layout.pages.skip(count), orderedEquals(suffix));
      expect(layout.pages[count - 1].lastEnd, offset);
      final first = layout.pages.first;
      expect(pieces(first), pieces(reference.pages[reference.chapterFirstPage[1]]));
      for (var i = 0; i < count; i++) {
        full(layout.pages[i], style, col);
        if (i > 1) expect(layout.pages[i - 1].lastEnd, layout.pages[i].firstOffset);
      }
      final second = layout.pages[1];
      expect(first.lastEnd, greaterThan(second.firstOffset),
          reason: 'the shortage of lines at the start is replaced by overlap');
      final overlap = second.firstOffset;
      expect(layout.findPage(1, overlap), 1);
      expect(layout.findPage(1, overlap, preferredPage: 0), 0);
      expect(layout.findPage(1, first.lastEnd + 1, preferredPage: 0), layout.findPage(1, first.lastEnd + 1));
      final previousCount = await layout.loadPrevious();
      final previous = reference.pages.where((p) => p.chapter == 0).toList();
      expect(previousCount, previous.length);
      for (var i = 0; i < previousCount; i++) {
        expect(pieces(layout.pages[i]), pieces(previous[i]), reason: 'the previous chapter has an ordinary end');
      }
      expect(layout.hasPrevious, isFalse);
      expect(layout.pages.skip(previousCount + count), orderedEquals(suffix));
    });

    testWidgets('backward across heading, image, caption, verse and long paragraph; narrow screen $narrow',
        (tester) async {
      final book = awkwardBook();
      final style = styleFor(narrow ? 5 : 2, narrow ? 1.3 : 1);
      final col = column(narrow ? const Size(320, 640) : const Size(360, 800));
      final offset = insideLine(book, style, col, 6, 800);
      final layout = await paginate(tester: tester, book: book, style: style, column: col,
          block: 6, offset: offset, imageSizes: imageSizes);
      addTearDown(layout.dispose);
      final original = layout.pages.first;
      final previous = layout.loadPrevious();
      for (var i = 0; layout.isLoadingPrevious && i < 10000; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(layout.isLoadingPrevious, isFalse);
      await previous;
      expect(layout.pages, contains(same(original)));
      final before = layout.pages.takeWhile((p) => !identical(p, original)).toList();
      expect(before.expand((p) => p.fragments).map((f) => book.blocks[f.block].kind).toSet(),
          containsAll([BlockKind.heading, BlockKind.image, BlockKind.verse, BlockKind.cite, BlockKind.separator]));
      final image = before.singleWhere((p) => p.fragments.any((f) => f.isImage));
      expect(image.fragments.any((f) => f.block == 2 && !f.isImage && f.start == 0), isTrue);
      for (final page in before) {
        for (final f in page.fragments) {
          expect(f.top, greaterThanOrEqualTo(0));
          expect(f.top + f.height, lessThanOrEqualTo(col.height + 0.5));
        }
      }
      expect(await checkRenderedHeights(tester, book, layout, style, col,
          List.generate(before.length, (i) => i)), greaterThan(10));
    });
  }

  testWidgets('a small heading moves whole and with the same insets', (tester) async {
    final source = awkwardBook();
    final book = Book(id: 'short-heading-back', title: '', author: '', language: 'ru', chapters: source.chapters,
        blocks: [const Block(index: 0, kind: BlockKind.heading, text: 'Глава\nПодзаголовок'),
          ...source.blocks.skip(1)], notes: const {});
    final style = styleFor(2, 1);
    final col = column(const Size(360, 800));
    final offset = insideLine(book, style, col, 6, 800);
    final layout = await paginate(tester: tester, book: book, style: style, column: col,
        block: 6, offset: offset, imageSizes: imageSizes);
    addTearDown(layout.dispose);
    await tester.runAsync(layout.loadPrevious);
    final headings = layout.pages.expand((p) => p.fragments).where((f) => f.block == 0).toList();
    // Repetition is allowed at the first boundary; every appearance of the heading contains the whole heading.
    expect(headings, isNotEmpty);
    expect(headings.every((f) => f.start == 0 && f.end == book.blocks[0].text.length), isTrue);
    expect(await checkRenderedHeights(tester, book, layout, style, col, [0, 1]), greaterThan(1));
  });

  for (final text in ['ОченьДлинноеСловоБезПробелов', '😀абв😀гдеж😀зик😀лмн']) {
    testWidgets('backward lines match the rendering inside a long word $text', (tester) async {
      final book = Book(id: 'word-back', title: '', author: '', language: 'ru',
          chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 1)],
          blocks: [Block(index: 0, kind: BlockKind.paragraph, text: text * 200)], notes: const {});
      final style = styleFor(2, 1);
      const col = Size(272, 500);
      final offset = insideLine(book, style, col, 0, 2300);
      final layout = await paginate(tester: tester, book: book, style: style, column: col, offset: offset);
      addTearDown(layout.dispose);
      await tester.runAsync(layout.loadPrevious);
      expect(await checkRenderedHeights(tester, book, layout, style, col,
          List.generate(layout.prependedCount, (i) => i)), greaterThan(1));
      for (final page in layout.pages.take(layout.prependedCount)) {
        full(page, style, col);
      }
    });
  }

  testWidgets('a long prefix is measured in windows between frames and cancelled without insertion', (tester) async {
    final book = Book(id: 'back-budget', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 1)],
        blocks: [Block(index: 0, kind: BlockKind.paragraph, text: 'Текст тут. ' * 30000)], notes: const {});
    final layout = ChapterPagination();
    addTearDown(layout.dispose);
    final measurements = <(int, int)>[];
    debugPageMeasurement = (_, a, z) => measurements.add((a, z));
    addTearDown(() => debugPageMeasurement = null);
    layout.start(book: book, style: styleFor(2, 1), column: const Size(272, 500), block: 0, offset: 234000);
    layout.pause();
    final original = layout.pages.single;
    measurements.clear();
    final previous = layout.loadPrevious();
    expect(measurements, isEmpty, reason: 'the command does not measure the whole prefix synchronously');
    var heartbeat = false;
    Timer.run(() => heartbeat = true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(heartbeat, isTrue);
    expect(measurements, isNotEmpty);
    expect(measurements.every((m) => m.$2 - m.$1 <= 4096), isTrue);
    expect(measurements.fold(0, (sum, m) => sum + m.$2 - m.$1), lessThan(32768));
    expect(layout.isLoadingPrevious, isTrue);
    expect(layout.pages, [same(original)]);
    layout.cancelPrevious();
    final count = measurements.length;
    await tester.pump(const Duration(milliseconds: 50));
    expect(await previous, 0);
    expect(measurements.length, count);
    expect(layout.pages, [same(original)]);
  });
}
