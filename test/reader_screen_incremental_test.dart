import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_pages_incremental_test.dart' show longChapter;
import 'support/harness.dart';

Future<(Prototype, Book, ReaderScreenState)> openLong(WidgetTester tester, {bool narrow = false, Book? source}) async {
  final p = await pumpPrototype(tester, size: narrow ? phone320 : phone412, textScale: narrow ? 1.3 : 1);
  if (narrow) p.settings.fontStep = fontSteps.length - 1;
  final book = source ?? longChapter();
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(services: p.services, book: book)));
  await tester.pump();
  await tester.pump();
  return (p, book, reader(tester));
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; !ready() && i < 10000; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue, reason: 'the calculation must make progress');
}

void main() {
  testWidgets('SC-1: the screen shows the first page before 300 thousand characters are calculated', (tester) async {
    final (_, book, st) = await openLong(tester);
    expect(book.totalChars, 300000);
    expect(find.byType(BookPage), findsWidgets);
    expect(st.layout.pages[st.page].firstOffset, 0);
    expect(st.layout.pages.last.lastEnd, lessThan(book.blocks.last.text.length),
        reason: 'we check the not-yet-calculated text, not just the presence of the first page');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a font change stops the old calculation and keeps the anchor without page turning', (tester) async {
    final (p, _, st) = await openLong(tester);
    await until(tester, () => st.layout.pages.length > 3);
    await st.goToPage(3);
    await tester.pump();
    final old = st.layout;
    expect(old.isComplete, isFalse);
    final page = old.pages[st.page];
    final anchor = (page.firstBlock, page.firstOffset);
    expect(anchor.$2, greaterThan(0));
    final count = old.pages.length;
    final oldSize = st.pageStyle.fontSize;
    p.settings.fontStep++;
    await tester.pump();
    expect(old.isCalculating, isFalse);
    expect(identical(st.layout, old), isFalse, reason: 'the anchor page of the new layout is ready immediately');
    expect(st.layout.pages[st.page].firstOffset, anchor.$2);
    expect(st.pageStyle.fontSize, greaterThan(oldSize));
    expect(st.layout.pages[st.page].contains(anchor.$1, anchor.$2), isTrue);
    final newPage = st.page;
    await tester.pump(const Duration(milliseconds: 30));
    expect(old.pages, hasLength(count));
    expect(st.page, newPage, reason: 'catching up the tail does not turn the page');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seeking in a huge block is batched and cancellable; 100 % only at the confirmed end', (tester) async {
    final (p, book, st) = await openLong(tester, narrow: true);
    // The route transition and tap protection have finished, but the long chapter is still being calculated.
    await tester.pump(const Duration(milliseconds: 360));
    final area = tester.getRect(find.byKey(const Key('page-area')));
    await tester.tapAt(area.center);
    await tester.pump();
    final slider = tester.widget<Slider>(find.byKey(const Key('book-slider')));
    final target = book.placeAt(0.95);
    expect(st.layout.findPage(target.$1, target.$2), isNull);
    expect(p.library.isFinished(book.id), isFalse);
    final shown = st.layout.pages[st.page];
    slider.onChangeEnd!(0.95);
    await tester.pump();
    expect(st.layout.pages[st.page], same(shown), reason: 'a long paragraph is not calculated synchronously');
    slider.onChangeEnd!(0);
    await tester.pump();
    expect(st.layout.pages[st.page].firstOffset, 0);
    tester.widget<Slider>(find.byKey(const Key('book-slider'))).onChangeEnd!(0.95);
    await tester.pump();
    await until(tester, () => st.layout.pages[st.page].contains(target.$1, target.$2));
    expect(p.library.isFinished(book.id), isFalse);
    expect(st.layout.isComplete, isFalse);
    // The other side: after the catch-up the real end can be opened and 100 % obtained.
    final endSlider = tester.widget<Slider>(find.byKey(const Key('book-slider')));
    endSlider.onChangeEnd!(1);
    await until(tester, () => st.layout.endsBook(st.layout.pages[st.page]));
    await tester.pump();
    expect(p.library.isFinished(book.id), isTrue);
    expect(tester.widget<Slider>(find.byKey(const Key('book-slider'))).value, 1);
    tester.widget<Slider>(find.byKey(const Key('book-slider'))).onChangeEnd!(0);
    await tester.pump();
    expect(p.library.isFinished(book.id), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fast taps beyond the edge of the ready pages are not lost and do not open emptiness', (tester) async {
    final (p, book, st) = await openLong(tester, narrow: true);
    await tester.pump(const Duration(milliseconds: 360));
    expect(st.layout.isComplete, isFalse);
    final lastReady = st.layout.pages.length - 1;
    await st.goToPage(lastReady);
    await tester.pump();
    expect(p.library.isFinished(book.id), isFalse, reason: 'the edge of the ready array is not the end of the book');
    final area = tester.getRect(find.byKey(const Key('page-area')));
    final right = Offset(area.right - 12, area.center.dy);
    // Without advancing the clock: the calculation cannot keep up with three real taps.
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(right);
      await tester.pump();
      expect(st.layout.pages[st.page].fragments, isNotEmpty);
      expect(find.byType(BookPage), findsWidgets);
    }
    expect(st.page, lastReady);
    expect(st.layout.pages, hasLength(lastReady + 1));
    await until(tester, () => st.page == lastReady + 3);
    await tester.pump(const Duration(milliseconds: 400));
    expect(st.page, lastReady + 3);
    expect(st.layout.pages[st.page].fragments, isNotEmpty);
    // A similar case with already ready pages also keeps all taps.
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(right);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(st.page, lastReady + 5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pause in a not-yet-calculated place is caught up without a new voice event', (tester) async {
    final (p, book, st) = await openLong(tester);
    p.narration.demoShow('paused', book: book);
    await tester.pump();
    final sounding = st.soundingPosition!;
    expect(sounding.offset, greaterThan(0));
    expect(st.layout.findPage(sounding.block, sounding.offset), isNull);
    final waitingPage = st.page;
    await tester.pump();
    expect(st.page, waitingPage, reason: 'the voice does not turn pages by the old layout while it is being replaced');
    await until(tester, () => st.layout.pages[st.page].contains(sounding.block, sounding.offset));
    expect(st.following, isTrue);
    final shown = st.page;
    await tester.pump(const Duration(milliseconds: 20));
    expect(st.page, shown);
    // The opposite side: a manual move away holds the screen even if the calculation and the voice continue.
    await st.goToPage(2);
    await tester.pump();
    expect(st.following, isFalse);
    final manual = st.layout.pages[st.page];
    p.narration.demoShow('paused', book: book);
    await tester.pump(const Duration(milliseconds: 20));
    expect(st.layout.pages[st.page].firstOffset, manual.firstOffset);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a swipe beyond the edge of the not-yet-calculated array opens the next page', (tester) async {
    final (p, book, st) = await openLong(tester, narrow: true);
    await tester.pump(const Duration(milliseconds: 360));
    expect(st.layout.isComplete, isFalse);
    final last = st.layout.pages.length - 1;
    await st.goToPage(last);
    await tester.pump();
    final area = tester.getRect(find.byKey(const Key('page-area')));
    final finger = await tester.startGesture(area.center);
    await finger.moveBy(const Offset(-30, 0));
    await tester.pump();
    await finger.moveBy(const Offset(-200, 0));
    await tester.pump();
    expect(st.layout.pages.length, last + 1, reason: 'the gesture outruns the calculation');
    await until(tester, () => st.page == last + 1);
    expect(st.layout.pages[st.page].fragments, isNotEmpty);
    final shown = st.layout.pages[st.page];
    expect(p.library.positionOf(book.id)?.offset, shown.firstOffset,
        reason: 'the move is recorded even if the finger is still holding the previous page');
    await finger.up();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a deferred voice jump before the end clears the finished-book mark', (tester) async {
    final text = longChapter().blocks.single.text.substring(0, 100000);
    final book = Book(id: 'voice-long', title: 'Тест', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 3)],
        blocks: [for (var i = 0; i < 3; i++) Block(index: i, kind: BlockKind.paragraph, text: text)],
        notes: const {});
    final (p, _, st) = await openLong(tester, source: book);
    p.narration.demoShow('paused', book: book);
    await tester.pump();
    await until(tester, () => st.layout.pages[st.page].contains(0, st.soundingPosition!.offset));
    await tester.pump(const Duration(milliseconds: 5));
    p.library.setFinished(book.id, true);
    expect(st.layout.findPage(1, 0), isNull);
    p.narration.next();
    await tester.pump();
    expect(st.soundingPosition!.block, 1);
    await until(tester, () => st.layout.pages[st.page].contains(1, 0));
    expect(p.library.isFinished(book.id), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an explicit voice command takes priority over a pending slider', (tester) async {
    final text = List.filled(3, longChapter().blocks.single.text).join();
    final book = Book(id: 'command-long', title: 'Тест', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 1)],
        blocks: [Block(index: 0, kind: BlockKind.paragraph, text: text)], notes: const {});
    final (p, _, st) = await openLong(tester, source: book);
    p.narration.demoShow('paused', book: book);
    await tester.pump();
    final sounding = st.soundingPosition!;
    await until(tester, () => st.layout.pages[st.page].contains(0, sounding.offset));
    final move = st.goToPage(2);
    await tester.pump(const Duration(milliseconds: 10));
    await move;
    await tester.pump(const Duration(milliseconds: 360));
    await tester.tapAt(tester.getRect(find.byKey(const Key('page-area'))).center);
    await tester.pump();
    final target = book.placeAt(0.95);
    expect(st.layout.findPage(target.$1, target.$2), isNull);
    tester.widget<Slider>(find.byKey(const Key('book-slider'))).onChangeEnd!(0.95);
    tester.widget<IconButton>(find.byKey(const Key('to-reading-place'))).onPressed!();
    await tester.pump(const Duration(milliseconds: 2));
    expect(st.following, isTrue);
    expect(st.layout.pages[st.page].contains(sounding.block, sounding.offset), isTrue,
        reason: 'returning to the voice cancels the pending slider jump even on pause');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a constant panel height keeps the pending slider jump', (tester) async {
    final (p, book, st) = await openLong(tester, narrow: true);
    p.narration.demoShow('paused', book: book);
    await tester.pump();
    final sounding = st.soundingPosition!;
    await until(tester, () => st.layout.pages[st.page].contains(0, sounding.offset));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.tapAt(tester.getRect(find.byKey(const Key('page-area'))).center);
    await tester.pump();
    final target = book.placeAt(0.95);
    expect(st.layout.findPage(target.$1, target.$2), isNull);
    final before = st.pagePadding.bottom;
    tester.widget<Slider>(find.byKey(const Key('book-slider'))).onChangeEnd!(0.95);
    await until(tester, () => st.layout.findPage(target.$1, target.$2) != null);
    await tester.pump();
    await tester.pump();
    expect(st.pagePadding.bottom, before, reason: 'the icon does not change the panel height');
    expect(st.layout.pages[st.page].contains(target.$1, target.$2), isTrue);
    expect(st.following, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
