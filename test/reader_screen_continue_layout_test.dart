import 'dart:convert';

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_backfill_test.dart' show openBackfillBook, turn;
import 'reader_screen_real_navigation_test.dart' show expectFollowingPage;
import 'support/flows.dart';
import 'support/harness.dart' show reader;
import 'support/app_harness.dart';

List<Object> bounds(BookPageLayout p) => [
  p.chapter, for (final f in p.fragments) (f.block, f.start, f.end, f.top, f.height),
];

List<int> nearbyBook() => utf8.encode('''<FictionBook><description><title-info>
<book-title>Продолжение раскладки</book-title><lang>ru</lang></title-info></description><body>
${List.generate(3, (c) => '<section><title><p>Глава $c</p></title>${List.generate(40, (b) => '<p>${List.filled(13, 'Утром путешественник осмотрел дорогу и продолжил путь. Вдали показались деревья, за которыми открывалась широкая долина. Он остановился у реки и посмотрел на другой берег.').join(' ')}</p>').join()}</section>').join()}
</body></FictionBook>''');

Future<(AppHarness, ReaderScreenState, int)> freshPage(WidgetTester tester, {bool atChapterEnd = false}) async {
  final h = AppHarness(tester);
  await h.start(fakeTts: true);
  final file = await h.copy(nearbyBook());
  h.files.events.add(file);
  await h.opened();
  var st = reader(tester);
  final book = st.widget.book;
  final block = atChapterEnd ? book.chapters[1].endBlock - 1 : book.chapters[1].firstBlock + 3;
  h.app.services.narration.readFrom(book, block);
  await h.until(() => h.player.playing);
  await h.until(() => h.app.queue.inFlight == 0);
  h.app.services.narration.pause();
  await tester.pumpAndSettle();
  tester.state<NavigatorState>(find.byType(Navigator).first).push(PageRouteBuilder<void>(
      transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, animation, secondaryAnimation) => ReaderScreen(services: h.app.services, book: book)));
  await tester.pump();
  await tester.pump();
  st = reader(tester);
  st.layout.pause();
  await tester.pump(const Duration(milliseconds: 400));
  st.layout.resume();
  expect(st.layout.isComplete, isFalse);
  expect(st.layout.findPage(block + 1, 0), isNull);
  return (h, st, block);
}

