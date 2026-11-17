// User journeys “shelf ↔ book”, adding a book and key settings.

import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'journey_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

Future<void> backToShelf(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byTooltip('Назад'));
  await tester.pumpAndSettle();
  await settle(tester);
}

void main() {
  testWidgets('listened and moved to another chapter via the table of contents → shelf: “Continue” names the chapter '
      'where I stopped',
      (tester) async {
    // FR-L4 and CONCEPT §3: the “Continue” card shows the chapter of the reading position. During listening the
    // position is written by the controller (A§5) — the chapter title must go together with it.
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p); // the saved position is in chapter II
    await listenFromPanel(tester);
    await tapCenter(tester);
    await chooseChapter(tester, 'Глава III. Крепость');
    final book = currentBook(tester);
    expect(book.chapterOf(p.narration.block!), 2, reason: 'precondition: the voice is in chapter III');

    await backToShelf(tester);
    final entry = p.library.entry('kapitanskaya');
    expect(book.chapterOf(p.library.positionOf('kapitanskaya')!.block), 2, reason: 'the position is in chapter III');
    expect(entry.chapterTitle, 'Глава III. Крепость', reason: 'the shelf shows the chapter that holds the position');
    expect(find.text('Глава II. Вожатый'), findsNothing);
  });

  testWidgets('“Close” after moving to another chapter → shelf: “Continue” names the chapter on '
      'screen', (tester) async {
    // FR-P8: “Close” gives the writer the position on screen (when following — the one that was playing); the shelf
    // shows the chapter of that position.
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await listenFromPanel(tester);
    await tapCenter(tester);
    await chooseChapter(tester, 'Глава III. Крепость');
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(milliseconds: 600));
    await backToShelf(tester);
    expect(p.library.entry('kapitanskaya').chapterTitle, 'Глава III. Крепость');
  });

  testWidgets('read to the last page → shelf: “100 %”', (tester) async {
    // FR-L4: "a finished book shows “100 %”". A reader who reached the last page has finished the book.
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    await tapCenter(tester);
    final slider = tester.getRect(find.byKey(const Key('book-slider')));
    await tester.tapAt(Offset(slider.right - 2, slider.center.dy));
    await tester.pumpAndSettle();
    final st = reader(tester);
    expect(st.page, st.layout.pages.length - 1, reason: 'precondition: the last page');
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), shelfProgress(ru, 1),
        reason: 'on the shelf a finished book shows “100 %”');
  });

  testWidgets('listened → shelf → back into the book: the fraction on the shelf equals the fraction at the bottom of '
      'the page', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await listenFromPanel(tester);
    await advance(tester, const Duration(seconds: 12));
    await backToShelf(tester);
    final shelf = shelfProgress(ru, p.library.entry('kapitanskaya').fraction);
    await openKapitanskaya(tester, p);
    final footer = tester.widget<Text>(find.byKey(const Key('footer-percent'))).data;
    expect(footer, shelf, reason: 'the same book shows the same fraction');
  });

  testWidgets('turned pages → shelf → another book → back to the first: the same page, the fraction on the shelf '
      'matches the book',
      (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    await tapRightThird(tester);
    await tapRightThird(tester);
    await tester.pumpAndSettle();
    final st = reader(tester);
    final shown = st.layout.pages[st.page];
    final footer = tester.widget<Text>(find.byKey(const Key('footer-percent'))).data;
    await backToShelf(tester);
    expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), footer);
    await openDama(tester, p);
    await tapRightThird(tester);
    await tester.pumpAndSettle();
    await backToShelf(tester);
    expect(p.library.shelf.first.id, 'dama', reason: 'the last opened book comes first (FR-L4)');
    await openKapitanskaya(tester, p);
    final now = reader(tester).layout.pages[reader(tester).page];
    expect((now.firstBlock, now.firstOffset), (shown.firstBlock, shown.firstOffset));
  });

  testWidgets('deleted “Записки охотника” → “+” → the same file: the book is added, the app does not '
      'crash', (tester) async {
    // FR-L3 opens an existing book only if it is on the shelf. After deletion it is not on the shelf.
    final p = await pumpPrototype(tester);
    await tester.longPress(find.text('Записки охотника'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить книгу'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(p.library.shelf.any((e) => e.id == 'zapiski'), isFalse, reason: 'precondition');

    await tester.tap(find.byTooltip('Добавить книгу'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-duplicate')));
    await advance(tester, const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Not only "did not crash": the book is on the shelf again, new, and opens (strengthened per the logic review).
    expect(p.library.shelf.where((e) => e.id == 'zapiski').length, 1, reason: 'the book is added again');
    expect(p.library.entry('zapiski').opened, isFalse, reason: 'a re-added book is new');
    await openBook(tester, 'Записки охотника');
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(currentBook(tester).id, 'zapiski');
  });

  testWidgets('“+” → “Повести Белкина” twice: there is one book on the shelf (FR-L3)', (tester) async {
    final p = await pumpPrototype(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Добавить книгу'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-ok')));
      await advance(tester, const Duration(seconds: 3));
      await tester.pumpAndSettle();
      if (find.byType(ReaderScreen).evaluate().isNotEmpty) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
    }
    expect(p.library.shelf.where((e) => e.title == 'Повести Белкина').length, 1);
  });

  testWidgets('“+” → a new book is added: “Continue” still belongs to the book that was being read, not to the '
      'unopened one',
      (tester) async {
    // FR-L4: the shelf is ordered by the time of the last OPENING; an unopened book is "new". Only a started book can
    // be continued.
    final p = await pumpPrototype(tester);
    await tester.tap(find.byTooltip('Добавить книгу'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-ok')));
    await advance(tester, const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(p.library.shelf.any((e) => e.title == 'Повести Белкина'), isTrue, reason: 'precondition');
    final card = find.ancestor(of: find.text('Продолжить'), matching: find.byType(Card));
    expect(find.descendant(of: card, matching: find.text('Капитанская дочка')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Повести Белкина')), findsNothing);
  });

  testWidgets('a key exists → “Change” → changed my mind and pressed “Done” on an empty field: the key is not '
      'erased', (tester) async {
    // FR-P7: the field shows the saved key hidden. “Change” with empty input must not silently delete the key:
    // the next “Listen” would lead to settings.
    final p = await pumpPrototype(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('key-change')));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byKey(const Key('key-field')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(p.settings.hasApiKey, isTrue);
  });
}
