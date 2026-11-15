import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_real_navigation_test.dart' show navigationBook, expectFollowingPage;
import 'support/app_harness.dart';
import 'support/flows.dart';
import 'support/harness.dart' show reader;

Future<AppHarness> panelApp(WidgetTester tester, {bool wrapped = true}) async {
  final h = AppHarness(tester);
  await h.start(fakeTts: true);
  if (wrapped) {
    // Физический экран Samsung; 4 пикселя на dp. Длинное имя настоящего голоса переносит кнопку ниже.
    tester.view.devicePixelRatio = 4;
    tester.view.physicalSize = const Size(1440, 3120);
    tester.view.padding = const FakeViewPadding(top: 128, bottom: 192);
    tester.view.viewPadding = const FakeViewPadding(top: 128, bottom: 192);
    h.app.settings.voice = 'Pulcherrima';
  } else {
    tester.view.physicalSize = const Size(360, 640);
    h.app.settings.voice = 'Aoede';
  }
  final file = await h.copy(navigationBook());
  h.files.events.add(file);
  await h.opened();
  await tapCenter(tester);
  await tester.tap(find.byKey(const Key('listen')));
  await h.until(() => h.app.services.narration.state == NarrationState.playing);
  await tester.pumpAndSettle();
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.byKey(const Key('next')));
    await h.until(() => h.app.services.narration.state == NarrationState.playing);
    await tester.pumpAndSettle();
  }
  h.app.services.narration.pause();
  await tester.pumpAndSettle();
  return h;
}

Future<void> swipePage(WidgetTester tester, int direction) async {
  final st = reader(tester);
  final area = tester.getRect(find.byKey(const Key('page-area')));
  await tester.dragFrom(Offset(area.center.dx, st.pagePadding.top + st.columnSize.height * 0.4),
      Offset(-area.width * 0.75 * direction, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('геометрия второго круга: короткое имя голоса оставляет кнопку в одной строке', (tester) async {
    final h = await panelApp(tester, wrapped: false);
    final height = reader(tester).columnSize.height;
    await swipePage(tester, 1);
    expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
    expect(reader(tester).columnSize.height, height, reason: 'старый тест не проходил через смену высоты');
    expect(h.app.settings.voice, 'Aoede');
  });

  for (final action in ['resume', 'back', 'next', 'previous', 'backward', 'auto']) {
    testWidgets('панель меняет высоту: $action возвращает прежнюю раскладку', (tester) async {
      final h = await panelApp(tester);
      final st = reader(tester);
      if (action == 'previous') {
        final prefix = st.layout.loadPrevious();
        await tester.pumpAndSettle();
        await prefix;
      }
      final originalLayout = st.layout;
      final original = st.layout.pages[st.page];
      final height = st.columnSize.height;
      final panelHeight = tester.getSize(find.byKey(const Key('player-panel'))).height;
      final at = st.soundingPosition!;
      expect(original.firstBlock, lessThan(at.block), reason: 'над звучащим абзацем есть предыдущий текст');
      expect(original.fragments.firstWhere((f) => f.block == at.block).top, greaterThan(st.pageStyle.lineHeight));
      if (action == 'auto' || action == 'next' || action == 'previous') h.app.services.narration.resume();
      final revision = h.app.services.narration.commandRevision;
      final direction = action == 'backward' ? -1 : 1;
      await swipePage(tester, direction);
      expect(st.following, isFalse);
      expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
      expect(st.columnSize.height, lessThan(height), reason: 'кнопка действительно уменьшает страницу');
      final detachedHeight = st.columnSize.height;
      expect(tester.getSize(find.byKey(const Key('player-panel'))).height, greaterThan(panelHeight));
      await swipePage(tester, direction);
      var expected = original;
      if (action == 'back') {
        await tester.tap(find.byKey(const Key('to-reading-place')));
        await tester.pump();
        expect(find.byKey(const Key('to-reading-place')), findsNothing, reason: 'кнопка исчезает сразу');
      } else if (action == 'next' || action == 'previous') {
        final block = at.block + (action == 'next' ? 1 : -1);
        expected = originalLayout.pages[originalLayout.findPage(block, 0)!];
        if (action == 'next') {
          await h.until(() => h.app.queue.inFlight == 0);
          h.engine.enqueue(delay: const Duration(milliseconds: 100));
        }
        await tester.tap(find.byKey(Key(action)));
        await tester.pump();
        await tester.pump();
        if (action == 'next') {
          expect(st.columnSize.height, greaterThan(detachedHeight), reason: 'кнопка ушла, появилась строка preparing');
          expect(st.columnSize.height, lessThan(height), reason: 'это третий, промежуточный размер панели');
        }
        await h.until(() => h.app.services.narration.state == NarrationState.playing);
      } else if (action == 'auto') {
        for (var i = 0; i < 100 && !st.following; i++) {
          h.playbackClock.advance(const Duration(seconds: 5));
          await h.until(() => h.app.services.narration.state == NarrationState.playing);
          await tester.pumpAndSettle();
          final voice = st.soundingPosition!;
          if (st.layout.pages[st.page].contains(voice.block, voice.offset)) break;
        }
        final voice = st.soundingPosition!;
        expect(st.layout.pages[st.page].contains(voice.block, voice.offset), isTrue, reason: 'голос дошёл до показанной страницы');
        expect(h.app.services.narration.commandRevision, revision, reason: 'новых команд звука не было');
        expected = originalLayout.pages[originalLayout.findPage(voice.block, voice.offset)!];
      } else {
        await tester.tap(find.byKey(const Key('play-pause')));
        await h.until(() => h.player.playing);
      }
      await tester.pumpAndSettle();
      expect(st.columnSize.height, height, reason: 'после исчезновения кнопки размер вернулся');
      final page = st.layout.pages[st.page];
      expect((page.firstBlock, page.firstOffset, page.lastBlock, page.lastEnd),
          (expected.firstBlock, expected.firstOffset, expected.lastBlock, expected.lastEnd),
          reason: 'сохраняются начало, конец и текст над абзацем');
      expect(page, same(expected));
      expect(st.layout, same(originalLayout));
      expectFollowingPage(tester);
    });
  }

  for (final change in ['font', 'window', 'theme']) {
    testWidgets('возврат после изменения $change учитывает типографику и настоящее окно', (tester) async {
      final h = await panelApp(tester);
      final st = reader(tester);
      final original = st.layout;
      final page = st.layout.pages[st.page];
      final size = st.columnSize;
      final font = st.pageStyle.fontSize;
      await swipePage(tester, 1);
      expect(st.columnSize.height, lessThan(size.height));
      if (change == 'font') {
        h.app.settings.fontStep++;
      } else if (change == 'window') {
        tester.view.physicalSize = const Size(1440, 2960);
      } else {
        h.app.settings.theme = ThemeChoice.sepia;
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('to-reading-place')));
      await tester.pumpAndSettle();
      if (change == 'theme') {
        expect(st.layout, same(original), reason: 'цвета не меняют раскладку');
        expect(st.layout.pages[st.page], same(page));
      } else {
        expect(st.layout, isNot(same(original)), reason: 'старые метрики после смены окна или шрифта недействительны');
        if (change == 'font') {
          expect(st.pageStyle.fontSize, greaterThan(font));
        } else {
          expect(st.columnSize.height, size.height - 40);
          tester.view.physicalSize = const Size(1440, 3120);
          await tester.pumpAndSettle();
          expect(st.layout, isNot(same(original)), reason: 'прошлый размер окна не хранится как высота панели');
        }
      }
      expectFollowingPage(tester);
    });
  }
}
