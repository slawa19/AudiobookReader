// Gestures while listening and while paused (sections D and G of the gesture review of 2026-11-14).

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
  testWidgets('fast “forward” ×3 and “pause/listen” ×4 by finger: the position is the third next paragraph, audio '
      'plays, the screen follows',
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

  testWidgets('“Read from here” on the lower half of a paragraph split by a page: audio starts from the paragraph '
      'start, the screen goes to '
      'the voice, there is no “To current spot” (FR-P3)', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    final st = reader(tester);
    final book = currentBook(tester);
    // A page that starts with the continuation of a paragraph.
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
        reason: 'the paragraph start is on the previous page: the screen moves to the voice');
    expect(find.byKey(ValueKey('hl-${f.block}-0')), findsOneWidget);
  });

  testWidgets('a long press in the middle of an automatic turn after the voice: the selected paragraph is on the page '
      'that '
      'stayed on screen; a tap elsewhere — the screen catches up with the voice', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 40);
    await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0));
    await startListening(tester);
    expect(p.narration.state, NarrationState.playing);
    // Wait for the middle of the automatic turn.
    var guard = 0;
    while ((scrollPage(tester) - scrollPage(tester).round()).abs() < 0.15 && guard++ < 4000) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(guard, lessThan(4000), reason: 'precondition: the middle of the turn is caught');

    final f = await Finger.down(tester, at(tester, 0.5, 0.3));
    await f.hold(700);
    await f.up();
    await frames(tester, 400);
    expect(tester.takeException(), isNull);
    final settled = scrollPage(tester);
    expect((settled - settled.round()).abs(), lessThan(0.001), reason: 'the page does not hang between two');
    expect(settled.round(), reader(tester).page);
    final button = find.byKey(const Key('read-from-here'));
    if (button.evaluate().isNotEmpty) {
      // The paragraph is selected: it must be on the visible page, and the button within the screen.
      expect(button.hitTestable(), findsOneWidget);
    }
    // A tap elsewhere clears the selection; the screen follows the voice.
    await tester.tapAt(at(tester, 0.5, 0.12));
    await advance(tester, const Duration(milliseconds: 900));
    expect(find.byKey(const Key('read-from-here')), findsNothing);
    expect(reader(tester).following, isTrue);
    expect(onPage(tester, reader(tester).soundingPosition!), isTrue);
  });

  testWidgets('the page moved after the voice and a finger put it back: the finger wins — the page stays, following is '
      'off', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 40);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    // Wait for the start of the automatic turn (its first third): the reader is still finishing the page.
    var guard = 0;
    double frac() => scrollPage(tester) - scrollPage(tester).floor();
    while (!(frac() > 0.1 && frac() < 0.45) && guard++ < 6000) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(guard, lessThan(6000), reason: 'precondition: the automatic turn is caught');
    final from = scrollPage(tester).floor();
    expect(reader(tester).page, from, reason: 'precondition: half of the turn is not passed');
    // The finger grabs the page and returns it exactly to its place: by as much as it had managed to move.
    final width = pageRect(tester).width;
    final f = await Finger.down(tester, at(tester, 0.3, 0.3));
    await f.move(Offset(frac() * width + 12, 0), ms: 180);
    await f.hold(120);
    expect(scrollPage(tester), closeTo(from.toDouble(), 0.06), reason: 'precondition: the previous page is under the '
        'finger again');
    await f.up();
    // Prototype README, “Gestures”: “the finger wins: the turn is cancelled, following the voice is turned off”.
    await advance(tester, const Duration(seconds: 2));
    expect(reader(tester).page, from, reason: 'a page the reader held does not move after the voice again');
    expect(reader(tester).following, isFalse);
    expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
  });

  testWidgets('dragging the slider at the moment the book ends: no exceptions, after release the selected position',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 400);
    await openKapitanskaya(tester, p);
    final st = reader(tester);
    final book = currentBook(tester);
    // Go to the page before the last and listen to the end of the book.
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
    expect(p.narration.state, NarrationState.stopped, reason: 'precondition: the book ended while the finger is on the '
        'slider');
    expect(p.narration.stopReason, StopReason.endOfBook);
    await f.move(const Offset(-20, 0), ms: 100);
    await f.up();
    await advance(tester, const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    final page = currentPage(tester);
    final start = book.fractionAt(page.firstBlock, page.firstOffset);
    expect(start, lessThan(0.6), reason: 'the screen shows the position chosen by the slider (about half of the book), '
        'not the end');
    expect(reader(tester).following, isFalse);
  });
}
