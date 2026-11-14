// Находки ревью логики поведения Codex 2026-11-14 (docs/reviews/CODEX_REVIEW_LOGIC_2026-11-14.md), №1–10, и
// «К месту чтения» после малого перетаскивания. Каждый тест падал на коде 2fc63a4 — до исправления.

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

/// Контроллер на синтетической книге, без экрана.
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
  group('№1: после остановки ручное листание отдаёт место экрану', () {
    testWidgets('ошибка → листал сам → «Закрыть»: позиция — начало страницы, которую читатель открыл', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.demoShow('error402');
      await advance(tester, const Duration(milliseconds: 600));
      await flingNext(tester);
      await flingNext(tester);
      final top = pageStart(tester);
      expect(reader(tester).following, isFalse, reason: 'ручное листание при открытой панели выключает следование');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.library.positionOf('kapitanskaya'), top);
      expect(onScreen(tester, top.block, top.offset), isTrue);
    });

    testWidgets('ошибка → листал сам → крупнее шрифт: на экране место, которое читатель открыл', (tester) async {
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

    testWidgets('конец книги → листал назад → «Закрыть»: позиция — начало открытой страницы', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('end', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await flingBack(tester);
      await flingBack(tester);
      final top = pageStart(tester);
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.library.positionOf('kapitanskaya'), top);
    });
  });

  group('№2: смена голоса или модели не теряет стартовое предложение внутри блока', () {
    testWidgets('старт с предложения внутри абзаца → пауза → смена профиля: место — то же предложение', (tester) async {
      final library = FakeLibrary();
      final c = controllerFor(library);
      final book = synthetic(['Первое предложение. Второе предложение. Третье.', 'Новый абзац.']);
      c.listen(book, const PageRange(ReadingPosition(0, 6), ReadingPosition(1, 12)));
      expect(c.unitStart, const ReadingPosition(0, 20), reason: 'предусловие');
      c.pause();
      c.restartSession();
      expect(c.unitStart, const ReadingPosition(0, 20));
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(0, 20));
      expect(c.blockProgress, closeTo(20 / book.blocks[0].text.length, 0.001), reason: 'начало абзаца не читается');
      c.close();
    });
  });

  group('№3: удержанный выбор абзаца переживает перераскладку', () {
    testWidgets('выбран абзац, голос ушёл дальше, строка скачивания исчезла: абзац и «Читать отсюда» на экране',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 4);
      await openKapitanskaya(tester, p);
      final book = currentBook(tester);
      p.downloads.start(book, book.chapterOf(39), p.downloads.profileFor('kapitanskaya'));
      await listenFromPanel(tester);
      expect(find.byKey(const Key('download-strip')), findsOneWidget, reason: 'предусловие: строка в панели плеера');
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
      expect(p.narration.block, isNot(block), reason: 'предусловие: голос ушёл дальше');
      p.downloads.stop();
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('download-strip')), findsNothing, reason: 'предусловие: высота панели изменилась');
      final now = reader(tester).layout.pages[reader(tester).page];
      expect(now.fragments.any((f) => f.block == block), isTrue, reason: 'выбранный абзац на экране');
      expect(find.byKey(const Key('read-from-here')), findsOneWidget);
    });
  });

  group('№4: «дочитана» — отдельный факт', () {
    testWidgets('одностраничная книга: открыл → на полку — 100 %', (tester) async {
      final p = await pumpPrototype(tester);
      await openBook(tester, 'Война и мир');
      expect(reader(tester).layout.pages.length, 1, reason: 'предусловие: книга в одну страницу');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(shelfProgress(ru, p.library.entry('voyna').fraction), shelfProgress(ru, 1));
    });

    testWidgets('дослушал → «Закрыть» → снова «Слушать» последний абзац на последней странице: по-прежнему 100 %',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p, at: const ReadingPosition(99, 0));
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 10));
      expect(p.narration.stopReason, StopReason.endOfBook, reason: 'предусловие');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      final st = reader(tester);
      final book = st.widget.book;
      final last = book.blocks.length - 1;
      expect(st.page, st.layout.pages.length - 1, reason: 'предусловие: последняя страница');
      expect(onScreen(tester, last, 0), isTrue, reason: 'предусловие: последний абзац целиком на последней странице');
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.block, last, reason: 'предусловие: звучит последний абзац');
      expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), shelfProgress(ru, 1));
    });
  });

  group('№5: команды извне (гарнитура, уведомление) включают следование', () {
    Future<void> pausedAndFlipped(WidgetTester tester, Prototype p) async {
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 300));
      await flingNext(tester);
      expect(reader(tester).following, isFalse, reason: 'предусловие');
    }

    testWidgets('пауза → листал сам → «Слушать» с гарнитуры', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await pausedAndFlipped(tester, p);
      p.narration.resume();
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      final at = reader(tester).soundingPosition!;
      expect(onScreen(tester, at.block, at.offset), isTrue);
    });

    testWidgets('пауза → листал сам → «вперёд» из уведомления', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await pausedAndFlipped(tester, p);
      p.narration.next();
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
    });

    testWidgets('автоматический переход к следующему абзацу следование не включает', (tester) async {
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

  group('№6: знак сноски не прячет начало предложения', () {
    test('текст для речи: без знака сноски и ударения, смещения переводятся обратно в блок', () {
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

    testWidgets('«Фраза.¹ Следующее…», страница начинается со «Следующее» — старт с него', (tester) async {
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

  group('№7: истёкший или сработавший таймер не наследуется новым стартом', () {
    testWidgets('«до конца главы» в последней главе → конец книги: таймер снят', (tester) async {
      final library = FakeLibrary();
      final c = controllerFor(library);
      final book = synthetic(['Раз.', 'Два.']);
      c.readFrom(book, 0);
      c.setSleepTimer(SleepTimer.endOfChapter(c.now()));
      await tester.pump(const Duration(seconds: 10));
      expect(c.stopReason, StopReason.endOfBook, reason: 'предусловие');
      expect(c.sleepTimer, isNull);
      c.close();
    });

    testWidgets('таймер по минутам → ошибка → срок прошёл → «Читать отсюда»: звук идёт', (tester) async {
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

  group('№8: сохранённая скорость — и в движении голоса', () {
    testWidgets('скорость 1,5 из настроек: за секунду пройдено в 1,5 раза больше, чем при 1×', (tester) async {
      final library = FakeLibrary();
      final settings = AppSettings(voice: 'Aoede', modelId: 'gemini-3.8-flash-tts')..speed = 1.5;
      final c = controllerFor(library, settings: settings);
      final book = synthetic([List.filled(100, 'слово').join(' ')]);
      c.readFrom(book, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(c.state, NarrationState.playing, reason: 'предусловие');
      final before = c.blockProgress;
      await tester.pump(const Duration(seconds: 1));
      final seconds = book.blocks[0].text.length * secondsPerChar / 1.5;
      expect(c.blockProgress - before, closeTo(1 / seconds, 0.002));
      c.close();
    });
  });

  group('№9: после «Очистить озвучку» новое скачивание снова занимает место', () {
    testWidgets('очистка → «Скачать главу» до конца → у книги снова есть озвучка для удаления', (tester) async {
      final p = await pumpPrototype(tester);
      p.narration.clearAllNarration();
      expect(p.audio.totalBytes, 0, reason: 'предусловие');
      final book = await p.library.loadBook('kapitanskaya');
      p.downloads.start(book, book.chapterOf(39), p.downloads.profileFor('kapitanskaya'));
      await advance(tester, const Duration(seconds: 45));
      expect(p.downloads.task, isNull, reason: 'предусловие: глава скачана');
      expect(p.audio.bytesForBook('kapitanskaya'), greaterThan(0));
      expect(p.audio.totalBytes, greaterThan(0));
    });
  });

  group('№10: проба — по полному профилю', () {
    testWidgets('проба Kore → сменил модель → проба Kore снова озвучивается', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester, animations: false);
      await tester.tap(find.byKey(const Key('settings-voice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('probe-Kore')));
      await advance(tester, const Duration(seconds: 5));
      expect(p.sampler.state, SampleState.idle, reason: 'предусловие: проба доиграла');
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
      expect(p.sampler.state, SampleState.loading, reason: 'другой профиль — другой звук');
    });
  });

  group('«К месту чтения» сразу после «Слушать»', () {
    testWidgets('малое перетаскивание с возвратом на ту же страницу: следование включено, кнопки нет', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final page = reader(tester).page;
      await tester.drag(find.byKey(const Key('page-area')), const Offset(-30, 0));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).page, page, reason: 'предусловие: страница та же');
      expect(reader(tester).following, isTrue);
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });

    testWidgets('отменённое перетаскивание: следование включено', (tester) async {
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

    testWidgets('перетаскивание во время появления панели плеера: кнопки нет', (tester) async {
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

    testWidgets('перетаскивание, сменившее страницу: следование выключено', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      expect(reader(tester).following, isFalse);
      expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
    });
  });
}
