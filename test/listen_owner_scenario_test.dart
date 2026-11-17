// Owner remark of 2026-11-14: pause on a paragraph in the middle of the page → “Close” → “Listen” turned the page back
// and read the previous long paragraph from its start, and following ended up off. Rule A–E — spec 001, FR-P3. (а)
// failed on code 90e4d59 (paragraph 20 played instead of 23). (д) did NOT fail on 90e4d59 in the test environment: the
// owner's following-off effect (in the browser) did not reproduce here for any of the 24 combinations of window size,
// speed-up of the fake voice and frame step; the test guards the outcome and does not prove the cause.

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

/// “Ионыч”, chapter I: the top of the page holds the tail of the long paragraph 22, paragraph 23 starts in the middle
/// (“— Ну, Котик, сегодня ты играла…”). Dark theme, as the owner has it.
Future<void> openOwnerPage(WidgetTester tester, Prototype p) async {
  p.settings.theme = ThemeChoice.dark;
  // The explicit page start of this scenario: the tail of 22 before the full paragraph 23.
  await openDama(tester, p, at: const ReadingPosition(22, 966));
  final st = reader(tester);
  final page = st.layout.pages[st.page];
  expect(page.firstBlock, 22, reason: 'the top of the page is the tail of paragraph 22');
  expect(page.firstOffset, greaterThan(0));
  expect(page.fragments.any((f) => f.block == 23 && f.start == 0), isTrue, reason: 'paragraph 23 starts on the page');
}

void main() {
  testWidgets('(а) pause on a paragraph in the middle of the page → “Close” → “Listen”: the same paragraph, the same '
      'page, '
      'following is on', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openOwnerPage(tester, p);
    // Listens to paragraph 23 and pauses.
    p.narration.readFrom(currentBook(tester), 23);
    await advance(tester, const Duration(seconds: 3));
    expect(p.narration.block, 23);
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 500));
    expect(p.narration.state, NarrationState.paused);
    final pageBefore = reader(tester).layout.pages[reader(tester).page];
    expect(pageBefore.fragments.any((f) => f.block == 23), isTrue);
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(milliseconds: 800));
    // “Listen” again.
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    final beforeListen = reader(tester).layout.pages[reader(tester).page];
    final startBeforeListen = (beforeListen.firstBlock, beforeListen.firstOffset);
    final topBeforeListen = beforeListen.fragments.firstWhere((f) => f.block == 23 && f.start == 0).top;
    await tester.tap(find.byKey(const Key('listen')));
    await advance(tester, const Duration(seconds: 3));
    final st = reader(tester);
    expect(p.narration.block, 23, reason: 'continues from the paragraph where it stopped');
    final page = st.layout.pages[st.page];
    expect(page.fragments.any((f) => f.block == 23 && f.start == 0), isTrue,
        reason: 'the page is the same — it did not turn back');
    expect((page.firstBlock, page.firstOffset), startBeforeListen,
        reason: '“Listen” does not change the start of the already visible page');
    expect(page.fragments.firstWhere((f) => f.block == 23 && f.start == 0).top, topBeforeListen,
        reason: 'the playing paragraph stays at the same vertical position');
    expect(st.following, isTrue);
  });

  testWidgets('(д) right after “Listen” there is no “To current spot” button — in the same sequence as the owner had',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openOwnerPage(tester, p);
    p.narration.readFrom(currentBook(tester), 23);
    await advance(tester, const Duration(seconds: 3));
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(milliseconds: 800));
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('listen')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('to-reading-place')), findsNothing, reason: 'step $i after “Listen”');
    }
    expect(reader(tester).following, isTrue);
  });
}
