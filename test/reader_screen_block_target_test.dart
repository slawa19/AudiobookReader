import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_position_test.dart' show openAt;
import 'support/harness.dart';
import 'support/pagination.dart';

Book targetBook() => Book(id: 'block-target', title: 'Цель', author: '', language: 'ru',
    chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 2)],
    blocks: [Block(index: 0, kind: BlockKind.paragraph, text: List.filled(160, 'Первый абзац книги. ').join()),
      Block(index: 1, kind: BlockKind.paragraph, text: List.filled(70, 'Нормальные слова составляют предложение. ').join())],
    notes: const {});

void main() {
  testWidgets('новая цель отменяет незавершённый досчёт назад и сохраняет показанную страницу', (tester) async {
    final p = await pumpPrototype(tester);
    final book = Book(id: 'cancel-prefix', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 1),
          Chapter(title: '', level: 1, firstBlock: 1, blockCount: 1)],
        blocks: [const Block(index: 0, kind: BlockKind.paragraph, text: 'Предыдущая глава.'),
          Block(index: 1, kind: BlockKind.paragraph, text: List.filled(30000, 'Текст тут ').join())],
        notes: const {});
    final st = await openAt(tester, p, book, const ReadingPosition(1, 0));
    final shown = st.layout.pages[st.page];
    final back = st.goToPage(-1);
    expect(st.layout.isLoadingPrevious, isTrue);
    st.goToPosition(const ReadingPosition(1, 15000));
    await back;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      expect(st.layout.pages[st.page], same(shown), reason: 'отменённый расчёт не подменяет страницу');
    }
    expect(st.layout.isLoadingPrevious, isFalse);
    await tester.pumpAndSettle();
    expect(st.layout.pages[st.page].contains(1, 15000), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('новая цель блока отменяет прежнее ожидание готовой страницы', (tester) async {
    final p = await pumpPrototype(tester);
    final book = Book(id: 'replace-waiting', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 1)],
        blocks: [Block(index: 0, kind: BlockKind.paragraph, text: List.filled(30000, 'Текст тут ').join())],
        notes: const {});
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    final old = st.goToPage(3);
    st.goToPosition(const ReadingPosition(0, 15000));
    await old;
    await tester.pumpAndSettle();
    expect(st.layout.pages[st.page].contains(0, 15000), isTrue);
    await tester.pump(const Duration(milliseconds: 20));
    expect(st.layout.pages[st.page].contains(0, 15000), isTrue, reason: 'старая очередь не возвращает экран назад');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('повторное использование блока после досчёта назад не сдвигает страницу второй раз', (tester) async {
    final p = await pumpPrototype(tester);
    final book = Book(id: 'reuse-prefix', title: '', author: '', language: 'ru',
        chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 1)],
        blocks: [Block(index: 0, kind: BlockKind.paragraph, text: List.filled(30000, 'Текст тут ').join())],
        notes: const {});
    final st = await openAt(tester, p, book, const ReadingPosition(0, 1800));
    final previous = st.layout.loadPrevious();
    for (var i = 0; st.layout.prependedCount == 0 && i < 1000; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await previous;
    expect(st.layout.prependedCount, greaterThan(0));
    expect(st.layout.isComplete, isFalse);
    final expected = st.layout.pages[st.layout.pageOf(0, 1953)];
    st.goToPosition(const ReadingPosition(0, 1953));
    await tester.pump(const Duration(milliseconds: 20));
    expect(st.layout.pages[st.page], same(expected));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('смена шрифта при поиске и новая цель используют новые метрики', (tester) async {
    final p = await pumpPrototype(tester);
    final book = targetBook();
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    st.goToPosition(const ReadingPosition(1, 2500));
    p.settings.fontStep++;
    await tester.pump();
    st.goToPosition(const ReadingPosition(0, 1500));
    await tester.pumpAndSettle();
    final reference = await paginate(tester: tester, book: book, style: st.pageStyle, column: st.columnSize);
    final expected = reference.pages[reference.pageOf(0, 1500)];
    final page = st.layout.pages[st.page];
    expect((page.firstBlock, page.firstOffset, page.lastEnd),
        (expected.firstBlock, expected.firstOffset, expected.lastEnd));
    reference.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ползунок внутри слова выбирает страницу раскладки блока; начало блока открывается ровно с него', (tester) async {
    final p = await pumpPrototype(tester);
    final book = targetBook();
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.tapAt(tester.getRect(find.byKey(const Key('page-area'))).center);
    await tester.pumpAndSettle();
    final offset = book.blocks[1].text.indexOf('слова', 1400) + 2;
    final fraction = (book.charsBefore(1) + offset) / book.totalChars;
    expect(book.placeAt(fraction), (1, offset));
    final reference = await paginate(tester: tester, book: book, style: st.pageStyle,
        column: st.columnSize, block: 1);
    final expected = reference.pages[reference.pageOf(1, offset)];
    expect(expected.firstOffset, greaterThan(0));
    expect(expected.firstOffset, lessThan(offset), reason: 'цель намеренно внутри слова, не на начале строки');
    tester.widget<Slider>(find.byKey(const Key('book-slider'))).onChangeEnd!(fraction);
    await tester.pumpAndSettle();
    final page = st.layout.pages[st.page];
    expect(page.contains(1, offset), isTrue);
    expect((page.firstBlock, page.firstOffset), (expected.firstBlock, expected.firstOffset));
    expect(p.library.positionOf(book.id), ReadingPosition(page.firstBlock, page.firstOffset));
    tester.widget<Slider>(find.byKey(const Key('book-slider'))).onChangeEnd!(book.charsBefore(1) / book.totalChars);
    await tester.pumpAndSettle();
    expect((st.layout.pages[st.page].firstBlock, st.layout.pages[st.page].firstOffset), (1, 0));
    reference.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('конец прослушивания показывает хвост последнего абзаца, а не последний знак', (tester) async {
    final p = await pumpPrototype(tester);
    final book = targetBook();
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    p.narration.demoShow('end', book: book);
    // Первые кадры замеряют реальную высоту панели до хода таймеров расчёта блока.
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    final reference = await paginate(tester: tester, book: book, style: st.pageStyle,
        column: st.columnSize, block: 1);
    final expected = reference.pages.last;
    final page = st.layout.pages[st.page];
    expect((page.firstBlock, page.firstOffset), (expected.firstBlock, expected.firstOffset));
    expect(page.lastEnd - page.firstOffset, greaterThan(1));
    expect(st.layout.endsBook(page), isTrue);
    expect(p.library.isFinished(book.id), isTrue);
    reference.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('сохранённое начало уже показанной строки не округляется к началу блока', (tester) async {
    final p = await pumpPrototype(tester);
    final book = targetBook();
    final st = await openAt(tester, p, book, const ReadingPosition(1, 0));
    await tester.pump(const Duration(milliseconds: 30));
    final line = st.layout.pages[1].firstOffset;
    expect(line, greaterThan(0));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    final reopened = await openAt(tester, p, book, ReadingPosition(1, line));
    expect(reopened.layout.pages[reopened.page].firstOffset, line);
    p.settings.fontStep++;
    await tester.pump();
    expect(reopened.layout.pages[reopened.page].firstOffset, line);
    await tester.pumpWidget(const SizedBox());
  });
}
