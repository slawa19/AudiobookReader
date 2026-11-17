// Findings of the Codex behaviour-logic review of 2026-11-14 (docs/reviews/CODEX_REVIEW_LOGIC_2026-11-14.md), Nos.
// 1–10, and “To current spot” after a small drag. Each test failed on code 2fc63a4 — before the fix.

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/audio/audio_store.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/speech_text.dart';
import 'package:audiobook_reader/library/fake_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/chapter_download.dart';
import 'package:audiobook_reader/playback/fake_narration.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/tariffs.dart';
import 'package:audiobook_reader/playback/voice_sample.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/tts/sentences.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'journey_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

/// A controller on a synthetic book, without a screen.
FakeNarrationController controllerFor(FakeLibrary library, {AppSettings? settings, DateTime Function()? clock}) {
  final s = settings ?? AppSettings(voice: 'Aoede', modelId: 'gemini-3.8-flash-tts');
  final tariffs = Tariffs(today: () => DateTime(2026, 11, 14));
  return FakeNarrationController(
    library: library,
    audio: FakeAudioStore({}),
    downloads: FakeChapterDownloads(settings: s, tariffs: tariffs),
    sampler: FakeVoiceSampler(),
    settings: s,
    demoAcceleration: 1,
    clock: clock ?? () => DateTime(2026, 11, 14),
  );
}

Book synthetic(List<String> paragraphs, {List<List<TextSpanRange>>? spans}) => Book(
      id: 'synthetic',
      title: 'Синтетическая',
      author: 'Тест',
      language: 'ru',
      chapters: [Chapter(title: '', level: 1, firstBlock: 0, blockCount: paragraphs.length)],
      blocks: [
        for (var i = 0; i < paragraphs.length; i++)
          Block(index: i, kind: BlockKind.paragraph, text: paragraphs[i], spans: spans?[i] ?? const []),
      ],
      notes: const {},
    );

Future<void> flingNext(WidgetTester tester) async {
  await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
  await advance(tester, const Duration(milliseconds: 800));
}

Future<void> flingBack(WidgetTester tester) async {
  await tester.fling(find.byKey(const Key('page-area')), const Offset(250, 0), 1200);
  await advance(tester, const Duration(milliseconds: 800));
}

ReadingPosition pageStart(WidgetTester tester) {
  final st = reader(tester);
  final page = st.layout.pages[st.page];
  return ReadingPosition(page.firstBlock, page.firstOffset);
}

