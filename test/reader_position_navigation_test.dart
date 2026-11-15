import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/reader/page_style.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reader_screen_position_test.dart' show openAt, millionBook;
import 'gesture_support.dart' show Finger;
import 'support/harness.dart';

Book chaptersBook() => Book(id: 'navigation', title: 'Границы', author: '', language: 'ru',
    chapters: [for (var i = 0; i < 3; i++) Chapter(title: 'Глава $i', level: 1, firstBlock: i, blockCount: 1)],
    blocks: [for (var i = 0; i < 3; i++) Block(index: i, kind: BlockKind.paragraph,
        text: List.filled(300, 'Глава $i. Обычный текст и 😀. ').join())], notes: const {});

Future<void> complete(ChapterPagination layout) async {
  while (!layout.isComplete) { await Future<void>.delayed(const Duration(milliseconds: 5)); }
}

List<(int, int, int)> pieces(BookPageLayout page) => [for (final f in page.fragments) (f.block, f.start, f.end)];

void main() {
  testWidgets('короткий быстрый бросок вправо подключает неизвестную предыдущую страницу', (tester) async {
    final p = await pumpPrototype(tester);
    final book = chaptersBook();
    final st = await openAt(tester, p, book, const ReadingPosition(1, 123));
    await tester.pump(const Duration(milliseconds: 360));
    final anchor = st.layout.pages[st.page];
    final area = tester.getRect(find.byKey(const Key('page-area')));
    final finger = await Finger.down(tester, area.center);
    await finger.move(const Offset(40, 0), ms: 120);
    await finger.move(const Offset(-40, 0), ms: 120);
    await finger.hold(300);
    await finger.up();
    await tester.pumpAndSettle();
    expect(st.layout.pages[st.page], same(anchor), reason: 'малое движение с возвратом не листает');
    await tester.fling(find.byKey(const Key('page-area')), const Offset(100, 0), 2000);
    await tester.pumpAndSettle();
    expect(st.layout.pages[st.page].lastEnd, 123,
        reason: 'бросок меньше половины ширины, но с достаточной скоростью, не теряется');
    expect(st.layout.pages[st.page], isNot(same(anchor)));
    await tester.pumpWidget(const SizedBox());
  });

  test('пустые текстовые главы пропускаются назад; пустая картинка остаётся видимой', () async {
    final style = PageStyle(fontSize: 16, lineHeight: 27, textScaler: TextScaler.noScaling);
    final layout = ChapterPagination();
    addTearDown(layout.dispose);
    final book = Book(id: 'empty-prefix', title: '', author: '', language: 'ru',
        chapters: [for (var i = 0; i < 3; i++) Chapter(title: '$i', level: 1, firstBlock: i, blockCount: 1)],
        blocks: const [Block(index: 0, kind: BlockKind.paragraph, text: 'Первый.'),
          Block(index: 1, kind: BlockKind.paragraph, text: ''),
          Block(index: 2, kind: BlockKind.paragraph, text: 'Последний.')], notes: const {});
    layout.start(book: book, style: style, column: const Size(272, 500), block: 2, offset: 0, throughBook: true);
    await layout.loadPrevious();
    expect(layout.pages.first.firstBlock, 0, reason: 'пустая глава не должна повторяться бесконечно');
    final imageBook = Book(id: 'image-prefix', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 2)],
        blocks: const [Block(index: 0, kind: BlockKind.image, text: '', imageId: 'pic'),
          Block(index: 1, kind: BlockKind.paragraph, text: 'Текст.')], notes: const {});
    layout.start(book: imageBook, style: style, column: const Size(272, 500), block: 1, offset: 0, throughBook: true);
    expect(layout.hasPrevious, isTrue);
    await layout.loadPrevious();
    expect(layout.pages.first.fragments.first.isImage, isTrue);
  });

  testWidgets('новое листание вперёд отменяет незавершённый запрос назад', (tester) async {
    final p = await pumpPrototype(tester);
    final book = chaptersBook();
    final st = await openAt(tester, p, book, const ReadingPosition(1, 1000));
    await tester.pump(const Duration(milliseconds: 1));
    final target = st.layout.pages[1];
    final back = st.goToPage(-1);
    final forward = st.goToPage(1);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    await forward;
    await back;
    expect(st.layout.pages[st.page], same(target));
    await tester.pumpWidget(const SizedBox());
  });

  test('назад от середины главы через её границу: покрытие без пропусков, показанные страницы неизменны', () async {
    final book = chaptersBook();
    final layout = ChapterPagination();
    addTearDown(layout.dispose);
    final style = PageStyle(fontSize: 16, lineHeight: 27, textScaler: TextScaler.noScaling);
    layout.start(book: book, style: style, column: const Size(272, 500), block: 1, offset: 2345, throughBook: true);
    final anchor = layout.pages.single;
    final original = pieces(anchor);
    expect(anchor.firstOffset, 2345);
    await complete(layout);
    final suffix = layout.pages.toList();
    final seen = [for (final p in suffix) pieces(p)];
    final firstAdded = await layout.loadPrevious();
    expect(firstAdded, greaterThan(0));
    expect(layout.pages[firstAdded], same(anchor));
    expect(pieces(anchor), original);
    expect(layout.pages[firstAdded - 1].lastEnd, 2345, reason: 'короткая страница обрывается точно перед якорем');
    expect(layout.pages.first.chapter, 1, reason: 'назад считаем текущую главу, а не начало книги');
    final secondAdded = await layout.loadPrevious();
    expect(secondAdded, greaterThan(0));
    expect(layout.pages.first.chapter, 0);
    expect(layout.hasPrevious, isFalse);
    // Обе стороны перехода: возвращение вперёд использует те же объекты и те же границы текста.
    for (var i = 0; i < suffix.length; i++) {
      final page = layout.pages[firstAdded + secondAdded + i];
      expect(page, same(suffix[i]));
      expect(pieces(page), seen[i]);
    }
    for (final block in book.blocks) {
      var at = 0;
      for (final page in layout.pages) {
        for (final f in page.fragments.where((f) => f.block == block.index)) {
          expect(f.start, at, reason: 'каждый знак встречается ровно один раз');
          expect(f.end, greaterThan(f.start));
          at = f.end;
        }
      }
      expect(at, block.text.length);
    }
  });

  testWidgets('экран листает назад через неизвестную границу главы и возвращается к тому же тексту', (tester) async {
    final p = await pumpPrototype(tester);
    final book = chaptersBook();
    final st = await openAt(tester, p, book, const ReadingPosition(1, 123));
    final anchor = st.layout.pages[st.page];
    final original = pieces(anchor);
    var back = st.goToPage(-1);
    for (var i = 0; st.layout.prependedCount == 0 && i < 1000; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.pumpAndSettle();
    await back;
    expect(st.layout.pages[st.page].chapter, 1);
    expect(st.layout.pages[st.page].lastEnd, 123);
    back = st.goToPage(-1);
    await tester.pumpAndSettle();
    await back;
    expect(st.layout.pages[st.page].chapter, 0);
    final returnIndex = st.layout.pages.indexOf(anchor);
    await st.goToPage(returnIndex);
    await tester.pump();
    expect(st.layout.pages[st.page], same(anchor));
    expect(pieces(st.layout.pages[st.page]), original);
    expect(p.library.positionOf(book.id), ReadingPosition(anchor.firstBlock, anchor.firstOffset));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('100 % известно на самой последней странице, пока итератор ещё не завершён', (tester) async {
    final p = await pumpPrototype(tester);
    final book = millionBook();
    final st = await openAt(tester, p, book, const ReadingPosition(0, 2999000));
    expect(st.layout.isComplete, isFalse);
    // Стартовая страница включает конец книги; обработчик завершения итератора ещё не вызван.
    expect(st.layout.endsBook(st.layout.pages[st.page]), isTrue);
    expect(p.library.isFinished(book.id), isTrue);
    expect(tester.widget<Text>(find.byKey(const Key('footer-percent'))).data, '100\u00a0%');
    expect(p.library.positionOf(book.id)?.offset, 2999000);
    await tester.pumpWidget(const SizedBox());
  });
}
