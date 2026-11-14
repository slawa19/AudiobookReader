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

Future<Book> loadBook(String name) async {
  final data = await rootBundle.load('assets/demo/$name.json');
  return Book.fromJson(jsonDecode(utf8.decode(data.buffer.asUint8List())) as Map<String, Object?>);
}

/// Колонка текста так же, как её считает экран чтения: поля 24, сверху строка состояния 32 + 28,
/// снизу полоска жестов 20 + 44.
Size column(Size screen) => Size(screen.width - 48, screen.height - (32 + 28) - (20 + 44));

const imageSizes = {'steppe': Size(960, 600)};

void main() {
  late Book kapitanskaya;
  late Book dama;

  setUpAll(() async {
    kapitanskaya = await loadBook('kapitanskaya');
    dama = await loadBook('dama');
  });

  final cases = <(String, Size, int, double)>[
    ('412×915, ступень 3', const Size(412, 915), 2, 1.0),
    ('320×640 ×1,3, ступень 6', const Size(320, 640), 5, 1.3),
    ('360×800, ступень 1', const Size(360, 800), 0, 1.0),
  ];

  for (final (label, screen, step, scale) in cases) {
    test('разбивка покрывает весь текст без пропусков и не режет строки: $label', () {
      for (final book in [kapitanskaya, dama]) {
        final style = PageStyle(
            fontSize: fontSteps[step].size, lineHeight: fontSteps[step].lineHeight, textScaler: TextScaler.linear(scale));
        final col = column(screen);
        final layout = BookLayout.compute(book: book, style: style, column: col, imageSizes: imageSizes);

        final covered = <int, List<(int, int)>>{};
        for (final page in layout.pages) {
          expect(page.fragments, isNotEmpty);
          for (final f in page.fragments) {
            expect(f.top + f.height, lessThanOrEqualTo(col.height + 0.5),
                reason: '${book.id}: кусок блока ${f.block} вылезает за низ страницы');
            covered.putIfAbsent(f.block, () => []).add((f.start, f.end));
          }
        }
        for (final b in book.blocks) {
          final parts = covered[b.index];
          expect(parts, isNotNull, reason: '${book.id}: блок ${b.index} не попал ни на одну страницу');
          var at = 0;
          for (final (s, e) in parts!) {
            expect(s, at, reason: '${book.id}: в блоке ${b.index} пропуск или повтор текста');
            at = e;
          }
          expect(at, b.text.length);
        }
        // Каждая глава начинается с новой страницы.
        for (var c = 0; c < book.chapters.length; c++) {
          expect(layout.pages[layout.chapterFirstPage[c]].firstBlock, book.chapters[c].firstBlock);
        }
      }
    });
  }

  test('страница находится по месту в книге', () {
    final style = PageStyle(fontSize: 16, lineHeight: 27, textScaler: TextScaler.noScaling);
    final layout = BookLayout.compute(book: kapitanskaya, style: style, column: column(const Size(412, 915)), imageSizes: imageSizes);
    for (var i = 0; i < layout.pages.length; i++) {
      final p = layout.pages[i];
      expect(layout.pageOf(p.firstBlock, p.firstOffset), i);
      expect(layout.pageOf(p.lastBlock, p.lastEnd - 1), i);
    }
  });

  testWidgets('отрисованный кусок занимает ровно посчитанную высоту — в теме Material', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final style = PageStyle(fontSize: 16, lineHeight: 27, textScaler: TextScaler.noScaling);
    final col = column(const Size(412, 915));
    final layout = BookLayout.compute(book: kapitanskaya, style: style, column: col, imageSizes: imageSizes);
    const colors = PageColors(ink: Color(0xFF000000), ink2: Color(0xFF555555), accent: Color(0xFFAA0000), highlight: Color(0xFFEEEEEE));
    var checked = 0;
    // Первые страницы трёх глав и соседние: заголовки, стихи, подписи, сноски, картинка.
    final pages = {
      for (final first in layout.chapterFirstPage) ...[first, first + 1, first + 2],
      layout.pageOf(43, 0),
    };
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
                book: kapitanskaya,
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
        final kind = kapitanskaya.blocks[f.block].kind;
        if (kind == BlockKind.image) {
          if (kapitanskaya.blocks[f.block].text.isNotEmpty) r++;
          continue;
        }
        final rendered = paragraphs[r++];
        if (kind == BlockKind.paragraph || kind == BlockKind.verse || kind == BlockKind.cite) {
          expect(rendered.size.height, moreOrLessEquals(f.height, epsilon: 0.5),
              reason: 'страница $i, блок ${f.block}: строки перенеслись не так, как посчитала разбивка');
          checked++;
        }
      }
    }
    expect(checked, greaterThan(20));
  });

  testWidgets('проверка высоты чувствительна: у той же страницы на другой ширине высоты расходятся', (tester) async {
    final style = PageStyle(fontSize: 16, lineHeight: 27, textScaler: TextScaler.noScaling);
    final col = column(const Size(412, 915));
    final layout = BookLayout.compute(book: kapitanskaya, style: style, column: col, imageSizes: imageSizes);
    final page = layout.pages[1];
    var differs = 0;
    for (final f in page.fragments) {
      final b = kapitanskaya.blocks[f.block];
      if (b.kind != BlockKind.paragraph) continue;
      final tp = fragmentPainter(style, b, f.start, f.end, width: col.width - 12);
      if ((tp.height - f.height).abs() > 0.5) differs++;
      tp.dispose();
    }
    expect(differs, greaterThan(0));
  });
}
