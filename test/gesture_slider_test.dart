// The book slider by finger: dragging, past the edge, while listening (section C of the gesture review
// of 2026-11-14). The earlier slider tests are a single tap on the track.

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'journey_support.dart' show ru;
import 'support/flows.dart';
import 'support/harness.dart';

const _slider = Key('book-slider');

/// The track point of the slider for the fraction [v]: the Material 3 slider has 24 dp margins at the edges.
Offset trackPoint(WidgetTester tester, double v) {
  final box = tester.getRect(find.byKey(_slider));
  return Offset(box.left + 24 + (box.width - 48) * v, box.center.dy);
}

void main() {
  testWidgets('dragging while listening: the header shows the chapter under the finger, the voice does not change '
      'position, '
      'after release — the page with that position and following is off (FR-R5)', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0));
    await startListening(tester);
    final book = currentBook(tester);
    final block = p.narration.block;
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 500));
    expect(find.byKey(_slider).hitTestable(), findsOneWidget, reason: 'the slider is above the player panel');
    final chapterBefore = tester.widget<Text>(find.byKey(const Key('top-bar-chapter'))).data;

    final f = await Finger.down(tester, trackPoint(tester, 0.05));
    await f.move(trackPoint(tester, 0.9) - trackPoint(tester, 0.05), ms: 400);
    await f.hold(200);
    // The finger is still on the slider: the header shows the chapter under the finger, the page and following are
    // unchanged.
    final preview = tester.widget<Text>(find.byKey(const Key('top-bar-chapter'))).data;
    expect(preview, chapterLabel(book, book.chapterOf(book.placeAt(0.9).$1)));
    expect(preview, isNot(chapterBefore), reason: 'precondition: 90 % of the book is a different chapter');
    expect(reader(tester).following, isTrue, reason: 'following is turned off by the release, not by the start of the '
        'drag');
    await f.up();
    await advance(tester, const Duration(milliseconds: 600));

    final st = reader(tester);
    final page = currentPage(tester);
    expect(book.fractionAt(page.firstBlock, page.firstOffset), lessThanOrEqualTo(0.91));
    expect(book.fractionAt(page.lastBlock, page.lastEnd), greaterThanOrEqualTo(0.89));
    expect(st.following, isFalse);
    // In the meantime the voice itself advanced no more than a couple of paragraphs from the start — it was not moved
    // to 90 % of the book.
    expect(p.narration.block! - block!, inInclusiveRange(0, 3), reason: 'the voice does not change position');
    expect(p.narration.state, NarrationState.playing);
    expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('top-bar-chapter'))).data, chapterLabel(book, page.chapter));
  });

  testWidgets('dragging past the right edge and releasing far from the slider — the last page and 100 %; past the left '
      '— '
      'the first', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    await tapCenter(tester);
    await tester.pumpAndSettle();
    var f = await Finger.down(tester, trackPoint(tester, 0.5));
    await f.move(const Offset(400, -300), ms: 300);
    await f.up();
    await tester.pumpAndSettle();
    final st = reader(tester);
    expect(st.page, st.layout.pages.length - 1);
    expect(find.text(ru.ofBook(1)), findsOneWidget);
    expect(p.library.isFinished('kapitanskaya'), isTrue);

    f = await Finger.down(tester, trackPoint(tester, 0.5));
    await f.move(const Offset(-400, 200), ms: 300);
    await f.up();
    await tester.pumpAndSettle();
    expect(reader(tester).page, 0);
    expect(p.library.isFinished('kapitanskaya'), isFalse);
    expect(p.library.positionOf('kapitanskaya'), const ReadingPosition(0, 0));
  });

  testWidgets('listening, touched the thumb and released without moving it: the page is the same, following is not '
      'turned off (FR-P4)',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 500));
    final st = reader(tester);
    final page = st.page;
    final book = currentBook(tester);
    final value = book.fractionAt(currentPage(tester).firstBlock, currentPage(tester).firstOffset);
    final f = await Finger.down(tester, trackPoint(tester, value));
    await f.hold(250);
    await f.up();
    await advance(tester, const Duration(milliseconds: 600));
    expect(reader(tester).page, page, reason: 'the slider is not moved — the page is the same');
    expect(reader(tester).following, isTrue,
        reason: 'FR-P4: the slider turns following off only when it is moved');
  });

  testWidgets('a one-page book: the slider does not crash the screen and does not change the page', (tester) async {
    await pumpPrototype(tester);
    await openBook(tester, 'Война и мир');
    final st = reader(tester);
    expect(st.layout.pages.length, 1, reason: 'precondition: the stub book is one page');
    await tapCenter(tester);
    await tester.pumpAndSettle();
    final f = await Finger.down(tester, trackPoint(tester, 0.9));
    await f.move(const Offset(-250, 0), ms: 300);
    await f.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(reader(tester).page, 0);
    expect(find.text(ru.ofBook(1)), findsOneWidget);
  });
}
