// Tests for the Codex review findings of 2026-11-14 (docs/reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md).
// Each test failed on commit 53c78d3, before the fix.

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';
import 'support/sentence_oracle.dart';

void main() {
  testWidgets('№1: a short key does not crash settings', (tester) async {
    final p = await pumpPrototype(tester);
    p.settings.apiKey = 'abc';
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('abc'), findsOneWidget);
  });

  testWidgets('№2: "Read from here" from pause leaves it paused at the new position', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 300));
    expect(p.narration.state, NarrationState.paused);
    final block = wholeParagraphOnPage(tester);
    await tester.longPressAt(blockCenter(tester, block));
    await advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('read-from-here')));
    await advance(tester, const Duration(seconds: 2));
    expect(p.narration.block, block);
    expect(p.narration.state, NarrationState.paused);
  });

  testWidgets('№3: after an error and manual page turns, "Listen" starts from the new position', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
    await advance(tester, const Duration(milliseconds: 600));
    await tapRightThird(tester);
    await advance(tester, const Duration(milliseconds: 600));
    await tapRightThird(tester);
    await advance(tester, const Duration(milliseconds: 600));
    final saved = p.library.positionOf('kapitanskaya')!;
    expect(saved.block, greaterThan(39), reason: 'the screen saves the position itself after an explicit turn (A§5)');
    await tester.tap(find.byKey(const Key('error-listen')));
    await tester.pump();
    expect(p.narration.block, saved.block);
  });

  testWidgets('№5: "Clear narration" resets chapter readiness, probes and stops the download', (tester) async {
    final p = await pumpPrototype(tester);
    expect(p.downloads.isVoiced('dama', 1, p.downloads.profileFor('dama')), isTrue);
    final book = await p.library.loadBook('dama');
    p.downloads.demoShow(book, 3, failed: false);
    const kore = VoiceProfile(voiceId: 'Kore', model: 'gemini-3.8-flash-tts');
    p.sampler.play(kore, bookLanguage: 'ru');
    await advance(tester, const Duration(seconds: 5));
    p.sampler.stop();
    await tester.tap(find.byTooltip('Настройки'));
    await settle(tester, animations: false);
    await tester.tap(find.byKey(const Key('clear')));
    await advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('clear-confirm')));
    await advance(tester, const Duration(milliseconds: 600));
    expect(p.audio.totalBytes, 0);
    expect(p.downloads.isVoiced('dama', 1, p.downloads.profileFor('dama')), isFalse, reason: 'chapter readiness reset');
    expect(p.downloads.task, isNull, reason: 'the download was stopped');
    p.sampler.play(kore, bookLanguage: 'ru');
    await tester.pump();
    expect(p.sampler.state.name, 'loading', reason: 'the voice probe is synthesized again after clearing');
  });

  // №11 is replaced by rule A–E (owner's remark of 2026-11-14): the tail of a sentence from the previous page is
  // not read; the start is the first sentence that begins on the page; the page does not move backwards.
  testWidgets('№11 → FR-P3: "Listen" starts at the first sentence on the page, no page turn back', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
    final st = reader(tester);
    // The scene needs a paragraph tail: get it by ordinary page turning from the start of the book.
    final continuation = st.layout.pages.indexWhere((page) => page.firstOffset > 0);
    expect(continuation, greaterThan(0));
    final move = st.goToPage(continuation);
    await tester.pumpAndSettle();
    await move;
    final page = st.layout.pages[st.page];
    expect(page.firstOffset, greaterThan(0), reason: 'the page begins with a paragraph tail');
    final book = st.widget.book;
    // The expected place is the first sentence start on the page, found by an independent check against the text of
    // rules A§6.1, not by the same `sentenceStarts` (logic review of 2026-11-14).
    final expected = firstSentenceStartOnPage(book, page);
    expect(expected, isNotNull);
    expect(expected, isNot(ReadingPosition(page.firstBlock, page.firstOffset)),
        reason: 'the test is not vacuous: the page does not start at a sentence start');
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await advance(tester, const Duration(milliseconds: 500));
    expect(p.library.listeningPositionOf('kapitanskaya'), expected);
    final now = reader(tester).layout.pages[reader(tester).page];
    expect(now.contains(expected!.block, expected.offset), isTrue, reason: 'the page did not move backwards');
    expect(reader(tester).following, isTrue);
  });

  testWidgets('№12: with the panels open, tapping a footnote mark opens the footnote', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
    await tapCenter(tester);
    await tester.pumpAndSettle();
    expect(reader(tester).panelsVisible, isTrue);
    await tester.tapAt(noteRefCenter(tester, 'n1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-sheet')), findsOneWidget);
  });
}
