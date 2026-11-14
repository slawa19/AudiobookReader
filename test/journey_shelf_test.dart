// Пути пользователя «полка ↔ книга», добавление и настройки ключа.

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
  testWidgets('слушал и перешёл оглавлением в другую главу → на полку: «Продолжить» называет главу, где остановился',
      (tester) async {
    // FR-L4 и CONCEPT §3: карточка «Продолжить» показывает главу места чтения. Позицию во время прослушивания пишет
    // контроллер (А§5) — название главы должно идти вместе с ней.
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p); // сохранённое место — глава II
    await listenFromPanel(tester);
    await tapCenter(tester);
    await chooseChapter(tester, 'Глава III. Крепость');
    final book = currentBook(tester);
    expect(book.chapterOf(p.narration.block!), 2, reason: 'предусловие: голос в главе III');

    await backToShelf(tester);
    final entry = p.library.entry('kapitanskaya');
    expect(book.chapterOf(p.library.positionOf('kapitanskaya')!.block), 2, reason: 'позиция — в главе III');
    expect(entry.chapterTitle, 'Глава III. Крепость', reason: 'на полке — глава, в которой позиция');
    expect(find.text('Глава II. Вожатый'), findsNothing);
  });

  testWidgets('«Закрыть» после перехода в другую главу → на полку: «Продолжить» называет главу на экране', (tester) async {
    // FR-P8: «Закрыть» отдаёт писателю место на экране (при следовании — звучавшее); полка показывает главу этого
    // места.
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

  testWidgets('дочитал до последней страницы → на полку: «100 %»', (tester) async {
    // FR-L4: «у дочитанной — „100 %“». Читатель, дошедший до последней страницы, книгу дочитал.
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    await tapCenter(tester);
    final slider = tester.getRect(find.byKey(const Key('book-slider')));
    await tester.tapAt(Offset(slider.right - 2, slider.center.dy));
    await tester.pumpAndSettle();
    final st = reader(tester);
    expect(st.page, st.layout.pages.length - 1, reason: 'предусловие: последняя страница');
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), shelfProgress(ru, 1),
        reason: 'на полке дочитанная книга — «100 %»');
  });

  testWidgets('слушал → на полку → снова в книгу: доля на полке равна доле внизу страницы', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await listenFromPanel(tester);
    await advance(tester, const Duration(seconds: 12));
    await backToShelf(tester);
    final shelf = shelfProgress(ru, p.library.entry('kapitanskaya').fraction);
    await openKapitanskaya(tester, p);
    final footer = tester.widget<Text>(find.byKey(const Key('footer-percent'))).data;
    expect(footer, shelf, reason: 'одна и та же книга показывает одну долю');
  });

  testWidgets('листал книгу → на полку → другая книга → назад в первую: та же страница, доля на полке как в книге',
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
    expect(p.library.shelf.first.id, 'dama', reason: 'последняя открытая — первой (FR-L4)');
    await openKapitanskaya(tester, p);
    final now = reader(tester).layout.pages[reader(tester).page];
    expect((now.firstBlock, now.firstOffset), (shown.firstBlock, shown.firstOffset));
  });

  testWidgets('удалил «Записки охотника» → «+» → тот же файл: книга добавляется, приложение не падает', (tester) async {
    // FR-L3 открывает имеющуюся книгу, только если она на полке. После удаления её на полке нет.
    final p = await pumpPrototype(tester);
    await tester.longPress(find.text('Записки охотника'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить книгу'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(p.library.shelf.any((e) => e.id == 'zapiski'), isFalse, reason: 'предусловие');

    await tester.tap(find.byTooltip('Добавить книгу'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-duplicate')));
    await advance(tester, const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Не только «не упало»: книга снова на полке, новая, и открывается (усилено по ревью логики).
    expect(p.library.shelf.where((e) => e.id == 'zapiski').length, 1, reason: 'книга добавлена заново');
    expect(p.library.entry('zapiski').opened, isFalse, reason: 'добавленная заново — новая');
    await openBook(tester, 'Записки охотника');
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(currentBook(tester).id, 'zapiski');
  });

  testWidgets('«+» → «Повести Белкина» дважды: книга на полке одна (FR-L3)', (tester) async {
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

  testWidgets('«+» → новая книга добавилась: «Продолжить» по-прежнему у книги, которую читали, а не у неоткрытой',
      (tester) async {
    // FR-L4: полка — по времени последнего ОТКРЫТИЯ; у неоткрытой — «новая». Продолжить можно только начатую книгу.
    final p = await pumpPrototype(tester);
    await tester.tap(find.byTooltip('Добавить книгу'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-ok')));
    await advance(tester, const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(p.library.shelf.any((e) => e.title == 'Повести Белкина'), isTrue, reason: 'предусловие');
    final card = find.ancestor(of: find.text('Продолжить'), matching: find.byType(Card));
    expect(find.descendant(of: card, matching: find.text('Капитанская дочка')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Повести Белкина')), findsNothing);
  });

  testWidgets('ключ есть → «Изменить» → передумал и нажал «Готово» на пустом поле: ключ не стёрт', (tester) async {
    // FR-P7: поле показывает сохранённый ключ скрытым. «Изменить» с пустым вводом не должно молча удалять ключ:
    // следующее «Слушать» поведёт в настройки.
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
