// Decisions A–J of the gesture review of 2026-11-14 (docs/reviews/GESTURE_AUDIT_2026-11-14.md) and the paths the
// reviewer did not cover: a second finger during a page flip, scrolling the table of contents, a dialog under the
// system Back, a language change while a sheet is open. The reviewer findings are in gesture_*_test.dart.

import 'dart:math' as math;

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

/// The same two adjacent notes as in gesture_page_test.dart.
Book twoNotesBookForDecisions() {
  const lead = 'Так об этом писали оба автора';
  const text = '${lead}1,2 и спорить с ними никто не стал. Дальше идёт обычный текст абзаца, в котором сносок нет.';
  return Book(
    id: 'synthetic-two-notes',
    title: 'Две сноски',
    author: 'Проверка',
    language: 'ru',
    chapters: const [Chapter(title: 'Глава', level: 1, firstBlock: 0, blockCount: 1)],
    blocks: [
      Block(index: 0, kind: BlockKind.paragraph, text: text, spans: [
        TextSpanRange(start: lead.length, end: lead.length + 1, style: SpanStyle.noteRef, noteId: 'a'),
        TextSpanRange(start: lead.length + 2, end: lead.length + 3, style: SpanStyle.noteRef, noteId: 'b'),
      ]),
    ],
    notes: const {
      'a': Note(id: 'a', blocks: [Block(index: 0, kind: BlockKind.paragraph, text: 'Первая сноска.')]),
      'b': Note(id: 'b', blocks: [Block(index: 0, kind: BlockKind.paragraph, text: 'Вторая сноска.')]),
    },
  );
}

