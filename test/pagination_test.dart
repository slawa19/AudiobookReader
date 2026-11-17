import 'dart:convert';

import 'package:audiobook_reader/app/theme.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/reader/page_style.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/pagination.dart';

Future<Book> loadBook(String name) async {
  final data = await rootBundle.load('assets/demo/$name.json');
  return Book.fromJson(jsonDecode(utf8.decode(data.buffer.asUint8List())) as Map<String, Object?>);
}

/// The text column as the reading screen computes it: margins 24, status bar 32 + 28 on top,
/// gesture strip 20 + 44 at the bottom.
Size column(Size screen) => Size(screen.width - 48, screen.height - (32 + 28) - (20 + 44));

const imageSizes = {'steppe': Size(960, 600)};

PageStyle styleFor(int step, double scale) =>
    PageStyle(fontSize: fontSteps[step].size, lineHeight: fontSteps[step].lineHeight, textScaler: TextScaler.linear(scale));

/// A synthetic book with awkward blocks: a heading longer than a page, an image with a caption longer than a page,
/// verse, a quote, a separator. The pagination rules are general — the book does not copy any real one.
Book awkwardBook() {
  final longTitle = List.filled(40, 'Очень длинное название раздела').join(' ');
  final longCaption = List.filled(60, 'длинная подпись к картинке').join(' ');
  final para = List.filled(30, 'Обычный абзац текста для заполнения страницы.').join(' ');
  final blocks = [
    Block(index: 0, kind: BlockKind.heading, text: 'Глава\n$longTitle'),
    Block(index: 1, kind: BlockKind.paragraph, text: para),
    Block(index: 2, kind: BlockKind.image, text: longCaption, imageId: 'steppe'),
    Block(index: 3, kind: BlockKind.verse, text: 'Первая строка стиха,\nвторая строка стиха,\nтретья строка.'),
    const Block(index: 4, kind: BlockKind.cite, text: 'Цитата прямым начертанием.'),
    const Block(index: 5, kind: BlockKind.separator, text: ''),
    Block(index: 6, kind: BlockKind.paragraph, text: para),
  ];
  return Book(
    id: 'awkward',
    title: 'Неудобная книга',
    author: 'Тест',
    language: 'ru',
    chapters: const [
      Chapter(title: 'Пустой раздел', level: 1, firstBlock: 0, blockCount: 0),
      Chapter(title: 'Глава', level: 1, firstBlock: 0, blockCount: 7),
    ],
    blocks: blocks,
    notes: const {},
  );
}

void checkCoverage(Book book, ChapterPagination layout, Size col) {
  final covered = <int, List<(int, int)>>{};
  for (final page in layout.pages) {
    expect(page.fragments, isNotEmpty);
    for (final f in page.fragments) {
      expect(f.top + f.height, lessThanOrEqualTo(col.height + 0.5),
          reason: '${book.id}: a piece of block ${f.block} extends below the page bottom');
      if (!f.isImage && book.blocks[f.block].text.isNotEmpty) {
        expect(f.end, greaterThan(f.start), reason: '${book.id}: empty piece of block ${f.block}');
      }
      covered.putIfAbsent(f.block, () => []).add((f.start, f.end));
    }
  }
  for (final b in book.blocks) {
    final parts = covered[b.index];
    expect(parts, isNotNull, reason: '${book.id}: block ${b.index} did not land on any page');
    var at = 0;
    for (final (s, e) in parts!) {
      expect(s, at, reason: '${book.id}: block ${b.index} has skipped or repeated text');
      at = e;
    }
    expect(at, b.text.length);
  }
  for (var c = 0; c < book.chapters.length; c++) {
    expect(layout.pages[layout.chapterFirstPage[c]].firstBlock, book.chapters[c].firstBlock);
  }
}

const colors = PageColors(
  ink: Color(0xFF000000),
  ink2: Color(0xFF555555),
  accent: Color(0xFFAA0000),
  highlight: Color(0xFFEEEEEE),
  rule: Color(0xFFCCCCCC),
);

/// Draws the pages in the Material theme and compares the height of every text piece (paragraph, verse, quote,
/// heading, caption) with the computed one. Returns the number of pieces checked.
Future<int> checkRenderedHeights(WidgetTester tester, Book book, ChapterPagination layout, PageStyle style, Size col,
    Iterable<int> pages) async {
  var checked = 0;
  for (final i in pages) {
    final page = layout.pages[i];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(lightPalette),
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: col,
            child: BookPage(
              book: book,
              page: page,
              style: style,
              colors: colors,
              imageFor: (_) => const AssetImage('assets/demo/images/steppe.png'),
            ),
          ),
        ),
      ),
    ));
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(find.descendant(of: find.byType(BookPage), matching: find.byType(RichText)))
        .toList();
    var r = 0;
    for (final f in page.fragments) {
      if (f.isImage) continue;
      final rendered = paragraphs[r++];
      if (book.blocks[f.block].kind == BlockKind.separator) continue;
      expect(rendered.size.height, moreOrLessEquals(f.height, epsilon: 0.5),
          reason: 'page $i, block ${f.block}: lines wrapped differently from what pagination computed');
      checked++;
    }
  }
  return checked;
}

