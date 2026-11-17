// Rules a–k (accepted by the owner on 2026-11-14) for the gaps in the documents found by the user-journey review of
// 2026-11-14 (docs/reviews/JOURNEY_AUDIT_2026-11-14.md), and two hypotheses the reviewer did not verify. The reviewer
// findings are in journey_listening_test.dart, journey_shelf_test.dart, journey_download_test.dart.

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:audiobook_reader/screens/settings_screen.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'journey_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

Future<void> flingNext(WidgetTester tester) async {
  await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
  await advance(tester, const Duration(milliseconds: 800));
}

Future<void> toShelf(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byTooltip('Назад'));
  await tester.pumpAndSettle();
  await settle(tester);
}

void main() {
  group('page turning', () {
    testWidgets('a second tap on the right third 40 ms after the first is not lost: +2 pages', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = reader(tester).page;
      final size = tester.getSize(find.byKey(const Key('page-area')));
      await tester.tapAt(Offset(size.width * 0.9, size.height / 2));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(Offset(size.width * 0.9, size.height / 2));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 2);
    });
  });

  group('speed (FR-P5)', () {
    testWidgets('a saved speed of 1.5× — listening starts with it at once', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      p.settings.speed = 1.5;
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      expect(p.narration.speed, 1.5);
      expect(find.text('1,5×'), findsOneWidget);
      // Not only the label: the voice also moves at speed 1.5 (item 8 of the logic review).
      final block = p.narration.block!;
      final before = p.narration.blockProgress;
      await advance(tester, const Duration(milliseconds: 500));
      if (p.narration.block == block) {
        final seconds = currentBook(tester).blocks[block].text.length * secondsPerChar / 1.5;
        expect(p.narration.blockProgress - before, closeTo(0.5 / (seconds < 1.6 ? 1.6 : seconds), 0.003));
      }
    });
  });

  group('a. following is turned on by actions that change the audio position', () {
    Future<void> listeningFlipped(WidgetTester tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      expect(reader(tester).following, isFalse, reason: 'precondition: turned the pages myself');
    }

    testWidgets('turned pages myself → “forward”: following is on', (tester) async {
      await listeningFlipped(tester);
      await tester.tap(find.byKey(const Key('next')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      final at = reader(tester).soundingPosition!;
      expect(onScreen(tester, at.block, at.offset), isTrue);
    });

    testWidgets('turned pages myself → “back”: following is on', (tester) async {
      await listeningFlipped(tester);
      await tester.tap(find.byKey(const Key('previous')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
    });

    testWidgets('pause → turned pages myself → “Listen” on the panel: following is on', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 300));
      await flingNext(tester);
      expect(reader(tester).following, isFalse, reason: 'precondition');
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(p.narration.state, NarrationState.playing);
      expect(reader(tester).following, isTrue);
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });

    testWidgets('error → turned pages myself → “Listen” in the error panel: following is on', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      p.narration.demoShow('error402');
      await advance(tester, const Duration(milliseconds: 600));
      await flingNext(tester);
      // Not vacuous: turning pages with the error panel open turned following off (item 1 of the logic review).
      expect(reader(tester).following, isFalse, reason: 'precondition: turned pages myself after the stop');
      await tester.tap(find.byKey(const Key('error-listen')));
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.isActive, isTrue);
      expect(reader(tester).following, isTrue);
      final at = reader(tester).soundingPosition!;
      expect(onScreen(tester, at.block, at.offset), isTrue, reason: 'the screen returned to the voice');
    });

    testWidgets('table of contents while listening: the same chapter — the voice goes to its start', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final book = currentBook(tester);
      final chapter = book.chapterOf(p.narration.block!);
      await tapCenter(tester);
      await chooseChapter(tester, book.chapters[chapter].title);
      expect(p.narration.block, greaterThanOrEqualTo(book.chapters[chapter].firstBlock));
      expect(p.narration.block, lessThan(book.chapters[chapter].firstBlock + 3), reason: 'the voice is at the start of '
          'the chapter');
      expect(reader(tester).following, isTrue);
    });
  });

  group('b. re-layout without following', () {
    testWidgets('turned pages myself during audio → larger font: the screen keeps the previous page start, not the '
        'voice position',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      await flingNext(tester);
      final st = reader(tester);
      final shown = st.layout.pages[st.page];
      final top = ReadingPosition(shown.firstBlock, shown.firstOffset);
      st.widget.services.settings.fontStep = st.widget.services.settings.fontStep + 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(reader(tester).following, isFalse);
      expect(onScreen(tester, top.block, top.offset), isTrue);
      expect(p.narration.state, NarrationState.playing);
    });
  });

  group('c. sleep timer', () {
    testWidgets('going back to the shelf clears the timer; back into the book — “Listen” without a '
        'timer', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('sleep-30')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer, isNotNull);
      await toShelf(tester);
      expect(p.narration.sleepTimer, isNull);
      // Back into the book and “Listen”: audio plays, the panel has no timer.
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 1));
      expect(p.narration.state, NarrationState.playing);
      expect(p.narration.sleepTimer, isNull);
      expect(find.byIcon(Icons.bedtime_rounded), findsNothing, reason: 'the active-timer icon is not lit');
    });

    testWidgets('“until the end of the chapter” from the sheet: pause on the first paragraph of the next chapter, the '
        'timer is cleared', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p);
      final book = currentBook(tester);
      final chapter = book.chapterOf(39);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('sleep-chapter')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer?.kind, SleepKind.endOfChapter);
      var guard = 0;
      while (p.narration.state != NarrationState.paused && guard++ < 1200) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(p.narration.state, NarrationState.paused);
      expect(book.chapterOf(p.narration.block!), chapter + 1, reason: 'stopped at the start of the next chapter');
      expect(p.narration.sleepTimer, isNull);
    });

    testWidgets('the time ran out in “Waiting for connection…” — pause, the timer is cleared', (tester) async {
      final clock = TestClock();
      final p = await pumpWithClock(tester, clock);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.setSleepTimer(SleepTimer.minutes(15, p.narration.now()));
      p.narration.demoShow('waiting');
      await advance(tester, const Duration(milliseconds: 300));
      clock.forward(const Duration(minutes: 16));
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.state, NarrationState.paused);
      expect(p.narration.sleepTimer, isNull);
    });

    testWidgets('changing position in the same book (“forward”) does not clear the timer; changing the book '
        'does', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.setSleepTimer(SleepTimer.minutes(30, p.narration.now()));
      await tester.tap(find.byKey(const Key('next')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer?.minutes, 30);
      final dama = await p.library.loadBook('dama');
      p.narration.readFrom(dama, 40);
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.bookId, 'dama');
      expect(p.narration.sleepTimer, isNull);
    });

    testWidgets('the time ran out in “Preparing the voice…” — pause, the timer is cleared', (tester) async {
      final clock = TestClock();
      final p = await pumpWithClock(tester, clock);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.setSleepTimer(SleepTimer.minutes(15, p.narration.now()));
      p.narration.demoShow('preparing');
      await advance(tester, const Duration(milliseconds: 300));
      clock.forward(const Duration(minutes: 16));
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.state, NarrationState.paused);
      expect(p.narration.sleepTimer, isNull);
    });
  });

  group('d. a finished book', () {
    testWidgets('listened to the end → “Close” → shelf: 100 %; back two pages → not 100 %', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p, at: const ReadingPosition(99, 0));
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 10));
      expect(p.narration.stopReason, StopReason.endOfBook, reason: 'precondition');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), shelfProgress(ru, 1));
      await toShelf(tester);
      expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), shelfProgress(ru, 1));
      await openKapitanskaya(tester, p);
      await tapLeftThird(tester);
      await tapLeftThird(tester);
      await toShelf(tester);
      expect(p.library.entry('kapitanskaya').fraction, lessThan(1));
    });
  });

  group('e. shelf', () {
    testWidgets('never-opened books come first under the card, newest on top', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Добавить книгу'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-ok')));
      await advance(tester, const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final belkin = tester.getTopLeft(find.text('Повести Белкина')).dy;
      final voyna = tester.getTopLeft(find.text('Война и мир')).dy;
      final dama = tester.getTopLeft(find.text('Дама с собачкой. Рассказы')).dy;
      final card = tester.getTopLeft(find.text('Капитанская дочка')).dy;
      expect(card < belkin && belkin < voyna && voyna < dama, isTrue,
          reason: 'the card → the new “Повести Белкина” → the unopened “Война и мир” → the ones opened before');
      expect(p.library.entry('belkin').opened, isFalse);
    });
  });

  group('f. the system Back', () {
    // Rule f is replaced by decision J of the gesture review of 2026-11-14 (the Android edge gesture is Back): panels
    // hidden — Back shows them; shown — closes the book. It used to be: "panels open → hides them; the second one
    // closes".
    testWidgets('panels hidden → Back shows the panels; panels shown → Back closes the book', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      expect(reader(tester).panelsVisible, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget, reason: 'an accidental edge gesture does not close the book');
      expect(reader(tester).panelsVisible, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
    });
  });

  group('g. “Download chapter”', () {
    Future<void> openToc(WidgetTester tester) async {
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await tester.pumpAndSettle();
    }

    testWidgets('downloading chapter II is in progress, the reader moved to chapter III: the progress block is at '
        'chapter II, there is no offer',
        (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await openToc(tester);
      await tester.tap(find.byKey(const Key('download-start')));
      await advance(tester, const Duration(seconds: 2));
      await tester.tap(find.text('Глава III. Крепость'));
      await tester.pumpAndSettle();
      expect(reader(tester).layout.pages[reader(tester).page].chapter, 2);
      await openToc(tester);
      expect(find.byKey(const Key('download-stop')), findsOneWidget, reason: 'the task progress is visible');
      expect(find.byKey(const Key('download-start')), findsNothing, reason: 'while a task is running, a second one is '
          'not offered');
      final stop = tester.getTopLeft(find.byKey(const Key('download-stop'))).dy;
      expect(stop, greaterThan(tester.getTopLeft(find.text('Глава II. Вожатый')).dy));
      expect(stop, lessThan(tester.getTopLeft(find.text('Глава III. Крепость')).dy), reason: 'the block is at chapter '
          'II');
    });

    testWidgets('changing the book voice stops the task; the current chapter gets an offer with a new estimate',
        (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await openToc(tester);
      await tester.tap(find.byKey(const Key('download-start')));
      await advance(tester, const Duration(seconds: 10));
      expect(p.downloads.task!.fraction, greaterThan(0.1), reason: 'precondition: part of the chapter is ready');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final book = currentBook(tester);
      final chapter = book.chapterOf(39);
      final remainder = p.downloads.estimate(book, chapter, p.downloads.profileFor('kapitanskaya')).seconds;
      // The panels are still open after the table of contents.
      await tester.tap(find.byKey(const Key('voice-chip-idle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voice-Kore')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(p.downloads.task, isNull, reason: 'the task of the previous voice is stopped');
      final kore = p.downloads.estimate(book, chapter, p.downloads.profileFor('kapitanskaya')).seconds;
      expect(kore, greaterThan(remainder), reason: 'for the new voice the estimate is the whole chapter, not the '
          'remainder of the previous one');
      await tester.tap(find.byTooltip('Оглавление'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('download-start')), findsOneWidget);
    });
  });

  group('h. wrong key', () {
    testWidgets('a key failure: an explanation, “Change key” → the key field; “Back” — into the book', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('errorKey', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.text(ru.errorKeyTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('change-key')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byKey(const Key('key-field')), findsOneWidget, reason: 'the key field is open although the key is '
          'saved');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(p.settings.hasApiKey, isTrue);
    });
  });

  group('i. “End of the book”', () {
    testWidgets('the panel has only “Close”', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('end', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.text(ru.endOfBook), findsOneWidget);
      expect(find.byKey(const Key('player-close')), findsOneWidget);
      for (final k in ['play-pause', 'next', 'previous', 'error-listen', 'voice-chip']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });
  });

  group('j. tapping an already selected item', () {
    testWidgets('pause → settings → model → the same model: the pause position is not reset', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 3));
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 300));
      final block = p.narration.block;
      final progress = p.narration.blockProgress;
      expect(progress, greaterThan(0.05), reason: 'precondition');
      tester.state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(services: p.services)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-flash')));
      await tester.pumpAndSettle();
      expect(p.narration.block, block);
      expect(p.narration.blockProgress, closeTo(progress, 0.001));
    });
  });

  group('k. “Preparing the voice…”', () {
    testWidgets('“Preparing the voice…” + turned pages myself: the label on its own row, the voice chip and “To '
        'current spot”',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.demoShow('preparing');
      await advance(tester, const Duration(milliseconds: 400));
      await flingNext(tester);
      expect(find.byKey(const Key('player-status')), findsOneWidget);
      expect(find.text(ru.preparing), findsOneWidget);
      expect(find.byKey(const Key('voice-chip')), findsOneWidget);
      expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
      await tester.tap(find.byKey(const Key('to-reading-place')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
    });
  });
}
