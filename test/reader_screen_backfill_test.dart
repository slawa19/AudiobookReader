import 'dart:convert';

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_real_navigation_test.dart' show expectFullProsePage, expectFollowingPage;
import 'support/app_harness.dart';
import 'support/flows.dart';
import 'support/harness.dart' show reader;

List<int> backfillBook() => utf8.encode('''<FictionBook><description><title-info>
<book-title>Обратные страницы</book-title><lang>ru</lang></title-info></description><body>
${List.generate(3, (c) => '<section><title><p>Глава $c</p></title>${List.generate(8, (b) => '<p>${List.filled(9, 'Утром путешественник осмотрел дорогу и продолжил путь. Вдали показались деревья, за которыми открывалась широкая долина. Он остановился у реки и посмотрел на другой берег.').join(' ')}</p>').join()}</section>').join()}
</body></FictionBook>''');

Future<AppHarness> openBackfillBook(WidgetTester tester) async {
  final h = AppHarness(tester);
  await h.start(fakeTts: true);
  final file = await h.copy(backfillBook());
  h.files.events.add(file);
  await h.opened();
  return h;
}

Future<void> turn(WidgetTester tester, {bool forward = false}) async {
  final st = reader(tester);
  final before = st.layout.pages[st.page];
  final area = tester.getRect(find.byKey(const Key('page-area')));
  await tester.tapAt(Offset(forward ? area.right - 12 : area.left + 12, st.pagePadding.top + 120));
  await tester.pumpAndSettle();
  final after = st.layout.pages[st.page];
  expect((after.firstBlock, after.firstOffset, after.lastBlock, after.lastEnd),
      isNot((before.firstBlock, before.firstOffset, before.lastBlock, before.lastEnd)),
      reason: 'касание действительно перелистнуло текст страницы');
  expectFullProsePage(st);
}

void main() {
  testWidgets('настоящий контроллер: вперёд дважды и касания назад не показывают короткий префикс', (tester) async {
    final h = await openBackfillBook(tester);
    final st = reader(tester);
    final chapter = st.widget.book.chapters[1];
    st.goToPosition(ReadingPosition(chapter.firstBlock + 3, 0));
    await tester.pumpAndSettle();
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await h.until(() => h.player.playing);
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('next')));
      await h.until(() => h.player.playing);
      await tester.pumpAndSettle();
    }
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    final visited = <BookPageLayout>[st.layout.pages[st.page]];
    for (final taps in [1, 2, 5]) {
      for (var i = 0; i < taps; i++) {
        await turn(tester);
        visited.add(st.layout.pages[st.page]);
      }
    }
    for (var i = 0; st.layout.pages[st.page].chapter == 1 && i < 40; i++) {
      await turn(tester);
      visited.add(st.layout.pages[st.page]);
    }
    expect(visited.last.chapter, 0);
    expect(visited[visited.length - 2].firstBlock, chapter.firstBlock);
    expect(visited[visited.length - 2].firstOffset, 0);
    for (final expected in visited.reversed.skip(1)) {
      await turn(tester, forward: true);
      expect(st.layout.pages[st.page], same(expected), reason: 'возврат вперёд сохраняет все границы');
    }
    await turn(tester);
    final page = st.layout.pages[st.page];
    h.app.settings.fontStep++;
    await tester.pumpAndSettle();
    expect((st.layout.pages[st.page].firstBlock, st.layout.pages[st.page].firstOffset),
        (page.firstBlock, page.firstOffset), reason: 'шрифт держит начало текущей страницы после досчёта назад');
  });

  for (final entry in ['saved', 'toc', 'read']) {
    testWidgets('настоящий контроллер: полные страницы назад после $entry', (tester) async {
      final h = await openBackfillBook(tester);
      var st = reader(tester);
      final book = st.widget.book;
      final block = book.chapters[1].firstBlock + 4;
      if (entry == 'saved') {
        // Сохраняется начало реально показанной строки, затем книга открывается заново.
        st.goToPosition(ReadingPosition(block, 0));
        await tester.pumpAndSettle();
        await turn(tester, forward: true);
        final page = st.layout.pages[st.page];
        final saved = ReadingPosition(page.firstBlock, page.firstOffset);
        expect(saved.offset, greaterThan(0));
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text(book.title).first);
        await h.opened();
        st = reader(tester);
        expect((st.layout.pages[st.page].firstBlock, st.layout.pages[st.page].firstOffset),
            (saved.block, saved.offset));
      } else if (entry == 'toc') {
        await tapCenter(tester);
        await tester.tap(find.byTooltip('Оглавление'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chapter-2')));
        await tester.pumpAndSettle();
        expect(st.layout.pages[st.page].chapter, 2);
      } else {
        st.goToPosition(ReadingPosition(block, 0));
        await tester.pumpAndSettle();
        await tester.longPressAt(blockCenter(tester, block));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('read-from-here')));
        await h.until(() => h.player.playing);
        await tester.pumpAndSettle();
        h.app.services.narration.pause();
        await tester.pumpAndSettle();
      }
      final history = <BookPageLayout>[st.layout.pages[st.page]];
      for (var i = 0; i < 5; i++) {
        await turn(tester);
        history.add(st.layout.pages[st.page]);
      }
      for (final page in history.reversed.skip(1)) {
        await turn(tester, forward: true);
        expect(st.layout.pages[st.page], same(page));
      }
    });
  }

  testWidgets('голос в перекрытии не уводит с первой страницы главы; подсветка остаётся', (tester) async {
    final h = await openBackfillBook(tester);
    final st = reader(tester);
    final block = st.widget.book.chapters[1].firstBlock + 1;
    st.goToPosition(ReadingPosition(block, 0));
    await tester.pumpAndSettle();
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await h.until(() => h.player.playing);
    await tester.pumpAndSettle();
    h.playbackClock.advance(const Duration(seconds: 5));
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    await turn(tester);
    final first = st.layout.pages[st.page];
    expect(first.firstBlock, st.widget.book.chapters[1].firstBlock);
    final at = st.soundingPosition!;
    expect(first.contains(at.block, at.offset), isTrue);
    expect(st.layout.findPage(at.block, at.offset), st.page + 1);
    await tester.tap(find.byKey(const Key('play-pause')));
    await h.until(() => h.player.playing);
    await tester.pumpAndSettle();
    expect(st.layout.pages[st.page], same(first));
    expectFollowingPage(tester);
  });
}
