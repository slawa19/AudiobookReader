import 'dart:async';
import 'dart:convert';

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/controller.dart';
import 'package:audiobook_reader/playback/fake_player.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/player.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:audiobook_reader/tts/segments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_position_test.dart' show openAt;
import 'support/app_harness.dart';
import 'support/book_samples.dart';
import 'support/flows.dart';
import 'support/harness.dart' show reader, pumpPrototype, phone360;

/// События сохраняют исходные поколение и элемент, включая запоздавший ход старого списка.
class DelayedPlayer extends FakePlayer {
  DelayedPlayer({required super.clock}) {
    super.events.listen((event) {
      _timers.add(clock.schedule(const Duration(milliseconds: 40), () => _delayed.add(event)));
    });
  }
  final _delayed = StreamController<PlayerEvent>.broadcast(sync: true);
  final _timers = <Timer>[];
  @override
  Stream<PlayerEvent> get events => _delayed.stream;
  @override
  Future<void> dispose() async {
    for (final timer in _timers) {
      timer.cancel();
    }
    await super.dispose();
    await _delayed.close();
  }
}

// Обычная проза: по умолчанию 12 абзацев по 2400 знаков, начала отрезков внутри строк.
List<int> navigationBook({int repetitions = 14}) => utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info><book-title>Переходы по прозе</book-title><lang>ru</lang></title-info></description>
<body><section>${List.generate(12, (b) => '<p>${List.generate(repetitions, (s) => 'Утром путешественник $b осмотрел дорогу и продолжил путь. Вдали показались деревья, за которыми открывалась широкая долина. Он остановился у реки и посмотрел на другой берег.').join(' ')}</p>').join()}</section></body></FictionBook>''');

/// Инвариант экрана для прозы: если глава ещё продолжается, следующая строка не помещается.
/// Конец главы/книги разрешает короткую страницу; искусственное место старта — нет.
void expectFullProsePage(ReaderScreenState st) {
  final page = st.layout.pages[st.page];
  final book = st.widget.book;
  final last = page.fragments.last;
  final atChapterEnd = page.lastBlock == book.chapters[page.chapter].endBlock - 1 &&
      page.lastEnd == book.blocks[page.lastBlock].text.length;
  if (!atChapterEnd) {
    expect(last.top + last.height + st.pageStyle.lineHeight, greaterThan(st.columnSize.height),
        reason: 'следующая строка прозы помещается: показан обрывок страницы');
  }
}

void expectFollowingPage(WidgetTester tester) {
  final st = reader(tester);
  final at = st.soundingPosition!;
  final page = st.layout.pages[st.page];
  expect(st.following, isTrue);
  expect(find.byKey(const Key('to-reading-place')), findsNothing);
  expect(page.contains(at.block, at.offset), isTrue);
  expectFullProsePage(st);
  final shown = tester.widgetList<BookPage>(find.byType(BookPage)).singleWhere((p) => identical(p.page, page));
  expect(shown.highlightBlocks, contains(at.block));
  final fragment = page.fragments.firstWhere((f) => f.block == at.block);
  expect(find.byKey(ValueKey('hl-${fragment.block}-${fragment.start}')), findsWidgets);
}

Future<AppHarness> listeningApp(WidgetTester tester,
    {bool delayed = false, bool narrow = false, List<int>? bookBytes}) async {
  final h = AppHarness(tester);
  final player = delayed ? DelayedPlayer(clock: h.playbackClock) : null;
  await h.start(fakeTts: true, playerPort: player);
  if (player != null) addTearDown(player.dispose);
  if (narrow) tester.view.physicalSize = const Size(320, 800);
  final file = await h.copy(bookBytes ?? navigationBook());
  h.files.events.add(file);
  await h.opened();
  await h.deleted(file);
  await tapCenter(tester);
  await tester.tap(find.byKey(const Key('listen')));
  await h.until(() {
    h.playbackClock.advance(const Duration(milliseconds: 20));
    return h.app.services.narration.state == NarrationState.playing;
  });
  await tester.pumpAndSettle();
  expect(h.app.services.narration, isA<FileNarrationController>());
  return h;
}

void main() {
  testWidgets('короткий конец главы разрешён инвариантом', (tester) async {
    final p = await pumpPrototype(tester, size: phone360);
    final book = checked(utf8.encode('<FictionBook><body><section><p>Конец главы.</p></section>'
        '<section><p>${'Дальше продолжается обычная проза. ' * 70}</p></section></body></FictionBook>')).book;
    final st = await openAt(tester, p, book, const ReadingPosition(1, 0));
    await tester.pumpAndSettle();
    final previous = st.layout.loadPrevious();
    await tester.pumpAndSettle();
    await previous;
    final move = st.goToPage(0);
    await tester.pumpAndSettle();
    await move;
    final last = st.layout.pages[st.page].fragments.last;
    expect(last.top + last.height + st.pageStyle.lineHeight, lessThan(st.columnSize.height));
    expectFullProsePage(st);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('настоящий контроллер: назад на текущую страницу отменяет незавершённое ручное листание', (tester) async {
    final h = await listeningApp(tester);
    await h.until(() => h.app.queue.inFlight == 0);
    h.playbackClock.advance(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final st = reader(tester);
    final original = st.layout.pages[st.page];
    final at = st.soundingPosition!;
    expect(at.offset, greaterThan(0));
    expect(original.contains(at.block, 0), isTrue, reason: 'назад перезапустит тот же абзац на исходной странице');
    final area = tester.getRect(find.byKey(const Key('page-area')));
    await tester.tapAt(Offset(area.right - 12, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final pc = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(pc.page, greaterThan(st.page), reason: 'ручная анимация уже идёт');
    final revision = h.app.services.narration.commandRevision;
    await tester.tap(find.byKey(const Key('previous')));
    expect(h.app.services.narration.commandRevision, revision + 1);
    expect(h.app.services.narration.unitStart, ReadingPosition(at.block, 0));
    // Медленный кадр: прежний переворот завершится раньше замера высоты preparing.
    await tester.pump(const Duration(milliseconds: 400));
    await h.until(() => h.player.playing);
    await tester.pumpAndSettle();
    expectFollowingPage(tester);
  });

  testWidgets('настоящий контроллер: цель выбирает полную страницу перед сохранённой строкой', (tester) async {
    final h = await listeningApp(tester, narrow: true);
    var st = reader(tester);
    final book = st.widget.book;
    h.app.services.narration.close();
    await tester.pumpAndSettle();
    // Сохранено именно начало строки, которое читатель видел.
    final tp = piecePainter(st.pageStyle, book.blocks[0], 0, book.blocks[0].text.length,
        width: st.columnSize.width);
    final line = tp.getLineBoundary(const TextPosition(offset: 650)).start - 1;
    tp.dispose();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    h.app.library.savePosition(book.id, ReadingPosition(0, line));
    await tester.tap(find.text(book.title).first);
    await h.opened();
    st = reader(tester);
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await h.until(() => h.player.playing);
    await tester.pumpAndSettle();
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    final shown = st.layout.pages[st.page];
    final previous = st.layout.loadPrevious();
    await tester.pumpAndSettle();
    await previous;
    expect(st.layout.pages[st.page], same(shown), reason: 'досчёт назад не меняет уже показанную страницу');
    // Переходы плеера теперь идут по абзацам. Цель внутри префикса задаём явным стартом с предложения.
    final offset = chapterSegments(book.blocks)[1].mappings.first.blockStart;
    expect(st.layout.findPage(0, offset), isNotNull);
    h.app.services.narration.listen(book, PageRange(ReadingPosition(0, offset), ReadingPosition(0, offset + 1)));
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    expectFollowingPage(tester);
    h.app.services.narration.resume();
    await h.until(() => h.player.playing);
    await tester.pumpAndSettle();
    expectFollowingPage(tester);
  });

  for (final delayed in [false, true]) {
    testWidgets('настоящий контроллер: вперёд ×10, назад ×10 по абзацам; задержка событий $delayed', (tester) async {
      final h = await listeningApp(tester, delayed: delayed);
      final n = h.app.services.narration;
      for (final direction in ['next', 'previous']) {
        for (var step = 0; step < 10; step++) {
          final revision = n.commandRevision;
          final block = n.block!;
          await tester.tap(find.byKey(Key(direction)));
          await h.until(() {
            h.playbackClock.advance(const Duration(milliseconds: 20));
            return n.state == NarrationState.playing;
          });
          for (var frame = 0; frame < 24; frame++) {
            h.playbackClock.advance(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 20));
          }
          await tester.pumpAndSettle();
          expect(n.commandRevision, revision + 1);
          expect(n.unitStart, ReadingPosition(block + (direction == 'next' ? 1 : -1), 0));
          expectFollowingPage(tester);
        }
      }
    });
  }

  testWidgets('прототип: тот же сценарий вперёд и назад по длинным абзацам', (tester) async {
    final p = await pumpPrototype(tester, size: phone360, demoAcceleration: 1);
    final book = checked(navigationBook()).book;
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    await tester.pumpAndSettle();
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await advance(tester, const Duration(seconds: 2));
    for (final direction in ['next', 'previous']) {
      for (var i = 0; i < 6; i++) {
        final before = p.narration.block!;
        await tester.tap(find.byKey(Key(direction)));
        await advance(tester, const Duration(milliseconds: 600));
        expect(p.narration.block, before + (direction == 'next' ? 1 : -1));
        expectFollowingPage(tester);
      }
    }
    expectFullProsePage(st);
    await tester.pumpWidget(const SizedBox());
  });
}
