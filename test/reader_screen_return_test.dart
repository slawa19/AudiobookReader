import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_real_navigation_test.dart' show navigationBook, expectFollowingPage;
import 'support/app_harness.dart';
import 'support/flows.dart';
import 'support/harness.dart' show reader, pumpPrototype;
import 'reader_screen_position_test.dart' show openAt;

void main() {
  testWidgets('возврат из отменённого дальнего поиска продолжает досчёт прежней раскладки', (tester) async {
    final p = await pumpPrototype(tester);
    final book = Book(id: 'return-pending', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 2)],
        blocks: [for (var i = 0; i < 2; i++) Block(index: i, kind: BlockKind.paragraph,
            text: 'Текст тут. ' * 3000)], notes: const {});
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    p.narration.readFrom(book, 0);
    p.narration.pause();
    await tester.pump();
    await tester.pump();
    final original = st.layout;
    final count = original.pages.length;
    expect(original.isComplete, isFalse);
    st.goToPosition(const ReadingPosition(1, 25000));
    p.narration.resume();
    await tester.pump(const Duration(milliseconds: 10));
    expect(st.layout, same(original));
    expect(original.pages.length, greaterThan(count), reason: 'готовые страницы сохранены, хвост продолжает считаться');
    await tester.pumpWidget(const SizedBox());
  });

  for (final action in ['resume', 'back']) {
    testWidgets('настоящий контроллер: $action возвращает прежние границы после листания на ±1 и ±3', (tester) async {
      final h = AppHarness(tester);
      await h.start(fakeTts: true);
      tester.view.physicalSize = const Size(360, 640);
      final file = await h.copy(navigationBook());
      h.files.events.add(file);
      await h.opened();
      var st = reader(tester);
      final book = st.widget.book;
      final move = st.goToPage(1);
      await tester.pumpAndSettle();
      await move;
      final saved = st.layout.pages[st.page].firstOffset;
      expect(saved, greaterThan(0));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text(book.title).first);
      await h.opened();
      st = reader(tester);
      expect(st.layout.pages.first.firstOffset, saved);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await h.until(() => h.player.playing);
      // Голос доходит до середины страницы, оставляя по три готовых страницы с обеих сторон.
      for (var i = 0; i < 100; i++) {
        final page = st.layout.pages[st.page];
        final at = st.soundingPosition!;
        if (st.page >= 3 && at.block == page.firstBlock && at.offset > page.firstOffset + 60 &&
            page.contains(at.block, at.offset + 60)) {
          break;
        }
        h.playbackClock.advance(const Duration(seconds: 5));
        await h.until(() => h.app.services.narration.state == NarrationState.playing);
        await tester.pumpAndSettle();
      }
      h.app.services.narration.pause();
      await tester.pumpAndSettle();
      final originalLayout = st.layout;
      final original = st.layout.pages[st.page];
      final origin = st.page;
      final at = st.soundingPosition!;
      expect(origin, greaterThanOrEqualTo(3));
      expect(at.offset, greaterThan(original.firstOffset + 60));
      expect(original.contains(at.block, at.offset + 60), isTrue);
      for (final distance in [1, 3, -1, -3]) {
        h.app.services.narration.pause();
        final browse = st.goToPage(origin + distance);
        await tester.pumpAndSettle();
        await browse;
        expect(st.following, isFalse);
        if (action == 'resume') {
          await tester.tap(find.byKey(const Key('play-pause')));
          await h.until(() => h.player.playing);
        } else {
          await tester.tap(find.byKey(const Key('to-reading-place')));
        }
        await tester.pumpAndSettle();
        expect(st.layout, same(originalLayout), reason: 'готовая страница не требует новой раскладки');
        expect(st.layout.pages[st.page], same(original), reason: 'границы и положение текста должны сохраниться');
        expectFollowingPage(tester);
      }
      // Начала соседних абзацев также выбирают уже готовые страницы, включая досчитанный префикс.
      final prefix = st.layout.loadPrevious();
      await tester.pumpAndSettle();
      await prefix;
      h.app.services.narration.pause();
      final block = h.app.services.narration.block!;
      final expectedNext = st.layout.pages[st.layout.findPage(block + 1, 0)!];
      final expectedPrevious = st.layout.pages[st.layout.findPage(block, 0)!];
      for (final entry in [('next', expectedNext), ('previous', expectedPrevious)]) {
        await tester.tap(find.byKey(Key(entry.$1)));
        await tester.pumpAndSettle();
        expect(st.layout, same(originalLayout));
        expect(st.layout.pages[st.page], same(entry.$2));
        expectFollowingPage(tester);
      }
    });
  }
}
