import 'package:audiobook_reader/app/theme.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  group('page turning (FR-R2)', () {
    testWidgets('a tap on the right third goes forward, on the left third back', (tester) async {
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

    testWidgets('a swipe left goes forward, right goes back', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
      await tester.pumpAndSettle();
      expect(reader(tester).page, 1);
      await tester.fling(find.byKey(const Key('page-area')), const Offset(250, 0), 1200);
      await tester.pumpAndSettle();
      expect(reader(tester).page, 0);
    });

    testWidgets('crossing a chapter boundary with the same gesture', (tester) async {
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

    testWidgets('a tap on the center shows and hides the panels; the page does not turn', (tester) async {
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

    testWidgets('the slider opens the page with the chosen place (FR-R5)', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tapCenter(tester);
      await tester.pumpAndSettle();
      final slider = find.byKey(const Key('book-slider'));
      final box = tester.getRect(slider);
      // The slider in the Material 3 theme has margins at its edges; a point at 3/4 of the track is about 75 %.
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

    testWidgets('the table of contents opens the start of the chosen chapter (FR-R4)', (tester) async {
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

  group('text appearance (FR-R6)', () {
    testWidgets('a larger font means less text on the page, the reading place is kept', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(60, 300));
      final before = reader(tester).layout.pages.length;
      final anchor = reader(tester).layout.pages[reader(tester).page];
      expect(anchor.firstOffset, greaterThan(0), reason: 'page starts inside a paragraph, checked by offset');
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
      // The reading place is the saved position (60, 300): after the size change the page contains it, both
      // block and offset, not just the block.
      expect(page.contains(60, 300), isTrue, reason: 'after the size change the same place of the book is on screen');
    });

    testWidgets('the theme is applied immediately', (tester) async {
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

  group('footnote and "Read from here"', () {
    testWidgets('a footnote mark opens it over the page (FR-R3)', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      final page = reader(tester).page;
      await tester.tapAt(noteRefCenter(tester, 'n1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsOneWidget);
      expect(find.textContaining('Хвастун'), findsOneWidget);
      expect(reader(tester).page, page);
    });

    testWidgets('a long press on a paragraph → "Read from here" starts from it (FR-P3)', (tester) async {
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

  group('narration on the reading screen', () {
    testWidgets('"Listen" → player panel, highlight of the sounding paragraph, the page follows the voice (FR-P4)',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0));
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.state, NarrationState.playing);
      expect(find.byKey(const Key('player-panel')), findsOneWidget);
      final block = p.narration.block!;
      expect(find.byKey(ValueKey('hl-$block-0')), findsOneWidget);
      final startPage = reader(tester).page;
      // The voice moves ahead and the page turns by itself to follow it.
      var guard = 0;
      while (reader(tester).page == startPage && guard++ < 300) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(reader(tester).page, greaterThan(startPage));
      final st = reader(tester);
      final at = st.soundingPosition!;
      expect(st.layout.pages[st.page].contains(at.block, at.offset), isTrue,
          reason: 'the sounding place (block and offset) is on screen, not just the same block');
    });

    testWidgets('turning pages myself → following is off, "To current spot" brings it back', (tester) async {
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
      expect(p.narration.state, NarrationState.playing, reason: 'the voice is not interrupted');
      await tester.tap(find.byKey(const Key('to-reading-place')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      expect(reader(tester).page, listening);
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });

    testWidgets('pause, forward/back, speed, sleep timer, "Close"', (tester) async {
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
      expect(p.narration.state, NarrationState.paused, reason: '"forward" from pause leaves it paused (A§6.6)');
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
          reason: '"Close" while following: the position is the sounding place on screen (FR-P8, FR-P3)');
      // The panel is gone, the page got longer and was recomputed from the same place: it is on screen.
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
      testWidgets('player state "$state" is named in words in the panel itself (FR-P6)', (tester) async {
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

    testWidgets('after an error "Listen" starts a new session from the same place', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
      // The error panel is a new layer: taps in the first 350 ms are ignored (protection against a follow-up tap).
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('error-listen')));
      await tester.pump();
      expect(p.narration.state, NarrationState.preparing);
      expect(p.narration.block, 39);
    });

    testWidgets('without a key "Listen" leads to settings, to the key field (FR-P7)', (tester) async {
      final p = await pumpPrototype(tester);
      p.settings.apiKey = null;
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('key-field')), findsOneWidget);
      expect(p.narration.state, NarrationState.idle);
    });

    testWidgets('the voice screen pauses; the probe plays; choosing the book voice (FR-V1, FR-V2)', (tester) async {
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
      expect(p.sampler.voice, isNull, reason: 'the probe finished playing');
      await tester.tap(find.byKey(const Key('voice-Kore')));
      await tester.pump();
      expect(p.library.bookVoice('kapitanskaya'), 'Kore');
      expect(p.settings.voice, 'Aoede', reason: 'the app voice does not change');
    });

    testWidgets('the "Download chapter" row on the reading screen and "Stop" (FR-D2)', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final book = currentBook(tester);
      p.downloads.demoShow(book, 1, failed: false);
      // The download row is a new layer: taps in the first 350 ms are ignored (protection against a follow-up tap).
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('download-strip')), findsOneWidget);
      await tester.tap(find.text('Стоп'));
      await advance(tester, const Duration(milliseconds: 400));
      expect(find.byKey(const Key('download-strip')), findsNothing);
      expect(p.downloads.task, isNull);
    });
  });

  group('shelf and settings', () {
    testWidgets('deleting a book: menu → confirmation with the size → the book is gone (FR-L5)', (tester) async {
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

    testWidgets('"Clear narration" with confirmation resets the space (FR-M3)', (tester) async {
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

    testWidgets('shelf: a finished book shows "100 %", an unopened one shows "new" (FR-L4)', (tester) async {
      await pumpPrototype(tester);
      expect(find.text('100 %'), findsOneWidget);
      expect(find.text('новая'), findsOneWidget);
      expect(find.text('прочитана'), findsNothing);
    });

    testWidgets('adding: the "Adding…" row, then the book on the shelf; a rejection stays until "✕"', (tester) async {
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

    testWidgets('"Demo states" open with a long press on the shelf title', (tester) async {
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
