// Tests for the remaining Codex review findings of 2026-11-14 (docs/reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md).
// №6, №7 and №21 are in pagination_test.dart; №1, 2, 3, 5, 11, 12 are in review_fixes_test.dart.

import 'package:audiobook_reader/app/theme.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/tariffs.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

/// Bottom of the text column on screen.
double textBottom(WidgetTester tester) => reader(tester).pagePadding.top + reader(tester).columnSize.height;

Future<void> startListening(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byKey(const Key('listen')));
  await advance(tester, const Duration(seconds: 2));
}

void main() {
  testWidgets('№4: "Close" ends the session; the screen position is saved and not overwritten again', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 40);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    final st = reader(tester);
    // The screen follows the voice, so the sounding place is on screen; that is what "Close" saves (FR-P8, FR-P3).
    expect(st.following, isTrue);
    final onScreen = st.soundingPosition!;
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(seconds: 3));
    expect(p.narration.state, NarrationState.idle);
    expect(p.library.positionOf('kapitanskaya'), onScreen);
    final page = st.layout.pages[st.page];
    expect(page.contains(onScreen.block, onScreen.offset), isTrue, reason: 'after the recalculation it is on screen');
  });

  testWidgets('№4: "Close" after manual page turning saves the start of the visible page', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 300));
    await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
    await advance(tester, const Duration(milliseconds: 800));
    final st = reader(tester);
    expect(st.following, isFalse);
    final shown = st.layout.pages[st.page];
    final onScreen = ReadingPosition(shown.firstBlock, shown.firstOffset);
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(seconds: 1));
    expect(p.library.positionOf('kapitanskaya'), onScreen);
  });

  testWidgets('№8: "Read from here" on a paragraph longer than the page is visible, not under player', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
    p.settings.fontStep = fontSteps.length - 1;
    await openKapitanskaya(tester, p);
    p.narration.demoShow('paused', book: currentBook(tester), fromBlock: 39);
    await advance(tester, const Duration(milliseconds: 600));
    final st = reader(tester);
    final f = st.layout.pages[st.page].fragments.first;
    await tester.longPressAt(Offset(160, st.pagePadding.top + f.top + f.height / 2));
    await advance(tester, const Duration(milliseconds: 600));
    final button = tester.getRect(find.byKey(const Key('read-from-here')));
    final panel = tester.getRect(find.byKey(const Key('player-panel')));
    expect(button.top, greaterThanOrEqualTo(0));
    expect(button.bottom, lessThanOrEqualTo(panel.top), reason: 'the button is not under the player panel');
  });

  testWidgets('№9: "To reading place" is inside the player panel and does not cover the text', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
    await advance(tester, const Duration(seconds: 1));
    final button = find.byKey(const Key('to-reading-place'));
    expect(find.descendant(of: find.byKey(const Key('player-panel')), matching: button), findsOneWidget);
    expect(tester.getRect(button).top, greaterThanOrEqualTo(textBottom(tester)));
  });

  for (final (name, open) in <(String, Future<void> Function(WidgetTester))>[
    ('text appearance', (t) async {
      await tapCenter(t);
      await t.tap(find.byTooltip('Вид текста'));
    }),
    ('sleep timer active', (t) async {
      await t.tap(find.byKey(const Key('sleep')));
    }),
  ]) {
    testWidgets('№10: the "$name" sheet at 320×640 ×1,3 does not overflow', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('sleep', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await open(tester);
      await advance(tester, const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  }

  testWidgets('№13: a swipe during automatic page turning is a user swipe', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    final st = reader(tester);
    final start = st.page;
    // The automatic turn is still in progress while the user already drags the page back.
    st.goToPage(start + 1, user: false);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.fling(find.byKey(const Key('page-area')), const Offset(300, 0), 1500);
    await advance(tester, const Duration(seconds: 1));
    expect(st.following, isFalse, reason: 'the user gesture turns following off');
    expect(p.narration.state, NarrationState.playing);
  });

  testWidgets('№14: the book voice can be chosen before the first listening too', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    await tapCenter(tester);
    await tester.pumpAndSettle();
    expect(p.narration.state, NarrationState.idle);
    await tester.tap(find.byKey(const Key('voice-chip-idle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-Kore')));
    await tester.pump();
    expect(p.library.bookVoice('kapitanskaya'), 'Kore');
  });

  testWidgets('№15: chapter title only in the header and wraps; not in the player or above the slider', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    final chapter = tester.widget<Text>(find.byKey(const Key('top-bar-chapter')));
    expect(chapter.maxLines, 2);
    expect(chapter.overflow, TextOverflow.ellipsis);
    expect(find.descendant(of: find.byKey(const Key('player-panel')), matching: find.text(chapter.data!)), findsNothing);
  });

  testWidgets('№16: the footnote mark is caught within a 48×48 area', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
    final c = noteRefCenter(tester, 'n1');
    // 20 dp to the right of the mark is under half of the 48 target: the footnote opens.
    await tester.tapAt(c + const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-sheet')), findsOneWidget);
  });

  testWidgets('№16: the "Probe" button is at least 48 dp tall', (tester) async {
    final p = await pumpPrototype(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-voice')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('probe-Achernar'))).height, greaterThanOrEqualTo(48));
    expect(p.narration.state, NarrationState.idle);
  });

  testWidgets('№17: in sepia, "voiced" on the selected chapter uses the main text color', (tester) async {
    final p = await pumpPrototype(tester);
    p.settings.theme = ThemeChoice.sepia;
    await openDama(tester, p, at: const ReadingPosition(5, 0));
    await tapCenter(tester);
    await tester.tap(find.byTooltip('Оглавление'));
    await tester.pumpAndSettle();
    final mark = find.descendant(of: find.byKey(const Key('voiced-mark')).first, matching: find.text('озвучена'));
    expect(tester.widget<Text>(mark).style?.color, sepiaPalette.ink);
  });

  test('№18: price and estimate use the tariff for the app-clock date, not one hard-coded in the screen', () {
    final now = Tariffs(today: () => DateTime(2026, 11, 14));
    final later = Tariffs(today: () => DateTime(2027, 1, 5));
    expect(now.dollarsPerHour(TtsModel.flash), 0.81);
    expect(later.dollarsPerHour(TtsModel.flash), 1.62);
    expect(now.beforePriceChange, isTrue);
    expect(later.beforePriceChange, isFalse);
  });

  testWidgets('№18: settings show the price for today by the app clock', (tester) async {
    await pumpPrototype(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0,81'), findsOneWidget);
  });

  testWidgets('№19: download strip visible with the panels open; after an error, "Download again"', (tester) async {
    final p = await pumpPrototype(tester);
    await openDama(tester, p, at: const ReadingPosition(180, 0));
    final book = currentBook(tester);
    p.downloads.demoShow(book, book.chapterOf(180), failed: false);
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    expect(find.byKey(const Key('download-strip')).hitTestable(), findsOneWidget);
    p.downloads.demoShow(book, book.chapterOf(180), failed: true);
    await tester.tap(find.byTooltip('Оглавление'));
    await advance(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('download-estimate')), findsOneWidget);
    expect(find.text('Скачать снова'), findsOneWidget);
  });

  testWidgets('№20: the 402 text does not promise automatic continuation', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
    await advance(tester, const Duration(milliseconds: 600));
    expect(find.textContaining('нажмите «Слушать»'), findsOneWidget);
    expect(find.textContaining('продолжится'), findsNothing);
  });

  testWidgets('voice probe: a permanent error is shown in the voice row as Google text', (tester) async {
    final p = await pumpPrototype(tester);
    p.sampler.demoFailVoice = 'Aoede';
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('probe-Aoede')));
    await advance(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('probe-error')), findsOneWidget);
    expect(find.textContaining('The service is currently unavailable.'), findsOneWidget);
  });

  testWidgets('a double tap on a book during a slow open opens a single screen', (tester) async {
    final p = await pumpPrototype(tester);
    p.library.loadDelay = const Duration(milliseconds: 300);
    await tester.tap(find.text('Капитанская дочка').first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Капитанская дочка').first);
    await advance(tester, const Duration(seconds: 1));
    await settle(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('page-area')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing, reason: 'there is no second reader screen under the first');
  });

  testWidgets('following the voice: the page contains the sounding place inside a long block', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3, demoAcceleration: 20);
    p.settings.fontStep = fontSteps.length - 1;
    await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0));
    await startListening(tester);
    var turned = 0;
    var last = reader(tester).page;
    for (var i = 0; i < 40; i++) {
      // The voice plays; then it "freezes" (a pause) during the page-turn animation, and the page is checked.
      await tester.pump(const Duration(milliseconds: 250));
      p.narration.pause();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final st = reader(tester);
      final at = st.soundingPosition!;
      expect(st.layout.pages[st.page].contains(at.block, at.offset), isTrue,
          reason: 'step $i: ${at.block}:${at.offset} is sounding, but a different page is on screen');
      if (st.page != last) turned++;
      last = st.page;
      p.narration.resume();
    }
    expect(turned, greaterThan(1), reason: 'the test is not vacuous: the page turned following the voice');
  });
}
