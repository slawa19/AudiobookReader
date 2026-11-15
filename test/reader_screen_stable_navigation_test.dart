import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_continue_layout_test.dart' show freshPage;
import 'reader_screen_properties_test.dart' show propertyApp, pageThird, textBounds;
import 'reader_screen_real_navigation_test.dart' show listeningApp, expectFollowingPage;
import 'support/harness.dart' show reader;

Future<void> frames(WidgetTester tester, [int count = 28]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('D1: ожидание первой страницы назад не выключает следование до показа', (tester) async {
    final h = await propertyApp(tester);
    h.app.services.narration.pause();
    await frames(tester);
    final st = reader(tester);
    final before = textBounds(st);
    expect(st.page, 0);
    final move = st.goToPage(-1);
    expect(textBounds(st), before);
    expect(st.following, isTrue, reason: 'пока показан прежний текст, читатель ещё не переместился');
    await frames(tester, 120);
    await move;
    final after = textBounds(st);
    final book = st.widget.book;
    expect(book.charsBefore(after.$3) + after.$4, book.charsBefore(before.$1) + before.$2);
    expect(st.following, isFalse);
  });

  testWidgets('D5: возврат через 16 мс отменяет уход с уже показанной страницы голоса', (tester) async {
    final h = await listeningApp(tester);
    h.app.services.narration.pause();
    await frames(tester);
    final st = reader(tester);
    st.goToPage(1);
    await frames(tester);
    st.goToPage(0);
    await frames(tester);
    expect(st.following, isFalse);
    final before = textBounds(st);
    await tester.tapAt(pageThird(tester, true));
    await frames(tester, 1);
    await tester.tap(find.byKey(const Key('to-reading-place')));
    await frames(tester);
    expect(textBounds(st), before);
    expectFollowingPage(tester);
  });

  testWidgets('D1: событие идущего звука не отменяет ожидаемое ручное касание', (tester) async {
    final h = await propertyApp(tester);
    final st = reader(tester);
    final before = textBounds(st);
    st.goToPage(-1);
    h.playbackClock.advance(const Duration(seconds: 1));
    await frames(tester, 120);
    final after = textBounds(st);
    final book = st.widget.book;
    expect(book.charsBefore(after.$3) + after.$4, book.charsBefore(before.$1) + before.$2);
    expect(st.following, isFalse);
  });

  testWidgets('D6: отменённое малое перетаскивание догоняет команду звука на паузе', (tester) async {
    final h = await listeningApp(tester);
    final st = reader(tester);
    h.app.services.narration.pause();
    await frames(tester);
    final gesture = await tester.startGesture(pageThird(tester, true));
    await gesture.moveBy(const Offset(-28, 0));
    await frames(tester, 2);
    h.app.services.narration.next();
    final at = st.soundingPosition!;
    expect(st.layout.pages[st.page].contains(at.block, at.offset), isFalse);
    await gesture.cancel();
    await frames(tester, 40);
    expectFollowingPage(tester);
  });

  for (final count in [1, 2]) {
    testWidgets('D7: $count касания во время близкого досчёта не теряются', (tester) async {
      final (h, st, block) = await freshPage(tester);
      final original = st.layout;
      final before = textBounds(st);
      h.app.services.narration.next();
      expect(original.findPage(block + 1, 0), isNull);
      for (var i = 0; i < count; i++) {
        await tester.tapAt(pageThird(tester, true));
      }
      await frames(tester, 40);
      expect(st.layout, same(original));
      expect(st.page, count);
      final first = original.pages[1];
      expect((first.firstBlock, first.firstOffset), (before.$3, before.$4));
      expect(st.following, isFalse);
    });
  }

  for (final source in ['voice', 'page']) {
    testWidgets('D7: досчёт прежней цели $source назад не заменяет страницу под новым жестом', (tester) async {
      final h = await propertyApp(tester);
      h.app.services.narration.pause();
      await frames(tester);
      final st = reader(tester);
      final before = textBounds(st);
      if (source == 'voice') {
        h.app.services.narration.previous();
      } else {
        st.goToPage(-1);
      }
      expect(st.layout.isLoadingPrevious, isTrue);
      final gesture = await tester.startGesture(pageThird(tester, true));
      await gesture.moveBy(const Offset(-28, 0));
      await frames(tester, 200);
      await gesture.moveBy(Offset(-st.columnSize.width * 0.8, 0));
      await frames(tester, 2);
      await gesture.up();
      await frames(tester, 60);
      final after = textBounds(st);
      expect((after.$1, after.$2), (before.$3, before.$4));
      expect(st.following, isFalse);
    });
  }
}
