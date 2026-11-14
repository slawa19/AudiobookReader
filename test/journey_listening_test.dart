// Пути пользователя «чтение × прослушивание»: последовательности из двух–четырёх действий.
// Ожидание каждого теста — от читателя и из спеки/архитектуры; тест, который падает, доказывает дефект.

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'journey_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  group('оглавление во время прослушивания', () {
    testWidgets('листал сам → оглавление → другая глава: голос и страница в новой главе, следование включено',
        (tester) async {
      // А§5: следование отключается «до нажатия „К месту чтения“ или до нового старта»; смена главы в оглавлении —
      // новый старт (А§5, А§6.4). Читатель ждёт, что дальше страницы снова листаются за голосом.
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isFalse, reason: 'предусловие: читатель листал сам');

      await tapCenter(tester);
      await chooseChapter(tester, 'Глава III. Крепость');

      final st = reader(tester);
      final book = st.widget.book;
      expect(p.narration.block, book.chapters[2].firstBlock, reason: 'голос перешёл на начало главы');
      expect(st.layout.pages[st.page].chapter, 2, reason: 'страница — в выбранной главе');
      expect(st.following, isTrue, reason: 'смена главы — новый старт: следование снова включено');
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });
  });

  group('таймер сна', () {
    testWidgets('таймер 15 мин → «Закрыть» → через три часа «Слушать»: звук идёт, а не встаёт на паузу',
        (tester) async {
      // «Закрыть» завершает прослушивание (FR-P8). Таймер, поставленный вчера вечером, не должен останавливать
      // сегодняшнее прослушивание через долю секунды.
      final clock = TestClock();
      final p = await pumpWithClock(tester, clock);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('sleep-15')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer?.minutes, 15, reason: 'предусловие');

      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 500));
      clock.forward(const Duration(hours: 3));

      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.state, NarrationState.playing, reason: 'новое прослушивание не гасит старый таймер');
      expect(find.text(ru.minutesShort(0)), findsNothing, reason: 'на панели нет таймера «0 мин»');
    });

    testWidgets('таймер истёк, пока стояла пауза → «Слушать»: звук продолжается', (tester) async {
      // Таймер — «пауза по времени» (А§6.6). Если к его сроку уже стоит пауза, ему нечего останавливать; нажатое
      // после этого «Слушать» продолжает с места паузы (FR-P3), а не ставит паузу снова через 0,1 с.
      final clock = TestClock();
      final p = await pumpWithClock(tester, clock);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('sleep-15')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.state, NarrationState.paused, reason: 'предусловие');

      clock.forward(const Duration(minutes: 20));
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.state, NarrationState.playing);
    });
  });

  group('«Готовлю голос…» и «Жду связь…»', () {
    testWidgets('«Жду связь…» → листаю сам: видна «К месту чтения» и чип голоса', (tester) async {
      // FR-P4: «Кнопка „К месту чтения“ видна, когда следование отключено» — без исключения для waiting/preparing.
      // FR-V2: вход «Голос» есть на панели плеера. «Жду связь…» может длиться долго (нет сети).
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.demoShow('waiting');
      await advance(tester, const Duration(milliseconds: 400));
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isFalse, reason: 'предусловие: следование отключено');
      expect(p.narration.state, NarrationState.waiting);
      expect(find.byKey(const Key('to-reading-place')), findsOneWidget,
          reason: 'вернуться к месту чтения можно и пока голос ждёт связь');
      expect(find.byKey(const Key('voice-chip')), findsOneWidget);
    });
  });

  group('ошибка 404 → «Выбрать модель»', () {
    testWidgets('выбрал другую модель и вернулся: панель не называет недоступной только что выбранную', (tester) async {
      // FR-P7: «Выбрать модель», из настроек «Назад» — в ту же книгу. Недоступной была 3.8 Flash; после выбора
      // Flash-Lite панель не должна утверждать, что недоступна Flash-Lite.
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('error404', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.text(ru.error404Title('3.8 Flash')), findsOneWidget, reason: 'предусловие');

      await tester.tap(find.byKey(const Key('choose-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-flashLite')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.text(ru.error404Title('3.8 Flash-Lite')), findsNothing,
          reason: 'панель говорит, что недоступна модель, которую читатель только что выбрал');
    });
  });

  group('перераскладка страницы, пока звук стоит', () {
    testWidgets('пауза на абзаце у низа страницы → крупнее шрифт: на экране место прослушивания', (tester) async {
      // А§5: пока прослушивание активно (пауза — тоже), позиция — место контроллера; следование включено, значит
      // экран показывает страницу с ним. FR-R6/FR-R7: смена шрифта место не теряет.
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 400));
      final block = lowestStartingParagraph(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('read-from-here')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.narration.state, NarrationState.paused, reason: 'предусловие');
      expect(p.narration.block, block);
      expect(onScreen(tester, block, 0), isTrue, reason: 'предусловие: место на экране');

      await tapCenter(tester);
      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('font-larger')));
        await tester.pumpAndSettle();
      }
      expect(p.settings.fontStep, defaultFontStep + 3);
      expect(reader(tester).following, isTrue);
      expect(onScreen(tester, block, 0), isTrue, reason: 'после смены шрифта на экране звучащий (поставленный на паузу) абзац');
    });

    testWidgets('пауза на абзаце у низа страницы → ошибка 402: на экране место остановки', (tester) async {
      // А§5: «При переходе в stopped экран сначала показывает страницу с сохранённой позицией». Панель ошибки выше
      // панели плеера — страница становится короче, но место остановки должно остаться на экране.
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 400));
      final block = lowestStartingParagraph(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('read-from-here')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(onScreen(tester, block, 0), isTrue, reason: 'предусловие');

      p.narration.demoShow('error402');
      await tester.pumpAndSettle();
      expect(p.narration.state, NarrationState.stopped);
      expect(p.library.positionOf('kapitanskaya')!.block, block, reason: 'сохранённая позиция — место остановки');
      expect(onScreen(tester, block, 0), isTrue, reason: 'экран показывает страницу с сохранённой позицией');
    });
  });

  group('экран «Голос»', () {
    testWidgets('пауза → «Голос» → касание уже выбранной строки: место внутри абзаца не теряется', (tester) async {
      // FR-V2/А§6.4: новый сеанс начинается при СМЕНЕ голоса. Касание строки, которая и так выбрана, голос не меняет —
      // «Слушать» после возврата продолжает с места паузы (FR-P3).
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 4));
      await tester.tap(find.byKey(const Key('voice-chip')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(p.narration.state, NarrationState.paused);
      final block = p.narration.block;
      final progress = p.narration.blockProgress;
      expect(progress, greaterThan(0.05), reason: 'предусловие: пауза внутри абзаца');

      await tester.tap(find.text('Как в настройках'));
      await advance(tester, const Duration(milliseconds: 400));
      expect(p.library.bookVoice('kapitanskaya'), isNull, reason: 'голос не изменился');
      expect(p.narration.block, block);
      expect(p.narration.blockProgress, closeTo(progress, 0.001), reason: 'место паузы прежнее');
    });
  });

  group('выбор абзаца во время звука', () {
    testWidgets('долгое нажатие на абзац перед самым переворотом страницы: «Читать отсюда» не уезжает вместе со страницей',
        (tester) async {
      // FR-P3: «долгое нажатие на абзац → „Читать отсюда“». Пока читатель выбирает место, страница под пальцем не
      // должна уходить: иначе кнопка исчезает, не дождавшись нажатия.
      final p = await pumpPrototype(tester, demoAcceleration: 4);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final st = reader(tester);
      var guard = 0;
      while (guard++ < 3000) {
        final page = st.layout.pages[st.page];
        final at = st.soundingPosition!;
        final last = page.fragments.last;
        if (at.block == last.block && at.offset >= last.start) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      final page0 = st.page;
      final block = wholeParagraphOnPage(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('read-from-here')), findsOneWidget, reason: 'предусловие: кнопка показана');
      await advance(tester, const Duration(seconds: 8));
      expect(p.narration.block, isNot(block), reason: 'предусловие: голос ушёл дальше');
      expect(find.byKey(const Key('read-from-here')), findsOneWidget, reason: 'кнопка ждёт нажатия');
      expect(st.page, page0, reason: 'страница с выбранным абзацем осталась на экране');
    });
  });

  group('системная «Назад»', () {
    testWidgets('выбран абзац («Читать отсюда») во время прослушивания → «Назад»: снимается выбор, книга и звук остаются',
        (tester) async {
      // README прототипа: выбор абзаца отменяется «касанием мимо». На Android системная «Назад» сначала убирает
      // временный режим выбора, а не закрывает экран под ним; закрытие книги здесь обрывает прослушивание (А§8.1).
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final block = wholeParagraphOnPage(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('read-from-here')), findsOneWidget, reason: 'предусловие');

      await tester.binding.handlePopRoute();
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byType(ReaderScreen), findsOneWidget, reason: 'книга не закрыта');
      expect(p.narration.state, NarrationState.playing, reason: 'прослушивание не оборвано');
      expect(find.byKey(const Key('read-from-here')), findsNothing, reason: 'выбор абзаца снят');
    });
  });

  group('пути, которые в порядке (не покрыты прежними тестами)', () {
    testWidgets('смена языка интерфейса во время прослушивания: страница, плеер и лист на месте', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final page = reader(tester).page;
      await tapCenter(tester);
      await tester.longPress(find.text('Капитанская дочка').last);
      await advance(tester, const Duration(milliseconds: 800));
      await tester.scrollUntilVisible(find.byKey(const Key('demo-lang-en')), 200,
          scrollable: find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first);
      await advance(tester, const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('demo-lang-en')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(find.byKey(const Key('demo-lang-en')), findsOneWidget, reason: 'лист не закрылся');
      expect(p.settings.language, 'en');
      expect(find.byTooltip('Next paragraph'), findsOneWidget, reason: 'панель плеера уже на английском');
      expect(p.narration.state, NarrationState.playing);
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect((reader(tester).page - page).abs(), lessThanOrEqualTo(1), reason: 'место то же (или страница за голосом)');
      final at = reader(tester).soundingPosition!;
      expect(onScreen(tester, at.block, at.offset), isTrue);
    });

    testWidgets('дослушал до конца книги: «Книга закончилась», на экране последняя страница; «Закрыть» её не сдвигает',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p, at: const ReadingPosition(99, 0));
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 10));
      expect(p.narration.state, NarrationState.stopped);
      expect(p.narration.stopReason, StopReason.endOfBook);
      expect(find.text(ru.endOfBook), findsOneWidget);
      final st = reader(tester);
      final book = st.widget.book;
      final last = book.blocks.length - 1;
      expect(onScreen(tester, last, book.blocks[last].text.length - 1), isTrue, reason: 'на экране конец книги');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.narration.state, NarrationState.idle);
      expect(onScreen(tester, last, book.blocks[last].text.length - 1), isTrue, reason: 'страница не уехала');
    });

    testWidgets('нет ключа → «Слушать» → ключ → «Назад»: та же книга и страница, озвучка сама не началась (FR-P7)',
        (tester) async {
      final p = await pumpPrototype(tester);
      p.settings.apiKey = null;
      await openKapitanskaya(tester, p);
      final page = reader(tester).page;
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('key-field')), 'AIzaSyD-test-key-9z9z');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(p.settings.hasApiKey, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(reader(tester).page, page);
      expect(p.narration.state, NarrationState.idle);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.state, NarrationState.playing, reason: 'со вторым «Слушать» озвучка идёт');
    });
  });

  group('перераскладка при появлении панели плеера', () {
    testWidgets('«Читать отсюда» на абзаце у низа страницы (без прослушивания): пока «Готовлю голос…», абзац на экране',
        (tester) async {
      // FR-P3/А§5: «Читать отсюда» начинает с выбранного абзаца, следование включено — экран показывает место, с
      // которого начнётся голос. Панель плеера появляется и укорачивает страницу; абзац не должен уйти с экрана.
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      final block = lowestStartingParagraph(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('read-from-here')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.narration.state, NarrationState.preparing, reason: 'предусловие: голос ещё готовится');
      expect(p.narration.block, block);
      expect(onScreen(tester, block, 0), isTrue, reason: 'выбранный абзац на экране');
    });
  });
}