void main() {
  group('A. follow-up tap', () {
    test('the threshold is a named constant, 350 ms', () {
      expect(layerSettleTime, const Duration(milliseconds: 350));
    });

    testWidgets('normal pace: “Listen”, then “Pause” after 400 ms — pause is pressed', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      await quickTap(tester, tester.getCenter(find.byKey(const Key('listen'))));
      await frames(tester, 400);
      await quickTap(tester, tester.getCenter(find.byKey(const Key('play-pause'))));
      await frames(tester, 100);
      expect(p.narration.state, NarrationState.paused, reason: 'a second press after 400 ms is deliberate, it works');
    });

    testWidgets('the speed sheet is opened by a double tap: the second tap neither picks a speed nor closes the sheet',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      final c = tester.getCenter(find.byKey(const Key('speed')));
      await quickTap(tester, c);
      await frames(tester, 200);
      await quickTap(tester, c);
      await frames(tester, 400);
      expect(find.byKey(const Key('speed-1.0')), findsOneWidget, reason: 'the sheet is open');
      expect(p.narration.speed, 1);
      // After 350 ms the sheet works as usual.
      await tester.tap(find.byKey(const Key('speed-1.5')));
      await tester.pumpAndSettle();
      expect(p.narration.speed, 1.5);
    });

    testWidgets('after the sheet is closed: a tap after 400 ms reaches the player panel', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 600));
      await quickTap(tester, tester.getCenter(find.byKey(const Key('sleep-15'))));
      await frames(tester, 450);
      await quickTap(tester, tester.getCenter(find.byKey(const Key('play-pause'))));
      await frames(tester, 100);
      expect(p.narration.sleepTimer?.minutes, 15);
      expect(p.narration.state, NarrationState.paused);
    });
  });

  group('B. the paragraph selection is cleared when the page changes', () {
    testWidgets('picked a paragraph → swiped back: no selection and no highlight', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      final block = wholeParagraphOnPage(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('hl-$block-0')), findsOneWidget, reason: 'precondition');
      await swipe(tester, at(tester, 0.15, 0.5), const Offset(220, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, start - 1);
      await jumpTo(tester, start);
      expect(find.byKey(const Key('read-from-here')), findsNothing);
      expect(find.byKey(ValueKey('hl-$block-0')), findsNothing, reason: 'returned to the page — no selection');
    });
  });

  group('C. a finger during an automatic page turn', () {
    testWidgets('outside an auto turn: a small drag with a return does not turn following off', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      final f = await Finger.down(tester, at(tester, 0.6, 0.4));
      await f.move(const Offset(-40, 0), ms: 120);
      await f.move(const Offset(40, 0), ms: 120);
      // The finger stopped — without fling velocity the page settles back in place.
      await f.hold(300);
      await f.up();
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      expect(p.narration.state, NarrationState.playing);
    });
  });

  group('D. only a mostly horizontal gesture flips the page', () {
    for (final (deg, flips) in const [(10, true), (30, true), (44, true), (46, false), (60, false), (80, false)]) {
      testWidgets('a left-up swipe at $deg° to the horizontal: ${flips ? 'flips' : 'does not flip'}', (tester) async {
        final p = await pumpPrototype(tester);
        await openKapitanskaya(tester, p);
        final start = await gotoPlainPage(tester);
        final a = deg * math.pi / 180;
        const length = 240.0;
        await swipe(tester, at(tester, 0.75, 0.7), Offset(-length * math.cos(a), -length * math.sin(a)), ms: 110);
        await tester.pumpAndSettle();
        expect(reader(tester).page, flips ? start + 1 : start);
        expect(reader(tester).panelsVisible, isFalse, reason: 'a vertical gesture does nothing');
      });
    }
  });

  group('E. the key is saved when leaving the field and the screen', () {
    Future<void> openKeyField(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('key-change')));
      await tester.pumpAndSettle();
    }

    testWidgets('the Back arrow of the settings screen: the entered key is saved', (tester) async {
      final p = await pumpPrototype(tester);
      await openKeyField(tester);
      await tester.enterText(find.byKey(const Key('key-field')), 'AIzaSyD-new-key-1234');
      await tester.pump();
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(p.settings.apiKeyTail, '1234');
    });

    testWidgets('left the field by tapping another item: the key is saved, the field is closed', (tester) async {
      final p = await pumpPrototype(tester);
      await openKeyField(tester);
      await tester.enterText(find.byKey(const Key('key-field')), 'AIzaSyD-new-key-5678');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(p.settings.apiKeyTail, '5678');
      expect(find.byKey(const Key('key-field')), findsNothing);
    });

    testWidgets('an empty field and Back: the previous key is untouched', (tester) async {
      final p = await pumpPrototype(tester);
      final before = p.settings.apiKeyTail;
      await openKeyField(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(p.settings.hasApiKey, isTrue);
      expect(p.settings.apiKeyTail, before);
    });
  });

  group('G. the nearest note marker', () {
    testWidgets('two markers next to each other: tapping the first opens the first note', (tester) async {
      final p = await pumpPrototype(tester);
      await openSynthetic(tester, p, twoNotesBookForDecisions());
      await tester.tapAt(noteRefCenter(tester, 'a'));
      await tester.pumpAndSettle();
      expect(find.text('Первая сноска.'), findsOneWidget);
    });
  });

  group('J. the system Back while reading', () {
    testWidgets('listening, panels hidden: Back shows the header and slider, audio keeps playing; the second one '
        'closes the book',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      expect(reader(tester).panelsVisible, isFalse);
      await tester.binding.handlePopRoute();
      await advance(tester, const Duration(milliseconds: 500));
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(reader(tester).panelsVisible, isTrue);
      expect(find.byKey(const Key('book-slider')), findsOneWidget, reason: 'the slider is above the player panel');
      expect(p.narration.state, NarrationState.playing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(p.narration.state, NarrationState.idle);
    });

    testWidgets('the Back arrow in the header closes the book at once', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(p.library.shelf.first.id, 'kapitanskaya');
    });
  });

  group('paths the reviewer did not cover', () {
    testWidgets('a second finger during a swipe: one page, no exceptions', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      final first = await Finger.down(tester, at(tester, 0.8, 0.5));
      await first.move(const Offset(-80, 0), ms: 80);
      final second = await Finger.down(tester, at(tester, 0.3, 0.3), pointer: 2);
      await first.move(const Offset(-140, 0), ms: 80);
      await second.move(const Offset(-60, 0), ms: 60);
      await second.up();
      await first.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(reader(tester).page, inInclusiveRange(start, start + 1), reason: 'no more than one page per gesture');
    });

    testWidgets('table of contents: scrolling by finger and tapping a chapter opens that chapter', (tester) async {
      final p = await pumpPrototype(tester);
      await openDama(tester, p);
      final book = currentBook(tester);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      final last = book.chapters.length - 1;
      final title = find.text(book.chapters[last].title).last;
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(reader(tester).layout.pages[reader(tester).page].chapter, last);
    });

    testWidgets('the delete-book dialog under the system Back: the dialog is closed, the book stays on the '
        'shelf', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.longPress(find.text('Записки охотника'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить книгу'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-delete')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-delete')), findsNothing);
      expect(p.library.shelf.any((e) => e.id == 'zapiski'), isTrue);
      expect(find.byKey(const Key('shelf-title')), findsOneWidget);
    });

    testWidgets('a language change while the “Text appearance” sheet is open: the sheet stays open and is already in '
        'the new language', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appearance-sheet')), findsOneWidget);
      p.settings.language = 'en';
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('appearance-sheet')), findsOneWidget);
      expect(find.text('Text appearance'), findsOneWidget);
    });
  });
}
