// Жесты во время прослушивания и на паузе (разделы D и G проверки жестов 2026-11-14).

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

bool onPage(WidgetTester tester, ReadingPosition at) => currentPage(tester).contains(at.block, at.offset);

double scrollPage(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView)).controller!.page!;

void main() {
  testWidgets('быстрые «вперёд» ×3 и «пауза/слушать» ×4 пальцем: место — третий следующий абзац, звук идёт, экран следует',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    final book = currentBook(tester);
    var expected = p.narration.block!;
    for (var i = 0; i < 3; i++) {
      expected++;
      while (!book.blocks[expected].isSpoken || book.blocks[expected].text.trim().isEmpty) {
        expected++;
      }
    }
    final next = tester.getCenter(find.byKey(const Key('next')));
    for (var i = 0; i < 3; i++) {
      await quickTap(tester, next);
      await frames(tester, 48);
    }
    expect(p.narration.block, expected);
    final play = tester.getCenter(find.byKey(const Key('play-pause')));
    for (var i = 0; i < 4; i++) {
      await quickTap(tester, play);
      await frames(tester, 48);
    }
    await advance(tester, const Duration(milliseconds: 800));
    expect(p.narration.state, NarrationState.playing);
    expect(p.narration.block, expected);
    expect(reader(tester).following, isTrue);
    expect(onPage(tester, reader(tester).soundingPosition!), isTrue);
  });

  testWidgets('«Читать отсюда» на нижней половине абзаца, разорванного страницей: звук — с начала абзаца, экран идёт к '
      'голосу, «К месту чтения» нет (FR-P3)', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    final st = reader(tester);
    final book = currentBook(tester);
    // Страница, начинающаяся с продолжения абзаца.
    await gotoPageWhere(tester, (i) {
      final f = st.layout.pages[i].fragments.first;
      return f.start > 0 && book.blocks[f.block].kind.name == 'paragraph' && !pageHasNotes(tester, i);
    }, from: 3);
    final f = currentPage(tester).fragments.first;
    await tester.longPressAt(Offset(pageRect(tester).center.dx, st.pagePadding.top + f.top + f.height / 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('read-from-here')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('read-from-here')));
    await tester.pump();
    expect(p.narration.unitStart, ReadingPosition(f.block, 0));
    await advance(tester, const Duration(seconds: 2));
    expect(p.narration.state, NarrationState.playing);
    expect(reader(tester).following, isTrue);
    expect(find.byKey(const Key('to-reading-place')), findsNothing);
    expect(onPage(tester, reader(tester).soundingPosition!), isTrue,
        reason: 'начало абзаца — на прошлой странице: экран переходит к голосу');
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('hl-${f.block}-')), findsWidgets);
  });

  testWidgets('долгое нажатие посреди автоматического переворота за голосом: выбранный абзац — на странице, которая '
      'осталась на экране; касание мимо — экран догоняет голос', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 40);
    await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0));
    await startListening(tester);
    expect(p.narration.state, NarrationState.playing);
    // Ждём середину автоматического переворота.
    var guard = 0;
    while ((scrollPage(tester) - scrollPage(tester).round()).abs() < 0.15 && guard++ < 4000) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(guard, lessThan(4000), reason: 'предусловие: поймана середина переворота');

    final f = await Finger.down(tester, at(tester, 0.5, 0.3));
    await f.hold(700);
    await f.up();
    await frames(tester, 400);
    expect(tester.takeException(), isNull);
    final settled = scrollPage(tester);
    expect((settled - settled.round()).abs(), lessThan(0.001), reason: 'страница не висит между двумя');
    expect(settled.round(), reader(tester).page);
    final button = find.byKey(const Key('read-from-here'));
    if (button.evaluate().isNotEmpty) {
      // Абзац выбран: он обязан стоять на видимой странице, и кнопка — в пределах экрана.
      expect(button.hitTestable(), findsOneWidget);
    }
    // Касание мимо снимает выбор; экран следует за голосом.
    await tester.tapAt(at(tester, 0.5, 0.12));
    await advance(tester, const Duration(milliseconds: 900));
    expect(find.byKey(const Key('read-from-here')), findsNothing);
    expect(reader(tester).following, isTrue);
    expect(onPage(tester, reader(tester).soundingPosition!), isTrue);
  });

  testWidgets('страница поехала за голосом, палец вернул её на место: побеждает палец — страница остаётся, следование '
      'выключено', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 40);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    // Ждём начало автоматического переворота (первая его треть): читатель ещё дочитывает страницу.
    var guard = 0;
    double frac() => scrollPage(tester) - scrollPage(tester).floor();
    while (!(frac() > 0.1 && frac() < 0.45) && guard++ < 6000) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(guard, lessThan(6000), reason: 'предусловие: пойман автоматический переворот');
    final from = scrollPage(tester).floor();
    expect(reader(tester).page, from, reason: 'предусловие: половина переворота не пройдена');
    // Палец хватает страницу и возвращает её ровно на место: на столько, на сколько она успела уехать.
    final width = pageRect(tester).width;
    final f = await Finger.down(tester, at(tester, 0.3, 0.3));
    await f.move(Offset(frac() * width + 12, 0), ms: 180);
    await f.hold(120);
    expect(scrollPage(tester), closeTo(from.toDouble(), 0.06), reason: 'предусловие: под пальцем снова прежняя страница');
    await f.up();
    // README прототипа, «Жесты»: «побеждает палец: переход отменяется, следование за голосом выключается».
    await advance(tester, const Duration(seconds: 2));
    expect(reader(tester).page, from, reason: 'страница, которую читатель удержал, не уезжает за голосом снова');
    expect(reader(tester).following, isFalse);
    expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
  });

  testWidgets('перетаскивание ползунка в момент конца книги: без исключений, после отпускания — выбранное место',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 400);
    await openKapitanskaya(tester, p);
    final st = reader(tester);
    final book = currentBook(tester);
    // Встаём за страницу до последней и слушаем до конца книги.
    await jumpTo(tester, st.layout.pages.length - 2);
    await startListening(tester);
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 300));
    final box = tester.getRect(find.byKey(const Key('book-slider')));
    final f = await Finger.down(tester, Offset(box.right - 30, box.center.dy));
    await f.move(Offset(-(box.width - 48) * 0.5, 0), ms: 300);
    var guard = 0;
    while (p.narration.state != NarrationState.stopped && guard++ < 600) {
      await f.hold(100);
    }
    expect(p.narration.state, NarrationState.stopped, reason: 'предусловие: книга закончилась, пока палец на ползунке');
    expect(p.narration.stopReason, StopReason.endOfBook);
    await f.move(const Offset(-20, 0), ms: 100);
    await f.up();
    await advance(tester, const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    final page = currentPage(tester);
    final start = book.fractionAt(page.firstBlock, page.firstOffset);
    expect(start, lessThan(0.6), reason: 'на экране место, выбранное ползунком (около половины книги), а не конец');
    expect(reader(tester).following, isFalse);
  });
}
