// User journeys “reading × listening”: sequences of two to four actions.
// The expectation of each test comes from the reader and from the spec/architecture; a failing test proves a defect.

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
  group('table of contents while listening', () {
    testWidgets('turned pages myself → table of contents → another chapter: the voice and the page are in the new '
        'chapter, following is on',
        (tester) async {
      // А§5: following is turned off "until “To current spot” is pressed or until a new start"; changing the chapter in
      // the table of contents is a new start (А§5, А§6.4). The reader expects the pages to follow the voice again from
      // then on.
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isFalse, reason: 'precondition: the reader turned the pages himself');

      await tapCenter(tester);
      await chooseChapter(tester, 'Глава III. Крепость');

      final st = reader(tester);
      final book = st.widget.book;
      expect(p.narration.block, book.chapters[2].firstBlock, reason: 'the voice moved to the start of the chapter');
      expect(st.layout.pages[st.page].chapter, 2, reason: 'the page is in the chosen chapter');
      expect(st.following, isTrue, reason: 'a chapter change is a new start: following is on again');
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });
  });

  group('sleep timer', () {
    testWidgets('timer 15 min → “Close” → three hours later “Listen”: audio plays and does not pause',
        (tester) async {
      // “Close” ends listening (FR-P8). A timer set yesterday evening must not stop
      // today's listening a fraction of a second later.
      final clock = TestClock();
      final p = await pumpWithClock(tester, clock);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('sleep-15')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer?.minutes, 15, reason: 'precondition');

      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 500));
      clock.forward(const Duration(hours: 3));

      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.state, NarrationState.playing, reason: 'new listening does not get stopped by the old timer');
      expect(find.text(ru.minutesShort(0)), findsNothing, reason: 'the panel has no “0 min” timer');
    });

    testWidgets('the timer expired during a pause → “Listen”: audio continues', (tester) async {
      // The timer is a "pause by time" (А§6.6). If a pause is already in place by its deadline, there is nothing for it
      // to stop; “Listen” pressed afterwards continues from the pause position (FR-P3) and does not pause again after
      // 0.1 s.
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
      expect(p.narration.state, NarrationState.paused, reason: 'precondition');

      clock.forward(const Duration(minutes: 20));
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.state, NarrationState.playing);
    });
  });

  group('“Preparing the voice…” and “Waiting for connection…”', () {
    testWidgets('“Waiting for connection…” → turning pages myself: “To current spot” and the voice chip are '
        'visible', (tester) async {
      // FR-P4: "The “To current spot” button is visible when following is off" — with no exception for
      // waiting/preparing. FR-V2: the “Voice” entry is on the player panel. “Waiting for connection…” can last long (no
      // network).
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.demoShow('waiting');
      await advance(tester, const Duration(milliseconds: 400));
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isFalse, reason: 'precondition: following is off');
      expect(p.narration.state, NarrationState.waiting);
      expect(find.byKey(const Key('to-reading-place')), findsOneWidget,
          reason: 'returning to the reading position is possible even while the voice waits for a connection');
      expect(find.byKey(const Key('voice-chip')), findsOneWidget);
    });
  });

  group('error 404 → “Choose model”', () {
    testWidgets('chose another model and came back: the panel does not call the just-chosen one '
        'unavailable', (tester) async {
      // FR-P7: “Choose model”, from settings “Back” goes to the same book. 3.8 Flash was the unavailable one; after
      // choosing Flash-Lite the panel must not claim that Flash-Lite is unavailable.
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('error404', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.text(ru.error404Title('3.8 Flash')), findsOneWidget, reason: 'precondition');

      await tester.tap(find.byKey(const Key('choose-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-flashLite')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.text(ru.error404Title('3.8 Flash-Lite')), findsNothing,
          reason: 'the panel says the model the reader has just chosen is unavailable');
    });
  });

  group('page re-layout while the audio is stopped', () {
    testWidgets('pause on a paragraph at the bottom of the page → larger font: the listening position is on '
        'screen', (tester) async {
      // А§5: while listening is active (a pause too), the position is the controller position; following is on, so
      // the screen shows the page with it. FR-R6/FR-R7: a font change does not lose the position.
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
      expect(p.narration.state, NarrationState.paused, reason: 'precondition');
      expect(p.narration.block, block);
      expect(onScreen(tester, block, 0), isTrue, reason: 'precondition: the position is on screen');

      await tapCenter(tester);
      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('font-larger')));
        await tester.pumpAndSettle();
      }
      expect(p.settings.fontStep, defaultFontStep + 3);
      expect(reader(tester).following, isTrue);
      expect(onScreen(tester, block, 0), isTrue, reason: 'after the font change the screen shows the paragraph that '
          'was playing (paused)');
    });

    testWidgets('pause on a paragraph at the bottom of the page → error 402: the stop position is on '
        'screen', (tester) async {
      // А§5: "On entering stopped the screen first shows the page with the saved position". The error panel is taller
      // than the player panel — the page becomes shorter, but the stop position must stay on screen.
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
      expect(onScreen(tester, block, 0), isTrue, reason: 'precondition');

      p.narration.demoShow('error402');
      await tester.pumpAndSettle();
      expect(p.narration.state, NarrationState.stopped);
      expect(p.library.positionOf('kapitanskaya')!.block, block, reason: 'the saved position is the stop position');
      expect(onScreen(tester, block, 0), isTrue, reason: 'the screen shows the page with the saved position');
    });
  });

  group('the “Voice” screen', () {
    testWidgets('pause → “Voice” → tapping an already selected row: the position inside the paragraph is not '
        'lost', (tester) async {
      // FR-V2/А§6.4: a new session starts on a voice CHANGE. Tapping a row that is already selected does not change the
      // voice — “Listen” after returning continues from the pause position (FR-P3).
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 4));
      await tester.tap(find.byKey(const Key('voice-chip')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(p.narration.state, NarrationState.paused);
      final block = p.narration.block;
      final progress = p.narration.blockProgress;
      expect(progress, greaterThan(0.05), reason: 'precondition: the pause is inside a paragraph');

      await tester.tap(find.text('Как в настройках'));
      await advance(tester, const Duration(milliseconds: 400));
      expect(p.library.bookVoice('kapitanskaya'), isNull, reason: 'the voice did not change');
      expect(p.narration.block, block);
      expect(p.narration.blockProgress, closeTo(progress, 0.001), reason: 'the pause position is the same');
    });
  });

  group('selecting a paragraph during audio', () {
    testWidgets('a long press on a paragraph right before a page turn: “Read from here” does not move away with the '
        'page',
        (tester) async {
      // FR-P3: "long press on a paragraph → “Read from here”". While the reader chooses a position, the page under the
      // finger must not move away: otherwise the button disappears before it is pressed.
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
      expect(find.byKey(const Key('read-from-here')), findsOneWidget, reason: 'precondition: the button is shown');
      await advance(tester, const Duration(seconds: 8));
      expect(p.narration.block, isNot(block), reason: 'precondition: the voice moved on');
      expect(find.byKey(const Key('read-from-here')), findsOneWidget, reason: 'the button waits for a press');
      expect(st.page, page0, reason: 'the page with the selected paragraph stayed on screen');
    });
  });

  group('the system Back', () {
    testWidgets('a paragraph is selected (“Read from here”) while listening → Back: the selection is cleared, the book '
        'and the audio stay',
        (tester) async {
      // Prototype README: the paragraph selection is cancelled by a "tap elsewhere". On Android the system Back first
      // removes the temporary selection mode and does not close the screen under it; closing the book here interrupts
      // listening (А§8.1).
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final block = wholeParagraphOnPage(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('read-from-here')), findsOneWidget, reason: 'precondition');

      await tester.binding.handlePopRoute();
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byType(ReaderScreen), findsOneWidget, reason: 'the book is not closed');
      expect(p.narration.state, NarrationState.playing, reason: 'listening is not interrupted');
      expect(find.byKey(const Key('read-from-here')), findsNothing, reason: 'the paragraph selection is cleared');
    });
  });

  group('paths that are fine (not covered by the earlier tests)', () {
    testWidgets('changing the interface language while listening: the page, the player and the sheet stay in '
        'place', (tester) async {
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
      expect(find.byKey(const Key('demo-lang-en')), findsOneWidget, reason: 'the sheet did not close');
      expect(p.settings.language, 'en');
      expect(find.byTooltip('Next paragraph'), findsOneWidget, reason: 'the player panel is already in English');
      expect(p.narration.state, NarrationState.playing);
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect((reader(tester).page - page).abs(), lessThanOrEqualTo(1), reason: 'the position is the same (or the page '
          'follows the voice)');
      final at = reader(tester).soundingPosition!;
      expect(onScreen(tester, at.block, at.offset), isTrue);
    });

    testWidgets('listened to the end of the book: “End of the book”, the last page is on screen; “Close” does not move '
        'it',
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
      expect(onScreen(tester, last, book.blocks[last].text.length - 1), isTrue, reason: 'the end of the book is on '
          'screen');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.narration.state, NarrationState.idle);
      expect(onScreen(tester, last, book.blocks[last].text.length - 1), isTrue, reason: 'the page did not move away');
    });

    testWidgets('no key → “Listen” → key → “Back”: the same book and page, narration did not start by itself (FR-P7)',
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
      expect(p.narration.state, NarrationState.playing, reason: 'with the second “Listen” narration plays');
    });
  });

  group('re-layout when the player panel appears', () {
    testWidgets('“Read from here” on a paragraph at the bottom of the page (without listening): while “Preparing the '
        'voice…”, the paragraph is on screen',
        (tester) async {
      // FR-P3/А§5: “Read from here” starts from the selected paragraph, following is on — the screen shows the position
      // from which the voice will start. The player panel appears and shortens the page; the paragraph must not leave
      // the screen.
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      final block = lowestStartingParagraph(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('read-from-here')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.narration.state, NarrationState.preparing, reason: 'precondition: the voice is still being prepared');
      expect(p.narration.block, block);
      expect(onScreen(tester, block, 0), isTrue, reason: 'the selected paragraph is on screen');
    });
  });
}