void main() {
  group('No. 1: after a stop, manual page turning gives the position to the screen', () {
    testWidgets('error → turned pages myself → “Close”: the position is the start of the page the reader '
        'opened', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.demoShow('error402');
      await advance(tester, const Duration(milliseconds: 600));
      await flingNext(tester);
      await flingNext(tester);
      final top = pageStart(tester);
      expect(reader(tester).following, isFalse, reason: 'manual page turning with the panel open turns following off');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.library.positionOf('kapitanskaya'), top);
      expect(onScreen(tester, top.block, top.offset), isTrue);
    });

    testWidgets('error → turned pages myself → larger font: the screen shows the position the reader '
        'opened', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.demoShow('error402');
      await advance(tester, const Duration(milliseconds: 600));
      await flingNext(tester);
      await flingNext(tester);
      final top = pageStart(tester);
      p.settings.fontStep = p.settings.fontStep + 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(onScreen(tester, top.block, top.offset), isTrue);
    });

    testWidgets('end of the book → turned back → “Close”: the position is the start of the opened '
        'page', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('end', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await flingBack(tester);
      await flingBack(tester);
      final top = pageStart(tester);
      expect(reader(tester).following, isFalse, reason: 'a back gesture from the only last page is accepted');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.library.positionOf('kapitanskaya'), top);
    });
  });

  group('No. 2: changing the voice or model does not lose the starting sentence inside a block', () {
    testWidgets('start from a sentence inside a paragraph → pause → profile change: the position is the same '
        'sentence', (tester) async {
      final library = FakeLibrary();
      final c = controllerFor(library);
      final book = synthetic(['Первое предложение. Второе предложение. Третье.', 'Новый абзац.']);
      c.listen(book, const PageRange(ReadingPosition(0, 6), ReadingPosition(1, 12)));
      expect(c.unitStart, const ReadingPosition(0, 20), reason: 'precondition');
      c.pause();
      c.restartSession();
      expect(c.unitStart, const ReadingPosition(0, 20));
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(0, 20));
      expect(c.blockProgress, closeTo(20 / book.blocks[0].text.length, 0.001), reason: 'the start of the paragraph is '
          'not read');
      c.close();
    });
  });

  group('No. 3: a held paragraph selection survives a re-layout', () {
    testWidgets('a paragraph is selected, the voice moved on, the download row disappeared: the paragraph and “Read '
        'from here” are on screen',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 4);
      await openKapitanskaya(tester, p);
      final book = currentBook(tester);
      p.downloads.start(book, book.chapterOf(39), p.downloads.profileFor('kapitanskaya'));
      await listenFromPanel(tester);
      expect(find.byKey(const Key('download-strip')), findsOneWidget, reason: 'precondition: the row is in the player '
          'panel');
      final st = reader(tester);
      var guard = 0;
      while (guard++ < 3000) {
        final page = st.layout.pages[st.page];
        final at = st.soundingPosition!;
        final last = page.fragments.last;
        if (at.block == last.block && at.offset >= last.start) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      final block = wholeParagraphOnPage(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await advance(tester, const Duration(milliseconds: 600));
      await advance(tester, const Duration(seconds: 8));
      expect(p.narration.block, isNot(block), reason: 'precondition: the voice moved on');
      p.downloads.stop();
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('download-strip')), findsNothing, reason: 'precondition: the panel height changed');
      final now = reader(tester).layout.pages[reader(tester).page];
      expect(now.fragments.any((f) => f.block == block), isTrue, reason: 'the selected paragraph is on screen');
      expect(find.byKey(const Key('read-from-here')), findsOneWidget);
    });
  });

  group('No. 4: “finished” is a separate fact', () {
    testWidgets('a one-page book: opened → shelf — 100 %', (tester) async {
      final p = await pumpPrototype(tester);
      await openBook(tester, 'Война и мир');
      expect(reader(tester).layout.pages.length, 1, reason: 'precondition: a one-page book');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(shelfProgress(ru, p.library.entry('voyna').fraction), shelfProgress(ru, 1));
    });

    testWidgets('listened to the end → “Close” → “Listen” again on the last paragraph on the last page: still 100 %',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p, at: const ReadingPosition(99, 0));
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 10));
      expect(p.narration.stopReason, StopReason.endOfBook, reason: 'precondition');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      final st = reader(tester);
      final book = st.widget.book;
      final last = book.blocks.length - 1;
      expect(st.page, st.layout.pages.length - 1, reason: 'precondition: the last page');
      expect(onScreen(tester, last, 0), isTrue, reason: 'precondition: the last paragraph is entirely on the last '
          'page');
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.block, last, reason: 'precondition: the last paragraph is playing');
      expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), shelfProgress(ru, 1));
    });
  });

  group('No. 5: external commands (headset, notification) turn following on', () {
    Future<void> pausedAndFlipped(WidgetTester tester, Prototype p) async {
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 300));
      await flingNext(tester);
      expect(reader(tester).following, isFalse, reason: 'precondition');
    }

    testWidgets('pause → turned pages myself → “Listen” from the headset', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await pausedAndFlipped(tester, p);
      p.narration.resume();
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      final at = reader(tester).soundingPosition!;
      expect(onScreen(tester, at.block, at.offset), isTrue);
    });

    testWidgets('pause → turned pages myself → “forward” from the notification', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await pausedAndFlipped(tester, p);
      p.narration.next();
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
    });

    testWidgets('an automatic move to the next paragraph does not turn following on', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 4);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      final block = p.narration.block;
      while (p.narration.block == block) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await advance(tester, const Duration(milliseconds: 300));
      expect(reader(tester).following, isFalse);
    });
  });

  group('No. 6: a note marker does not hide the start of a sentence', () {
    test('speech text: without the note marker and stress, offsets map back into the block', () {
      const text = 'Замо́к.12 Дальше.';
      const block = Block(index: 0, kind: BlockKind.paragraph, text: text, spans: [
        TextSpanRange(start: 7, end: 9, style: SpanStyle.noteRef, noteId: 'n1'),
      ]);
      final speech = speechText(block);
      expect(speech.text, 'Замок. Дальше.');
      expect(speech.toBlock(speech.text.indexOf('Дальше')), text.indexOf('Дальше'));
      expect(speech.fromBlock(text.indexOf('Дальше')), speech.text.indexOf('Дальше'));
      expect(blockSentenceStarts(block), [0, text.indexOf('Дальше')]);
    });

    testWidgets('“Фраза.¹ Следующее…”, the page starts at “Следующее” — the start is from it', (tester) async {
      final library = FakeLibrary();
      final c = controllerFor(library);
      const text = 'Фраза.1 Следующее предложение.';
      final book = synthetic([
        text
      ], spans: [
        [const TextSpanRange(start: 6, end: 7, style: SpanStyle.noteRef, noteId: 'n1')]
      ]);
      c.listen(book, const PageRange(ReadingPosition(0, 8), ReadingPosition(0, text.length)));
      expect(c.unitStart, const ReadingPosition(0, 8));
      c.close();
    });
  });

  group('No. 7: an expired or fired timer is not inherited by a new start', () {
    testWidgets('“until the end of the chapter” in the last chapter → end of the book: the timer is '
        'cleared', (tester) async {
      final library = FakeLibrary();
      final c = controllerFor(library);
      final book = synthetic(['Раз.', 'Два.']);
      c.readFrom(book, 0);
      c.setSleepTimer(SleepTimer.endOfChapter(c.now()));
      await tester.pump(const Duration(seconds: 10));
      expect(c.stopReason, StopReason.endOfBook, reason: 'precondition');
      expect(c.sleepTimer, isNull);
      c.close();
    });

    testWidgets('a minute timer → error → the time passed → “Read from here”: audio plays', (tester) async {
      final clock = TestClock();
      final library = FakeLibrary();
      final c = controllerFor(library, clock: clock.call);
      final book = synthetic(['Первый абзац довольно длинный, чтобы звучать дольше.', 'Второй абзац.']);
      c.readFrom(book, 0);
      c.setSleepTimer(SleepTimer.minutes(15, c.now()));
      await tester.pump(const Duration(seconds: 2));
      c.demoShow('error402');
      clock.forward(const Duration(minutes: 20));
      c.readFrom(book, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(c.state, NarrationState.playing);
      c.close();
    });
  });

  group('No. 8: the saved speed also applies to the voice movement', () {
    testWidgets('speed 1.5 from settings: in a second 1.5 times more is covered than at 1×', (tester) async {
      final library = FakeLibrary();
      final settings = AppSettings(voice: 'Aoede', modelId: 'gemini-3.8-flash-tts')..speed = 1.5;
      final c = controllerFor(library, settings: settings);
      final book = synthetic([List.filled(100, 'слово').join(' ')]);
      c.readFrom(book, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(c.state, NarrationState.playing, reason: 'precondition');
      final before = c.blockProgress;
      await tester.pump(const Duration(seconds: 1));
      final seconds = book.blocks[0].text.length * secondsPerChar / 1.5;
      expect(c.blockProgress - before, closeTo(1 / seconds, 0.002));
      c.close();
    });
  });

  group('No. 9: after “Clear narration” a new download takes space again', () {
    testWidgets('clearing → “Download chapter” to the end → the book has narration to delete again', (tester) async {
      final p = await pumpPrototype(tester);
      p.narration.clearAllNarration();
      expect(p.audio.totalBytes, 0, reason: 'precondition');
      final book = await p.library.loadBook('kapitanskaya');
      p.downloads.start(book, book.chapterOf(39), p.downloads.profileFor('kapitanskaya'));
      await advance(tester, const Duration(seconds: 45));
      expect(p.downloads.task, isNull, reason: 'precondition: the chapter is downloaded');
      expect(p.audio.bytesForBook('kapitanskaya'), greaterThan(0));
      expect(p.audio.totalBytes, greaterThan(0));
    });
  });

  group('No. 10: the probe goes by the full profile', () {
    testWidgets('probe Kore → changed the model → probe Kore is synthesized again', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester, animations: false);
      await tester.tap(find.byKey(const Key('settings-voice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('probe-Kore')));
      await advance(tester, const Duration(seconds: 5));
      expect(p.sampler.state, SampleState.idle, reason: 'precondition: the probe finished playing');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-flashLite')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-voice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('probe-Kore')));
      await tester.pump();
      expect(p.sampler.state, SampleState.loading, reason: 'another profile — another audio');
    });
  });

  group('“To current spot” right after “Listen”', () {
    testWidgets('a small drag with a return to the same page: following is on, no button', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final page = reader(tester).page;
      await tester.drag(find.byKey(const Key('page-area')), const Offset(-30, 0));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).page, page, reason: 'precondition: the page is the same');
      expect(reader(tester).following, isTrue);
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });

    testWidgets('a cancelled drag: following is on', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final center = tester.getCenter(find.byKey(const Key('page-area')));
      final g = await tester.startGesture(center);
      await g.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g.cancel();
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });

    testWidgets('a drag while the player panel appears: no button', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      final center = tester.getCenter(find.byKey(const Key('page-area')));
      final g = await tester.startGesture(center);
      await g.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(const Offset(-10, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await advance(tester, const Duration(seconds: 2));
      expect(reader(tester).following, isTrue);
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });

    testWidgets('a drag that changed the page: following is off', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      expect(reader(tester).following, isFalse);
      expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
    });
  });
}
