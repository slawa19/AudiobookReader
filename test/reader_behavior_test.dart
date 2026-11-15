import 'package:audiobook_reader/app/theme.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  group('листание (FR-R2)', () {
    testWidgets('касание правой трети — вперёд, левой — назад', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      expect(reader(tester).page, 0);
      await tapRightThird(tester);
      await tester.pumpAndSettle();
      expect(reader(tester).page, 1);
      await tapRightThird(tester);
      await tester.pumpAndSettle();
      expect(reader(tester).page, 2);
      await tapLeftThird(tester);
      await tester.pumpAndSettle();
      expect(reader(tester).page, 1);
    });

    testWidgets('смахивание влево — вперёд, вправо — назад', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
      await tester.pumpAndSettle();
      expect(reader(tester).page, 1);
      await tester.fling(find.byKey(const Key('page-area')), const Offset(250, 0), 1200);
      await tester.pumpAndSettle();
      expect(reader(tester).page, 0);
    });

    testWidgets('переход через границу главы тем же жестом', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      final st = reader(tester);
      final lastOfFirst = st.layout.chapterFirstPage[1] - 1;
      await st.goToPage(lastOfFirst);
      await tester.pumpAndSettle();
      expect(st.layout.pages[st.page].chapter, 0);
      await tapRightThird(tester);
      await tester.pumpAndSettle();
      expect(st.layout.pages[st.page].chapter, 1);
      await tester.fling(find.byKey(const Key('page-area')), const Offset(250, 0), 1200);
      await tester.pumpAndSettle();
      expect(st.layout.pages[st.page].chapter, 0);
    });

    testWidgets('касание центра показывает и прячет панели; страница при этом не листается', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final page = reader(tester).page;
      expect(reader(tester).panelsVisible, isFalse);
      await tapCenter(tester);
      expect(reader(tester).panelsVisible, isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('listen')).hitTestable(), findsOneWidget);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      expect(reader(tester).panelsVisible, isFalse);
      expect(find.byKey(const Key('listen')).hitTestable(), findsNothing);
      expect(reader(tester).page, page);
    });

    testWidgets('ползунок открывает страницу с выбранным местом (FR-R5)', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tapCenter(tester);
      await tester.pumpAndSettle();
      final slider = find.byKey(const Key('book-slider'));
      final box = tester.getRect(slider);
      // Ползунок в теме Material 3 имеет поля по краям; точка на 3/4 дорожки — около 75 %.
      await tester.tapAt(Offset(box.left + 24 + (box.width - 48) * 0.75, box.center.dy));
      await tester.pumpAndSettle();
      final st = reader(tester);
      final page = st.layout.pages[st.page];
      final book = st.widget.book;
      final start = book.fractionAt(page.firstBlock, page.firstOffset);
      final end = book.fractionAt(page.lastBlock, page.lastEnd);
      expect(start, lessThanOrEqualTo(0.77));
      expect(end, greaterThanOrEqualTo(0.73));
    });

    testWidgets('оглавление открывает начало выбранной главы (FR-R4)', (tester) async {
      final p = await pumpPrototype(tester);
      await openDama(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Дама с собачкой').last);
      await tester.pumpAndSettle();
      final st = reader(tester);
      final book = st.widget.book;
      expect(book.chapters[st.layout.pages[st.page].chapter].title, 'Дама с собачкой');
    });
  });

  group('вид текста (FR-R6)', () {
    testWidgets('крупнее шрифт — меньше текста на странице, место чтения сохраняется', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(60, 300));
      final before = reader(tester).layout.pages.length;
      final anchor = reader(tester).layout.pages[reader(tester).page];
      expect(anchor.firstOffset, greaterThan(0), reason: 'страница начинается внутри абзаца — проверка по смещению');
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('font-larger')));
      await tester.tap(find.byKey(const Key('font-larger')));
      await tester.pumpAndSettle();
      expect(p.settings.fontStep, defaultFontStep + 2);
      final st = reader(tester);
      expect(st.layout.pages.length, greaterThan(before));
      final page = st.layout.pages[st.page];
      // Место чтения — сохранённая позиция (60, 300): страница после смены размера содержит её — блок и
      // смещение, а не только блок.
      expect(page.contains(60, 300), isTrue, reason: 'после смены размера на экране то же место книги');
    });

    testWidgets('тема применяется сразу', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();
      expect(p.settings.theme, ThemeChoice.dark);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, darkPalette.bg);
      await tester.tap(find.byKey(const Key('theme-sepia')));
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, sepiaPalette.bg);
    });
  });

  group('сноска и «Читать отсюда»', () {
    testWidgets('знак сноски открывает её поверх страницы (FR-R3)', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      final page = reader(tester).page;
      await tester.tapAt(noteRefCenter(tester, 'n1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsOneWidget);
      expect(find.textContaining('Хвастун'), findsOneWidget);
      expect(reader(tester).page, page);
    });

    testWidgets('долгое нажатие на абзац → «Читать отсюда» начинает с него (FR-P3)', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      final block = wholeParagraphOnPage(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('read-from-here')));
      await tester.pump();
      expect(p.narration.block, block);
      expect(p.narration.state, NarrationState.preparing);
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.state, NarrationState.playing);
    });
  });

  group('озвучка на экране чтения', () {
    testWidgets('«Слушать» → панель плеера, подсветка звучащего абзаца, страница идёт за голосом (FR-P4)',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0));
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.state, NarrationState.playing);
      expect(find.byKey(const Key('player-panel')), findsOneWidget);
      final block = p.narration.block!;
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('hl-$block-')), findsWidgets);
      final startPage = reader(tester).page;
      // Голос уходит вперёд — страница сама переворачивается следом.
      var guard = 0;
      while (reader(tester).page == startPage && guard++ < 300) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(reader(tester).page, greaterThan(startPage));
      final st = reader(tester);
      final at = st.soundingPosition!;
      expect(st.layout.pages[st.page].contains(at.block, at.offset), isTrue,
          reason: 'на экране звучащее место (блок и смещение), а не просто тот же блок');
    });

    testWidgets('листаю сам → следование отключено, «К месту чтения» возвращает', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 2));
      final listening = reader(tester).page;
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isFalse);
      expect(reader(tester).page, listening + 1);
      expect(p.narration.state, NarrationState.playing, reason: 'голос не прерывается');
      await tester.tap(find.byKey(const Key('to-reading-place')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      expect(reader(tester).page, listening);
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });

    testWidgets('пауза, вперёд/назад, скорость, таймер сна, «Закрыть»', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 2));
      final first = p.narration.block!;
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pump();
      expect(p.narration.state, NarrationState.paused);
      await tester.tap(find.byKey(const Key('next')));
      await tester.pump();
      expect(p.narration.block, greaterThan(first));
      expect(p.narration.state, NarrationState.paused, reason: '«вперёд» из паузы оставляет паузу (А§6.6)');
      await tester.tap(find.byKey(const Key('previous')));
      await tester.pump();
      expect(p.narration.block, first);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pump();
      expect(p.narration.state, NarrationState.playing);

      await tester.tap(find.byKey(const Key('speed')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('speed-1.5')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.speed, 1.5);
      expect(p.settings.speed, 1.5);
      expect(find.text('1,5×'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('sleep-30')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer?.minutes, 30);
      expect(find.text('30 мин'), findsOneWidget);

      expect(reader(tester).following, isTrue);
      final onScreen = reader(tester).soundingPosition!;
      await tester.tap(find.byKey(const Key('player-close')));
      await tester.pump();
      expect(p.narration.state, NarrationState.idle);
      expect(find.byKey(const Key('player-panel')), findsNothing);
      expect(p.library.positionOf('kapitanskaya'), onScreen,
          reason: '«Закрыть» при следовании: позиция — звучавшее место на экране (FR-P8, FR-P3)');
      // Панель ушла, страница стала длиннее и пересчитана от того же места: оно на экране.
      final st = reader(tester);
      final page = st.layout.pages[st.page];
      expect(page.firstBlock < onScreen.block || (page.firstBlock == onScreen.block && page.firstOffset <= onScreen.offset),
          isTrue);
      expect(page.lastBlock > onScreen.block || (page.lastBlock == onScreen.block && page.lastEnd > onScreen.offset), isTrue);
    });

    for (final (state, text) in const [
      ('preparing', 'Готовлю голос…'),
      ('waiting', 'Жду связь…'),
      ('end', 'Книга закончилась'),
      ('error402', 'На счёте Gemini закончились деньги'),
      ('error404', 'Модель 3.8 Flash больше недоступна'),
      ('errorOther', 'Google отказал в озвучке'),
    ]) {
      testWidgets('состояние плеера «$state» названо словами в самой панели (FR-P6)', (tester) async {
        final p = await pumpPrototype(tester);
        await openKapitanskaya(tester, p);
        p.narration.demoShow(state, book: currentBook(tester), fromBlock: 39);
        await advance(tester, const Duration(milliseconds: 400));
        expect(find.descendant(of: find.byKey(const Key('player-panel')), matching: find.text(text)), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        if (state == 'error402') expect(find.text('Пополнить'), findsOneWidget);
        if (state == 'error404') expect(find.text('Выбрать модель'), findsOneWidget);
      });
    }

    testWidgets('после ошибки «Слушать» начинает новый сеанс с того же места', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
      // Панель ошибки — новый слой: первые 350 мс касания не принимаются (защита от касания вдогонку).
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('error-listen')));
      await tester.pump();
      expect(p.narration.state, NarrationState.preparing);
      expect(p.narration.block, 39);
    });

    testWidgets('без ключа «Слушать» ведёт в настройки на поле ключа (FR-P7)', (tester) async {
      final p = await pumpPrototype(tester);
      p.settings.apiKey = null;
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('key-field')), findsOneWidget);
      expect(p.narration.state, NarrationState.idle);
    });

    testWidgets('экран голоса ставит паузу; проба играет; выбор голоса книги (FR-V1, FR-V2)', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('voice-chip')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(p.narration.state, NarrationState.paused);
      await tester.tap(find.byKey(const Key('probe-Callirrhoe')));
      await tester.pump();
      expect(p.sampler.voice, 'Callirrhoe');
      await advance(tester, const Duration(seconds: 6));
      expect(p.sampler.voice, isNull, reason: 'проба доиграла');
      await tester.tap(find.byKey(const Key('voice-Kore')));
      await tester.pump();
      expect(p.library.bookVoice('kapitanskaya'), 'Kore');
      expect(p.settings.voice, 'Aoede', reason: 'голос приложения не меняется');
    });

    testWidgets('строка «Скачать главу» на экране чтения и «Стоп» (FR-D2)', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final book = currentBook(tester);
      p.downloads.demoShow(book, 1, failed: false);
      // Строка скачивания — новый слой: первые 350 мс касания не принимаются (защита от касания вдогонку).
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('download-strip')), findsOneWidget);
      await tester.tap(find.text('Стоп'));
      await advance(tester, const Duration(milliseconds: 400));
      expect(find.byKey(const Key('download-strip')), findsNothing);
      expect(p.downloads.task, isNull);
    });
  });

  group('полка и настройки', () {
    testWidgets('удаление книги: меню → подтверждение с объёмом → книги нет (FR-L5)', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.longPress(find.text('Война и мир'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить книгу'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Освободится'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();
      expect(find.text('Война и мир'), findsNothing);
      expect(p.library.shelf.any((e) => e.id == 'voyna'), isFalse);
    });

    testWidgets('«Очистить озвучку» с подтверждением обнуляет место (FR-M3)', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clear-confirm')));
      await tester.pumpAndSettle();
      expect(p.audio.totalBytes, 0);
      expect(find.text('0 МБ'), findsOneWidget);
    });

    testWidgets('полка: дочитанная — «100 %», неоткрытая — «новая» (FR-L4)', (tester) async {
      await pumpPrototype(tester);
      expect(find.text('100 %'), findsOneWidget);
      expect(find.text('новая'), findsOneWidget);
      expect(find.text('прочитана'), findsNothing);
    });

    testWidgets('добавление: строка «Добавляется…», затем книга на полке; отказ висит до «✕»', (tester) async {
      final p = await pumpPrototype(tester);
      p.library.addDemoFile('pushkin_povesti_belkina.fb2.zip', 'ok');
      await tester.pump();
      expect(find.text('Добавляется…'), findsOneWidget);
      await advance(tester, const Duration(seconds: 3));
      expect(find.text('Добавляется…'), findsNothing);
      expect(p.library.shelf.any((e) => e.title == 'Повести Белкина'), isTrue);
      p.library.demoAddJob('unsupported');
      await tester.pump();
      expect(find.text('Этот формат не поддерживается'), findsOneWidget);
      await tester.tap(find.byTooltip('Убрать'));
      await tester.pump();
      expect(find.text('Этот формат не поддерживается'), findsNothing);
    });

    testWidgets('«Состояния для показа» открываются долгим нажатием на заголовок полки', (tester) async {
      await pumpPrototype(tester);
      await tester.longPress(find.byKey(const Key('shelf-title')));
      await tester.pumpAndSettle();
      expect(find.text('Состояния для показа'), findsOneWidget);
      await tester.tap(find.byKey(const Key('demo-player:waiting')));
      await advance(tester, const Duration(seconds: 2));
      await settle(tester, animations: false);
      expect(find.text('Жду связь…'), findsOneWidget);
    });
  });
}