void main() {
  testWidgets('real controller: forward three times continues previous pages like ordinary turning', (tester) async {
    final h = await openBackfillBook(tester);
    var st = reader(tester);
    final book = st.widget.book;
    final block = book.chapters[1].firstBlock + 3;
    st.goToPosition(ReadingPosition(block, 0));
    await tester.pumpAndSettle();
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await h.until(() => h.player.playing);
    await tester.pumpAndSettle();
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    final origin = st.layout.pages[st.page];
    final seen = <List<Object>>[bounds(origin)];
    for (var i = 0; i < 3; i++) {
      await turn(tester, forward: true);
      seen.add(bounds(st.layout.pages[st.page]));
    }
    for (var i = 2; i >= 0; i--) {
      await turn(tester);
      expect(bounds(st.layout.pages[st.page]), seen[i]);
    }
    final control = st.layout.pages.skipWhile((p) => !identical(p, origin)).map(bounds).toList();
    final col = st.columnSize;
    // The control screen has already turned these pages. The second one is open at the same place, but its
    // background layout has not yet been given time to calculate the next paragraph.
    tester.state<NavigatorState>(find.byType(Navigator).first).push(PageRouteBuilder<void>(
        transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, animation, secondaryAnimation) => ReaderScreen(services: h.app.services, book: book)));
    await tester.pump();
    await tester.pump();
    st = reader(tester);
    expect(st.columnSize, col);
    final original = st.layout;
    expect(bounds(original.pages[st.page]), seen.first);
    original.pause();
    await tester.pump(const Duration(milliseconds: 400));
    original.resume();
    expect(original.findPage(block + 1, 0), isNull, reason: 'the first command is really beyond the calculated edge');
    await tester.tap(find.byKey(const Key('play-pause')));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('next')));
      expect(st.layout, same(original), reason: 'a nearby command continues the layout');
      await h.until(() => h.app.services.narration.state == NarrationState.playing);
      await tester.pumpAndSettle();
      expect(st.layout, same(original));
      expectFollowingPage(tester);
      expect(bounds(st.layout.pages[st.page]), control[st.page]);
    }
    final voice = st.soundingPosition!;
    final shown = st.layout.pages[st.page];
    expect(shown.firstBlock < voice.block || shown.firstOffset < voice.offset, isTrue,
        reason: 'the narrated paragraph is inside the previous page and is not moved to the top');
    while (st.page > 0) {
      await turn(tester);
      expect(bounds(st.layout.pages[st.page]), control[st.page]);
    }
    expect(bounds(st.layout.pages[st.page]), seen.first);
  });

  for (final distance in [30000, 30001]) {
    testWidgets('real controller: nearby-target boundary, $distance characters from the ready edge', (tester) async {
      final (_, st, _) = await freshPage(tester);
      final original = st.layout;
      final page = original.pages[st.page];
      final book = st.widget.book;
      final last = original.pages.last;
      final absolute = book.charsBefore(last.lastBlock) + last.lastEnd + distance;
      final at = book.placeAt(absolute / book.totalChars);
      expect(book.charsBefore(at.$1) + at.$2, absolute);
      expect(book.chapterOf(at.$1), page.chapter);
      st.goToPosition(ReadingPosition(at.$1, at.$2), user: false);
      expect(st.layout.pages[st.page], same(page), reason: 'until the target is ready the previous page stays');
      if (distance == 30000) {
        expect(st.layout, same(original));
      }
      await tester.pumpAndSettle();
      expect(identical(st.layout, original), distance == 30000);
      expect(st.layout.pages[st.page].contains(at.$1, at.$2), isTrue);
      if (distance == 30001) expect(st.layout.pages.first.firstBlock, at.$1);
    });
  }

  testWidgets('real controller: another chapter starts a new layout even when nearby', (tester) async {
    final (_, st, block) = await freshPage(tester, atChapterEnd: true);
    final original = st.layout;
    final goal = st.widget.book.chapters[2].firstBlock;
    expect(st.widget.book.charsBefore(goal) - st.widget.book.charsBefore(block), lessThan(30000));
    st.goToPosition(ReadingPosition(goal, 0), user: false);
    await tester.pumpAndSettle();
    expect(st.layout, isNot(same(original)));
    expect(st.layout.pages.first.firstBlock, goal);
  });

  testWidgets('the table of contents to an unknown chapter start keeps the previous path', (tester) async {
    final (_, st, _) = await freshPage(tester);
    final original = st.layout;
    final chapter = st.widget.book.chapters[1];
    expect(original.findPage(chapter.firstBlock, 0), isNull);
    await tapCenter(tester);
    await tester.tap(find.byTooltip('Оглавление'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Глава 1').first);
    await tester.pumpAndSettle();
    expect(st.layout, isNot(same(original)));
    expect(st.layout.pages.first.firstBlock, chapter.firstBlock);
    expectFollowingPage(tester);
  });

  testWidgets('real controller: commands during catch-up replace the target, no intermediate pages', (tester) async {
    final (h, st, block) = await freshPage(tester);
    final original = st.layout;
    final shown = original.pages[st.page];
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('next')));
      expect(st.layout, same(original));
      expect(original.pages[st.page], same(shown));
    }
    h.app.services.narration.previous();
    expect(h.app.services.narration.unitStart, ReadingPosition(block + 2, 0));
    final goal = ReadingPosition(block + 2, 0);
    for (var i = 0; original.findPage(goal.block, goal.offset) == null && i < 1000; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      if (original.findPage(goal.block, goal.offset) == null) expect(original.pages[st.page], same(shown));
    }
    await tester.pumpAndSettle();
    expect(st.layout, same(original));
    expectFollowingPage(tester);
  });

  testWidgets('real controller: a command to a ready page cancels the nearby wait', (tester) async {
    final (h, st, block) = await freshPage(tester);
    final original = st.layout;
    final shown = original.pages[st.page];
    h.app.services.narration.next();
    expect(original.findPage(block + 1, 0), isNull);
    expect(st.layout, same(original));
    h.app.services.narration.previous();
    expect(h.app.services.narration.unitStart, ReadingPosition(block, 0));
    await tester.pumpAndSettle();
    expect(st.layout, same(original));
    expect(original.pages[st.page], same(shown), reason: 'the cancelled target does not appear after the catch-up');
    expectFollowingPage(tester);
  });

  testWidgets('real controller: a font change cancels the nearby catch-up and keeps the new target', (tester) async {
    final (h, st, block) = await freshPage(tester);
    final original = st.layout;
    for (var i = 0; i < 3; i++) {
      h.app.services.narration.next();
    }
    expect(st.layout, same(original));
    expect(original.findPage(block + 3, 0), isNull);
    h.app.settings.fontStep++;
    await tester.pump();
    final updated = st.layout;
    await tester.pumpAndSettle();
    expect(st.layout, isNot(same(original)));
    expect(st.layout.pages[st.page].contains(block + 3, 0), isTrue);
    expect(original.isCalculating, isFalse);
    expect(st.layout, same(updated));
    expectFollowingPage(tester);
  });

  for (final playing in [false, true]) {
    testWidgets('real controller: back to a nearby unknown paragraph, sound $playing', (tester) async {
      final (h, st, block) = await freshPage(tester);
      final original = st.layout;
      final shown = original.pages[st.page];
      if (playing) h.app.services.narration.resume();
      await tester.tap(find.byKey(const Key('previous')));
      expect(h.app.services.narration.unitStart, ReadingPosition(block - 1, 0));
      expect(st.layout, same(original));
      expect(original.pages[st.page], same(shown));
      expect(original.isLoadingPrevious, isTrue);
      if (playing) await h.until(() => h.player.playing);
      await tester.pumpAndSettle();
      expect(st.layout, same(original));
      expect(original.pages, contains(same(shown)));
      expect(original.prependedCount, greaterThan(0));
      expectFollowingPage(tester);
    });
  }

  testWidgets('real controller: natural progress beyond the ready edge keeps the layout', (tester) async {
    final (h, st, block) = await freshPage(tester);
    final original = st.layout;
    h.app.services.narration.resume();
    final revision = h.app.services.narration.commandRevision;
    // Fake WAVs give 0.1 seconds per character. Progress crosses the paragraph boundary without catch-up frames.
    for (var i = 0; i < 80 && h.app.services.narration.block == block; i++) {
      h.playbackClock.advance(const Duration(seconds: 5));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(h.app.services.narration.block, greaterThan(block));
    expect(h.app.services.narration.commandRevision, revision);
    expect(st.layout, same(original));
    await h.until(() => h.app.services.narration.state == NarrationState.playing);
    await tester.pumpAndSettle();
    expect(st.layout, same(original));
    expectFollowingPage(tester);
  });

  for (final action in ['resume', 'back']) {
    testWidgets('real controller: $action catches up the nearby place after a manual move away', (tester) async {
      final (h, st, block) = await freshPage(tester);
      final original = st.layout;
      h.app.services.narration.resume();
      original.pause();
      final browse = st.goToPage(-1);
      await tester.pumpAndSettle();
      await browse;
      expect(st.following, isFalse);
      // While the reader looks back, the voice crosses the ready edge. Page frames
      // do not advance the fake audio clock; audio and file operations run separately.
      await h.until(() => h.player.playing);
      final wait = Stopwatch()..start();
      while (h.app.services.narration.block == block) {
        if (wait.elapsed >= const Duration(seconds: 10)) {
          fail('Within 10 s the voice did not leave block $block: ${h.app.services.narration.state}, '
              'player playing: ${h.player.playing}');
        }
        h.playbackClock.advance(const Duration(seconds: 5));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      h.app.services.narration.pause();
      await tester.pump();
      final at = st.soundingPosition!;
      expect(at.block, greaterThan(block));
      expect(original.findPage(at.block, at.offset), isNull);
      final shown = original.pages[st.page];
      await tester.tap(find.byKey(Key(action == 'resume' ? 'play-pause' : 'to-reading-place')));
      expect(st.layout, same(original));
      expect(original.pages[st.page], same(shown));
      if (action == 'resume') await h.until(() => h.player.playing);
      await tester.pumpAndSettle();
      expect(st.layout, same(original));
      expectFollowingPage(tester);
    });
  }
}
