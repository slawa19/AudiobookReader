import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_position_test.dart' show openAt;
import 'support/harness.dart';

void main() {
  testWidgets('the panel moves the held place off the first page: the next one is shown from the previous start', (tester) async {
    final p = await pumpPrototype(tester);
    final book = Book(id: 'shorter-page', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 2)],
        blocks: [Block(index: 0, kind: BlockKind.paragraph, text: List.filled(110, 'Текст тут ').join()),
          const Block(index: 1, kind: BlockKind.paragraph, text: 'Звучащий абзац.')], notes: const {});
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    final before = st.layout.pages[st.page];
    expect(before.contains(1, 0), isTrue, reason: 'before the panel the voice place is on the visible page');
    final start = (before.firstBlock, before.firstOffset);
    p.narration.demoShow('paused', book: book, fromBlock: 1);
    await tester.pump();
    await tester.pump();
    final at = st.soundingPosition!;
    expect((st.layout.pages.first.firstBlock, st.layout.pages.first.firstOffset), start);
    expect(st.layout.pages.first.contains(at.block, at.offset), isFalse,
        reason: 'with the panel the first page really became too short');
    expect(st.page, 1);
    expect(st.layout.pages[st.page].contains(at.block, at.offset), isTrue);
    expect(st.layout.pages[st.page].firstBlock, 0,
        reason: 'the page kept the tail of the previous block, it does not start with the voice');
    final shown = st.layout.pages[st.page];
    await tester.pump(const Duration(milliseconds: 30));
    expect(st.layout.pages[st.page], same(shown));
    await tester.pumpWidget(const SizedBox());
  });
}
