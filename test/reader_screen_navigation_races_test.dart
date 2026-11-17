import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_position_test.dart' show openAt;
import 'reader_screen_real_navigation_test.dart'
    show listeningApp, navigationBook, expectFollowingPage, expectFullProsePage;
import 'support/harness.dart' show reader, pumpPrototype;

Offset third(WidgetTester tester, bool right) {
  final st = reader(tester);
  final area = tester.getRect(find.byKey(const Key('page-area')));
  return Offset(area.left + area.width * (right ? 0.9 : 0.1), st.pagePadding.top + 120);
}

void main() {
  for (final reuse in [false, true]) {
    testWidgets('cancelling a seek after reuse of $reuse: the backward catch-up keeps the page', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      final book = Book(id: 'listener-chain', title: '', author: '', language: 'ru',
          chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 3)],
          blocks: [for (var i = 0; i < 3; i++) Block(index: i, kind: BlockKind.paragraph,
              text: 'Текст тут. ' * 3000)], notes: const {});
      final st = await openAt(tester, p, book, const ReadingPosition(1, 0));
      p.narration.readFrom(book, 1);
      p.narration.pause();
      await tester.pump();
      await tester.pump();
      final original = st.layout;
      final page = st.layout.pages[st.page];
      expect(st.layout.isComplete, isFalse);
      if (reuse) st.goToPosition(const ReadingPosition(1, 32000), user: false);
      st.goToPosition(const ReadingPosition(2, 25000));
      p.narration.resume();
      await tester.pump(const Duration(milliseconds: 400));
      expect(st.layout, same(original));
      expect(st.layout.pages[st.page], same(page));
      await tester.tapAt(third(tester, false));
      for (var i = 0; i < 200 && st.layout.prependedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump();
      expect(st.layout.prependedCount, greaterThan(0));
      expect(st.page, st.layout.prependedCount - 1, reason: 'back goes to the adjacent page, not to the chapter start');
      expect(st.layout.pages[st.page].lastEnd, 33000);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the To current spot button takes over the manual animation to the voice page', (tester) async {
    final h = await listeningApp(tester);
    final st = reader(tester);
    for (var i = 0; i < 60 && st.page == 0; i++) {
      h.playbackClock.advance(const Duration(seconds: 5));
      await h.until(() => h.app.services.narration.state == NarrationState.playing);
      await tester.pumpAndSettle();
    }
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    final voicePage = st.page;
    expect(voicePage, greaterThan(0));
    final back = st.goToPage(voicePage - 1);
    await tester.pumpAndSettle();
    await back;
    expect(st.following, isFalse);
    await tester.tapAt(third(tester, true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(st.page, voicePage - 1, reason: 'the manual page turn has not passed halfway yet');
    await tester.tap(find.byKey(const Key('to-reading-place')));
    await tester.pumpAndSettle();
    expectFollowingPage(tester);
  });

  testWidgets('a tap after forward on pause holds the page and switches following off', (tester) async {
    final h = await listeningApp(tester, bookBytes: navigationBook(repetitions: 5));
    final st = reader(tester);
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    final origin = st.page;
    expect(origin, 0, reason: 'a counter tap at the book edge holds the original page');
    final at = st.soundingPosition!;
    expect(st.layout.findPage(at.block + 1, 0), origin + 1, reason: 'the audio target is on the adjacent ready page');
    await tester.tap(find.byKey(const Key('next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.tapAt(third(tester, false));
    await tester.pumpAndSettle();
    expect(st.page, origin);
    final voice = st.soundingPosition!;
    expect(st.layout.pages[st.page].contains(voice.block, voice.offset), isFalse);
    expect(st.following, isFalse);
    expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
    expectFullProsePage(st);
  });
}
