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
  testWidgets('a short fast flick to the right attaches the unknown previous page', (tester) async {
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
    expect(st.layout.pages[st.page], same(anchor), reason: 'a small movement with a return does not turn the page');
    await tester.fling(find.byKey(const Key('page-area')), const Offset(100, 0), 2000);
    await tester.pumpAndSettle();
    expect(st.layout.pages[st.page].firstOffset, 0,
        reason: 'the flick opens the full first page of the chapter instead of a short prefix');
    expect(st.layout.pages[st.page].lastEnd, greaterThan(123));
    expect(st.layout.pages[st.page], isNot(same(anchor)));
    await tester.pumpWidget(const SizedBox());
  });

  test('empty text chapters are skipped backwards; an empty image stays visible', () async {
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
    expect(layout.pages.first.firstBlock, 0, reason: 'an empty chapter must not repeat endlessly');
    final imageBook = Book(id: 'image-prefix', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 2)],
        blocks: const [Block(index: 0, kind: BlockKind.image, text: '', imageId: 'pic'),
          Block(index: 1, kind: BlockKind.paragraph, text: 'Текст.')], notes: const {});
    layout.start(book: imageBook, style: style, column: const Size(272, 500), block: 1, offset: 0, throughBook: true);
    expect(layout.hasPrevious, isTrue);
    await layout.loadPrevious();
    expect(layout.pages.first.fragments.first.isImage, isTrue);
  });

  testWidgets('a new forward page turn cancels an unfinished backward request', (tester) async {
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

  test('backwards across a chapter boundary: coverage without gaps, shown pages unchanged', () async {
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
    expect(layout.pages[firstAdded - 1].lastEnd, 2345, reason: 'the full backward page ends before the anchor');
    expect(layout.pages.first.chapter, 1, reason: 'backwards lays out the current chapter, not the book start');
    final secondAdded = await layout.loadPrevious();
    expect(secondAdded, greaterThan(0));
    expect(layout.pages.first.chapter, 0);
    expect(layout.hasPrevious, isFalse);
    // Both sides of the transition: returning forward uses the same objects and the same text boundaries.
    for (var i = 0; i < suffix.length; i++) {
      final page = layout.pages[firstAdded + secondAdded + i];
      expect(page, same(suffix[i]));
      expect(pieces(page), seen[i]);
    }
    var overlaps = 0;
    for (final block in book.blocks) {
      var at = 0;
      for (var i = 0; i < layout.pages.length; i++) {
        final page = layout.pages[i];
        for (final f in page.fragments.where((f) => f.block == block.index)) {
          if (f.start != at) {
            expect(i, layout.chapterFirstPage[page.chapter] + 1, reason: 'overlap only at the first chapter boundary');
            expect(f.start, lessThan(at), reason: 'there are no text gaps');
            overlaps++;
          }
          expect(f.end, greaterThan(f.start));
          at = f.end;
        }
      }
      expect(at, block.text.length);
    }
    expect(overlaps, 1);
  });

  testWidgets('the screen turns back across an unknown chapter boundary and returns to the same text', (tester) async {
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
    expect(st.layout.pages[st.page].firstOffset, 0);
    expect(st.layout.pages[st.page].lastEnd, greaterThan(123), reason: 'the first page is full, some lines will repeat on the next one');
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

  testWidgets('100 % is known on the very last page while the iterator has not finished yet', (tester) async {
    final p = await pumpPrototype(tester);
    final book = millionBook();
    final st = await openAt(tester, p, book, const ReadingPosition(0, 2999000));
    expect(st.layout.isComplete, isFalse);
    // The start page includes the end of the book; the iterator completion handler has not been called yet.
    expect(st.layout.endsBook(st.layout.pages[st.page]), isTrue);
    expect(p.library.isFinished(book.id), isTrue);
    expect(tester.widget<Text>(find.byKey(const Key('footer-percent'))).data, '100\u00a0%');
    expect(p.library.positionOf(book.id)?.offset, 2999000);
    await tester.pumpWidget(const SizedBox());
  });
}