void main() {
  late Book kapitanskaya;
  late Book dama;

  setUpAll(() async {
    kapitanskaya = await loadBook('kapitanskaya');
    dama = await loadBook('dama');
  });

  final cases = <(String, Size, int, double)>[
    ('412×915, step 3', const Size(412, 915), 2, 1.0),
    ('320×640 ×1.3, step 6', const Size(320, 640), 5, 1.3),
    ('360×800, step 1', const Size(360, 800), 0, 1.0),
  ];

  for (final (label, screen, step, scale) in cases) {
    test('pagination covers all the text without gaps and does not split lines: $label', () async {
      for (final book in [kapitanskaya, dama, awkwardBook()]) {
        final col = column(screen);
        final layout = await paginate(book: book, style: styleFor(step, scale), column: col, imageSizes: imageSizes);
        checkCoverage(book, layout, col);
      }
    });
  }

  test('a page is found by its place in the book', () async {
    final style = styleFor(2, 1);
    final layout = await paginate(book: kapitanskaya, style: style, column: column(const Size(412, 915)), imageSizes: imageSizes);
    for (var i = 0; i < layout.pages.length; i++) {
      final p = layout.pages[i];
      expect(layout.pageOf(p.firstBlock, p.firstOffset), i);
      if (p.lastEnd > 0) expect(layout.pageOf(p.lastBlock, p.lastEnd - 1), i);
      expect(p.contains(p.firstBlock, p.firstOffset), isTrue);
    }
  });

  testWidgets('a rendered piece takes exactly the computed height — in the Material theme', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final style = styleFor(2, 1);
    final col = column(const Size(412, 915));
    final layout = await paginate(tester: tester, book: kapitanskaya, style: style, column: col, imageSizes: imageSizes);
    // The first pages of three chapters and their neighbours: headings, verse, quotes, captions, footnotes, an image.
    final pages = {
      for (final first in layout.chapterFirstPage) ...[first, first + 1, first + 2],
      layout.pageOf(43, 0),
    };
    expect(await checkRenderedHeights(tester, kapitanskaya, layout, style, col, pages), greaterThan(20));
  });

  testWidgets('№6: a long heading and a long caption split by lines and do not overflow the page', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final book = awkwardBook();
    final style = styleFor(5, 1.3);
    final col = column(const Size(320, 640));
    final layout = await paginate(tester: tester, book: book, style: style, column: col, imageSizes: imageSizes);
    checkCoverage(book, layout, col);
    final headingPages = layout.pages.where((p) => p.fragments.any((f) => f.block == 0)).length;
    final captionPages = layout.pages.where((p) => p.fragments.any((f) => f.block == 2 && !f.isImage)).length;
    expect(headingPages, greaterThan(1), reason: 'a heading longer than a page is split');
    expect(captionPages, greaterThan(1), reason: 'a caption longer than a page continues on the following ones');
    final imagePage = layout.pages.firstWhere((p) => p.fragments.any((f) => f.block == 2 && f.isImage));
    expect(imagePage.fragments.any((f) => f.block == 2 && !f.isImage), isTrue,
        reason: 'the first caption line is on the image page');
    final checked = await checkRenderedHeights(tester, book, layout, style, col, List.generate(layout.pages.length, (i) => i));
    expect(checked, greaterThan(5));
  });

  test('№7: an empty section does not become a chapter, an empty book is not created', () async {
    final book = awkwardBook();
    expect(book.chapters.map((c) => c.title), ['Глава']);
    final layout = await paginate(book: book, style: styleFor(2, 1), column: column(const Size(412, 915)));
    expect(layout.chapterFirstPage, hasLength(book.chapters.length));
    expect(
      () => Book(id: 'x', title: 'x', author: 'x', language: 'ru', chapters: const [], blocks: const [], notes: const {}),
      throwsA(isA<EmptyBookException>()),
    );
    // A similar input where the rule stays silent: a chapter with blocks stays.
    final one = Book(
      id: 'y',
      title: 'y',
      author: 'y',
      language: 'ru',
      chapters: const [Chapter(title: 'Одна', level: 1, firstBlock: 0, blockCount: 1)],
      blocks: const [Block(index: 0, kind: BlockKind.paragraph, text: 'Текст.')],
      notes: const {},
    );
    expect(one.chapters, hasLength(1));
  });

  testWidgets('№21: a quote is upright with a line on the left; verse is italic without a line', (tester) async {
    final style = styleFor(2, 1);
    expect(style.cite.fontStyle, isNot(FontStyle.italic));
    expect(style.verse.fontStyle, FontStyle.italic);
    final book = awkwardBook();
    final col = column(const Size(412, 915));
    final layout = await paginate(tester: tester, book: book, style: style, column: col, imageSizes: imageSizes);
    final page = layout.pages.indexWhere((p) => p.fragments.any((f) => f.block == 4));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.fromSize(
        size: col,
        child: BookPage(book: book, page: layout.pages[page], style: style, colors: colors, imageFor: (_) => const AssetImage('x')),
      ),
    ));
    expect(find.byKey(const ValueKey('rule-4-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-3-0')), findsNothing);
  });

  testWidgets('the height check is sensitive: the same page at a different width gives different heights',
      (tester) async {
    final style = styleFor(2, 1);
    final col = column(const Size(412, 915));
    final layout = await paginate(tester: tester, book: kapitanskaya, style: style, column: col, imageSizes: imageSizes);
    final page = layout.pages[1];
    var differs = 0;
    for (final f in page.fragments) {
      final b = kapitanskaya.blocks[f.block];
      if (b.kind != BlockKind.paragraph) continue;
      final tp = piecePainter(style, b, f.start, f.end, width: col.width - 12);
      if ((tp.height - f.height).abs() > 0.5) differs++;
      tp.dispose();
    }
    expect(differs, greaterThan(0));
  });
}
