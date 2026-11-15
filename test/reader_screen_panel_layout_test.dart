import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_real_navigation_test.dart' show navigationBook, expectFollowingPage;
import 'support/app_harness.dart';
import 'support/flows.dart';
import 'support/harness.dart' show reader;

Future<AppHarness> panelApp(WidgetTester tester, {bool wrapped = true, bool narrow = false}) async {
  final h = AppHarness(tester);
  await h.start(fakeTts: true, textScale: narrow ? 1.3 : 1);
  if (wrapped) {
    // Физический экран Samsung; 4 пикселя на dp. Длинное имя не вытесняет значки из верхней строки.
    tester.view.devicePixelRatio = 4;
    tester.view.physicalSize = const Size(1440, 3120);
    tester.view.padding = const FakeViewPadding(top: 128, bottom: 192);
    tester.view.viewPadding = const FakeViewPadding(top: 128, bottom: 192);
    h.app.settings.voice = 'Pulcherrima';
  } else {
    tester.view.physicalSize = const Size(360, 640);
    h.app.settings.voice = 'Aoede';
  }
  if (narrow) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 48);
    h.app.settings.language = 'de';
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
  testWidgets('320 dp ×1,3 de: значки, preparing и системный отступ не меняют геометрию', (tester) async {
    final h = await panelApp(tester, narrow: true);
    final st = reader(tester);
    final height = st.columnSize.height;
    final voice = tester.getRect(find.byKey(const Key('voice-chip')));
    final close = tester.getRect(find.byKey(const Key('player-close')));
    final original = st.layout;
    await swipePage(tester, 1);
    final shown = st.layout.pages[st.page];
    final bounds = (shown.firstBlock, shown.firstOffset, shown.lastBlock, shown.lastEnd);
    for (var i = 0; i < 3; i++) {
      tester.view.viewPadding = const FakeViewPadding();
      tester.view.padding = const FakeViewPadding();
      await tester.pump(const Duration(milliseconds: 16));
      expect(st.columnSize.height, height);
      expect(tester.getRect(find.byKey(const Key('voice-chip'))), voice);
      expect(tester.getRect(find.byKey(const Key('player-close'))), close);
      final size = tester.getSize(find.byKey(const Key('to-reading-place')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(st.layout, same(original));
      final p = st.layout.pages[st.page];
      expect((p.firstBlock, p.firstOffset, p.lastBlock, p.lastEnd), bounds);
    }
    await h.until(() => h.app.queue.inFlight == 0);
    h.app.settings.voice = 'Achernar';
    h.app.services.narration.resume();
    final preparing = st.layout.pages[st.page];
    for (var frame = 0; frame < 140; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(st.columnSize.height, height);
      expect(tester.getRect(find.byKey(const Key('player-close'))), close);
    }
    expect(st.layout.pages, contains(same(preparing)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('постоянная геометрия с коротким именем голоса', (tester) async {
    final h = await panelApp(tester, wrapped: false);
    final height = reader(tester).columnSize.height;
    await swipePage(tester, 1);
    expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
    expect(reader(tester).columnSize.height, height, reason: 'старый тест не проходил через смену высоты');
    expect(h.app.settings.voice, 'Aoede');
  });

  for (final action in ['resume', 'back', 'next', 'previous', 'backward', 'auto']) {
    testWidgets('постоянная панель: $action сохраняет прежнюю раскладку', (tester) async {
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
      expect(st.columnSize.height, height, reason: 'значок не меняет область страницы');
      final detachedHeight = st.columnSize.height;
      expect(tester.getSize(find.byKey(const Key('player-panel'))).height, panelHeight);
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
          expect(st.columnSize.height, detachedHeight, reason: 'preparing не меняет область страницы');
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
      expect(st.columnSize.height, size.height);
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
