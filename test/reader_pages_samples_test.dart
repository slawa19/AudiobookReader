import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/reader/page_style.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pagination_test.dart' show checkCoverage, colors, styleFor;
import 'support/book_samples.dart';
import 'support/pagination.dart';
import 'support/reader_samples.dart';

Future<Map<String, Size>> imageSizes(ParsedBook parsed) async {
  final sizes = <String, Size>{};
  for (final entry in parsed.images.entries) {
    final codec = await ui.instantiateImageCodec(entry.value);
    final frame = await codec.getNextFrame();
    sizes[entry.key] = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    codec.dispose();
  }
  return sizes;
}

Future<void> renderPages(
  WidgetTester tester,
  ParsedBook parsed,
  ChapterPagination layout,
  PageStyle style,
  Size column,
) async {
  var textCount = 0;
  var imageCount = 0;
  for (final page in layout.pages) {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: column,
            child: BookPage(
              book: parsed.book,
              page: page,
              style: style,
              colors: colors,
              imageFor: (id) => MemoryImage(parsed.images[id]!),
            ),
          ),
        ),
      ),
    );
    final imageWidgets = tester.widgetList<Image>(find.byType(Image)).toList();
    if (imageWidgets.isNotEmpty) {
      await tester.runAsync(() async {
        for (final image in imageWidgets) {
          await precacheImage(image.image, tester.element(find.byType(BookPage)));
        }
      });
      await tester.pump();
      final renderedImages = tester.renderObjectList<RenderImage>(find.byType(RawImage)).toList();
      expect(renderedImages, hasLength(imageWidgets.length));
      for (final image in renderedImages) {
        expect(image.image, isNotNull, reason: 'проверяется декодированная картинка, а не только пустая рамка');
      }
    }
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(find.descendant(of: find.byType(BookPage), matching: find.byType(RichText)))
        .toList();
    var next = 0;
    for (final fragment in page.fragments) {
      expect(fragment.top, greaterThanOrEqualTo(0));
      final block = parsed.book.blocks[fragment.block];
      if (fragment.isImage) {
        imageCount++;
        expect(fragment.imageSize!.width, lessThanOrEqualTo(column.width));
        if (block.text.isNotEmpty) {
          expect(
            page.fragments.any((f) => f.block == fragment.block && !f.isImage && f.start == 0),
            isTrue,
            reason: 'изображение остаётся с первой строкой подписи',
          );
        }
        continue;
      }
      final rendered = paragraphs[next++];
      if (block.kind == BlockKind.separator) continue;
      expect(
        rendered.size.height,
        moreOrLessEquals(fragment.height, epsilon: 0.5),
        reason: 'реальные строки блока ${block.index} не совпадают с расчётом',
      );
      textCount++;
    }
    for (final image in imageWidgets) {
      expect(image.fit, BoxFit.contain, reason: 'даже без размеров из хранилища изображение не обрезается');
    }
    expect(tester.takeException(), isNull);
  }
  expect(textCount, greaterThan(0));
  expect(imageCount, parsed.book.blocks.where((b) => b.kind == BlockKind.image).length);
}

