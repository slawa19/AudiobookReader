import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_position_test.dart' show openAt;
import 'support/harness.dart';

void main() {
  testWidgets('панель уводит удерживаемое место с первой страницы: показывается следующая от прежнего начала', (tester) async {
    final p = await pumpPrototype(tester);
    final book = Book(id: 'shorter-page', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 2)],
        blocks: [Block(index: 0, kind: BlockKind.paragraph, text: List.filled(110, 'Текст тут ').join()),
          const Block(index: 1, kind: BlockKind.paragraph, text: 'Звучащий абзац.')], notes: const {});
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    final before = st.layout.pages[st.page];
    expect(before.contains(1, 0), isTrue, reason: 'до панели место голоса на видимой странице');
    final start = (before.firstBlock, before.firstOffset);
    p.narration.demoShow('paused', book: book, fromBlock: 1);
    await tester.pump();
    await tester.pump();
    final at = st.soundingPosition!;
    expect((st.layout.pages.first.firstBlock, st.layout.pages.first.firstOffset), start);
    expect(st.layout.pages.first.contains(at.block, at.offset), isFalse,
        reason: 'с панелью первая страница действительно стала слишком короткой');
    expect(st.page, 1);
    expect(st.layout.pages[st.page].contains(at.block, at.offset), isTrue);
    expect(st.layout.pages[st.page].firstBlock, 0,
        reason: 'на странице остался хвост предыдущего блока, она не начинается с голоса');
    final shown = st.layout.pages[st.page];
    await tester.pump(const Duration(milliseconds: 30));
    expect(st.layout.pages[st.page], same(shown));
    await tester.pumpWidget(const SizedBox());
  });
}
