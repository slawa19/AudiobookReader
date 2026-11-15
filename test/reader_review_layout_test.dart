import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/reader/page_style.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pagination_test.dart' show colors;
import 'support/pagination.dart';

Book paragraphs(List<String> texts, {bool chapters = false}) => Book(id: 'review', title: 'Тест', author: '', language: 'ru',
    chapters: chapters
        ? [for (var i = 0; i < texts.length; i++) Chapter(title: '$i', level: 1, firstBlock: i, blockCount: 1)]
        : [Chapter(title: '', level: 1, firstBlock: 0, blockCount: texts.length)],
    blocks: [for (var i = 0; i < texts.length; i++) Block(index: i, kind: BlockKind.paragraph, text: texts[i])],
    notes: const {});

Future<void> heights(WidgetTester tester, Book book, ChapterPagination layout, PageStyle style,
    {bool bold = false}) async {
  for (final page in layout.pages) {
    await tester.pumpWidget(MediaQuery(data: MediaQueryData(boldText: bold), child: Directionality(
        textDirection: TextDirection.ltr, child: Align(alignment: Alignment.topLeft,
            child: SizedBox(width: 272, height: 500, child: BookPage(book: book, page: page, style: style,
                colors: colors, imageFor: (_) => const AssetImage('unused')))))));
    final rendered = tester.renderObjectList<RenderParagraph>(
        find.descendant(of: find.byType(BookPage), matching: find.byType(RichText))).toList();
    expect(rendered, hasLength(page.fragments.length));
    for (var i = 0; i < rendered.length; i++) {
      expect(rendered[i].size.height, moreOrLessEquals(page.fragments[i].height, epsilon: 0.1),
          reason: 'кусок ${page.fragments[i].start}–${page.fragments[i].end}, bold=$bold');
    }
  }
}

void main() {
  testWidgets('а: системный жирный шрифт не расходится с измеренными высотами', (tester) async {
    final book = paragraphs([List.filled(40, 'Это проверка системного жирного текста и высоты страницы. ').join(), 'Конец.']);
    final style = PageStyle(fontSize: 16, lineHeight: 27, textScaler: TextScaler.noScaling);
    final layout = await paginate(tester: tester, book: book, style: style, column: const Size(272, 500));
    await heights(tester, book, layout, style, bold: true);
    await heights(tester, book, layout, style);
  });

  testWidgets('б: длинное слово на границе страницы рисуется с посчитанной высотой', (tester) async {
    final style = PageStyle(fontSize: 28.6, lineHeight: 48, textScaler: TextScaler.noScaling);
    final book = paragraphs(['${List.filled(3, 'Тут текст. ').join()}${List.filled(20, 'человеконенавистничество ').join()}']);
    final layout = await paginate(tester: tester, book: book, style: style, column: const Size(272, 500));
    expect(layout.pages.length, greaterThan(1));
    await heights(tester, book, layout, style);
    final plain = paragraphs([List.filled(200, 'Тут текст. ').join()]);
    final normal = await paginate(tester: tester, book: plain, style: style, column: const Size(272, 500));
    final whole = piecePainter(style, plain.blocks.single, 0, plain.blocks.single.text.length, width: 272);
    final oldBoundary = whole.getPositionForOffset(const Offset(0.5, 504)).offset - 1;
    expect(normal.pages.first.lastEnd, oldBoundary,
        reason: 'обычная строка на прежней границе: десять строк полного TextPainter, без подгонки по слову');
    expect(normal.pages.first.fragments.single.height, 480);
    whole.dispose();
    await heights(tester, plain, normal, style);
  });

  test('в: конец блока переходит дальше, конец книги открывает непустую последнюю страницу', () {
    final book = paragraphs(['Первый.', 'Второй.'], chapters: true);
    final style = PageStyle(fontSize: 16, lineHeight: 27, textScaler: TextScaler.noScaling);
    final layout = ChapterPagination();
    addTearDown(layout.dispose);
    layout.start(book: book, style: style, column: const Size(272, 500), block: 0,
        offset: book.blocks[0].text.length, throughBook: true);
    expect(layout.pages, isNotEmpty);
    expect(layout.pages.first.firstBlock, 1);
    layout.start(book: book, style: style, column: const Size(272, 500), block: 1,
        offset: book.blocks[1].text.length, throughBook: true);
    expect(layout.pages, isNotEmpty);
    expect(layout.pages.first.lastEnd, book.blocks[1].text.length);
    layout.start(book: book, style: style, column: const Size(272, 500), block: 0,
        offset: book.blocks[0].text.length - 1, throughBook: true);
    expect(layout.pages.first.contains(0, book.blocks[0].text.length - 1), isTrue);
    layout.cancel();
  });
}