void main() {
  const column = Size(272, 516); // 320×640 с полями экрана чтения, NOTES.md.
  late Map<String, ParsedBook> samples;
  late Map<String, Map<String, Size>> sizes;
  setUpAll(() async {
    samples = readerSamples(File('assets/demo/images/steppe.png').readAsBytesSync());
    sizes = {for (final entry in samples.entries) entry.key: await imageSizes(entry.value)};
  });

  for (final (step, scale) in [(0, 1.0), (5, 1.3)]) {
    testWidgets('настоящие FB2, FB2.ZIP и EPUB: покрытие и высота всех страниц, ступень ${step + 1} ×$scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final style = styleFor(step, scale);
      final kinds = <BlockKind>{};
      final spans = <SpanStyle>{};
      var withCaption = 0;
      var withoutCaption = 0;
      for (final entry in samples.entries) {
        final parsed = entry.value;
        final book = parsed.book;
        final layout = await paginate(tester: tester, book: book, style: style, column: column, imageSizes: sizes[entry.key]!);
        checkCoverage(book, layout, column);
        await renderPages(tester, parsed, layout, style, column);
        for (final block in book.blocks) {
          kinds.add(block.kind);
          spans.addAll(block.spans.map((s) => s.style));
          if (block.kind == BlockKind.image) {
            block.text.isEmpty ? withoutCaption++ : withCaption++;
          }
        }
      }
      expect(kinds, BlockKind.values.toSet());
      expect(spans, SpanStyle.values.toSet());
      expect(withCaption, greaterThan(0));
      expect(withoutCaption, greaterThan(0));
    });
  }

  testWidgets('настоящий EPUB: длинные заголовок и подпись, портретная картинка и пустая подпись', (tester) async {
    final text = fixture('epub_structures.xhtml')
        .replaceFirst('Заголовок', List.filled(400, 'Длинный заголовок').join(' '))
        .replaceFirst('Подпись ', List.filled(600, 'Длинная подпись ').join())
        .replaceFirst('</figure>', '</figure><figure><img src="pic.png"/><figcaption/></figure>');
    final parsed = checked(
      epub(content: text, raw: {'OPS/pic.png': File('assets/demo/covers/dama.png').readAsBytesSync()}),
    );
    final style = styleFor(5, 1.3);
    final sizes = (await tester.runAsync(() => imageSizes(parsed)))!;
    expect(sizes.values.single.height, greaterThan(sizes.values.single.width));
    final layout = await paginate(tester: tester, book: parsed.book, style: style, column: column, imageSizes: sizes);
    checkCoverage(parsed.book, layout, column);
    for (final block in parsed.book.blocks.where(
      (b) => b.kind == BlockKind.heading || b.kind == BlockKind.image && b.text.isNotEmpty,
    )) {
      expect(
        layout.pages.where((p) => p.fragments.any((f) => f.block == block.index && !f.isImage)).length,
        greaterThan(1),
      );
    }
    await renderPages(tester, parsed, layout, style, column);
  });

  test('пустые блоки из разборщика: разделитель и картинка без подписи не дают строк подписи', () async {
    final book = samples['fb2_structure.xml']!.book;
    final empty = book.blocks.where((b) => b.text.isEmpty).toList();
    expect(empty.map((b) => b.kind), [BlockKind.separator, BlockKind.image]);
    final layout = await paginate(book: book, style: styleFor(5, 1.3), column: column);
    checkCoverage(book, layout, column);
    final image = empty.singleWhere((b) => b.kind == BlockKind.image);
    final fragments = layout.pages.expand((p) => p.fragments).where((f) => f.block == image.index).toList();
    expect(fragments, hasLength(1));
    expect(fragments.single.isImage, isTrue);
    expect(fragments.single.start, fragments.single.end);
  });

  testWidgets('окна измерения не добавляют переносов: длинный абзац, UTF-16 и явные строки стихов', (tester) async {
    final text = List.filled(500, 'Слова 😀 и длинноесловобезпробелов.').join(' ');
    final parsed = checked(
      epub(
        content: fixture('epub_pre.xhtml')
            .replaceFirst('Первая строка\nВторая строка', '$text\n$text')
            .replaceFirst('Первая строка\nВторая строка', text),
      ),
    );
    final style = styleFor(5, 1.3);
    final layout = await paginate(tester: tester, book: parsed.book, style: style, column: column);
    checkCoverage(parsed.book, layout, column);
    for (final block in parsed.book.blocks) {
      final whole = piecePainter(style, block, 0, block.text.length, width: column.width);
      final laidOutHeight = layout.pages
          .expand((p) => p.fragments)
          .where((f) => f.block == block.index)
          .fold(0.0, (height, f) => height + f.height);
      expect(
        laidOutHeight,
        moreOrLessEquals(whole.height, epsilon: 0.5),
        reason: 'окна должны дать те же строки, что и один TextPainter на всём блоке',
      );
      whole.dispose();
    }
    await renderPages(tester, parsed, layout, style, column);
  });

  test('образцы отказов не доходят до reader как пустые книги', () {
    for (final bytes in [utf8.encode(fixture('fb2_empty.xml')), epub(content: fixture('epub_empty.xhtml'))]) {
      expect(() => parseBook(bytes), throwsA(isA<BookParseException>()));
    }
  });
}
