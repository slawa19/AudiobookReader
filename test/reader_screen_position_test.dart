import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

Book millionBook() => Book(id: 'three-million', title: 'Три миллиона', author: '', language: 'ru',
    chapters: const [Chapter(title: 'Глава', level: 1, firstBlock: 0, blockCount: 1)],
    blocks: [Block(index: 0, kind: BlockKind.paragraph, text: List.filled(300000, 'Текст тут ').join())],
    notes: const {});

Future<ReaderScreenState> openAt(WidgetTester tester, Prototype p, Book book, ReadingPosition at) async {
  p.library.savePosition(book.id, at);
  tester.state<NavigatorState>(find.byType(Navigator).first).push(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(services: p.services, book: book)));
  await tester.pump();
  await tester.pump();
  return reader(tester);
}

void main() {
  final measured = <(int, int, int)>[];
  setUp(() => debugPageMeasurement = (b, a, z) => measured.add((b, a, z)));
  tearDown(() {
    debugPageMeasurement = null;
    measured.clear();
  });

  testWidgets('3 миллиона: открытие на 90 % измеряет только текст от позиции; шрифт держит якорь сразу', (tester) async {
    final p = await pumpPrototype(tester);
    final book = millionBook();
    expect(book.totalChars, 3000000);
    final st = await openAt(tester, p, book, const ReadingPosition(0, 2700000));
    expect(find.byType(BookPage), findsWidgets);
    expect(measured, isNotEmpty);
    expect(measured.every((r) => r.$2 >= 2700000), isTrue,
        reason: 'первая страница не должна измерять 2,7 миллиона знаков перед местом');
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(16384));
    expect(st.layout.pages[st.page].firstOffset, 2700000);
    measured.clear();
    p.settings.fontStep++;
    await tester.pump();
    expect(st.layout.pages[st.page].firstOffset, 2700000);
    expect(measured, isNotEmpty);
    expect(measured.every((r) => r.$2 >= 2700000), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(16384));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('3 миллиона: ползунок 50 % открывает страницу сразу без измерения предшествующего текста', (tester) async {
    final p = await pumpPrototype(tester);
    final book = millionBook();
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.tapAt(tester.getRect(find.byKey(const Key('page-area'))).center);
    await tester.pump();
    measured.clear();
    tester.widget<Slider>(find.byKey(const Key('book-slider'))).onChangeEnd!(0.5);
    await tester.pump();
    expect(measured, isNotEmpty, reason: 'целевая страница считается в этой команде, а не ждёт хвоста очереди');
    expect(measured.every((r) => r.$2 >= 1500000), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(16384));
    expect(st.layout.pages[st.page].firstOffset, 1500000);
    expect(p.library.positionOf(book.id)?.offset, 1500000);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('далёкие оглавление, голос и возврат к голосу начинают страницу от места', (tester) async {
    final p = await pumpPrototype(tester);
    final text = millionBook().blocks.single.text.substring(0, 1000000);
    final book = Book(id: 'million-chapters', title: 'Главы', author: '', language: 'ru',
        chapters: [for (var i = 0; i < 3; i++) Chapter(title: 'Глава $i', level: 1, firstBlock: i, blockCount: 1)],
        blocks: [for (var i = 0; i < 3; i++) Block(index: i, kind: BlockKind.paragraph, text: text)], notes: const {});
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.tapAt(tester.getRect(find.byKey(const Key('page-area'))).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Оглавление'));
    await tester.pumpAndSettle();
    measured.clear();
    await tester.tap(find.byKey(const Key('chapter-2')));
    await tester.pump();
    await tester.pump();
    expect((st.layout.pages[st.page].firstBlock, st.layout.pages[st.page].firstOffset), (2, 0));
    expect(measured, isNotEmpty);
    expect(measured.every((r) => r.$1 == 2), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(16384));
    measured.clear();
    p.narration.demoShow('paused', book: book, fromBlock: 0);
    await tester.pump();
    await tester.pump();
    final sound = st.soundingPosition!;
    expect((st.layout.pages[st.page].firstBlock, st.layout.pages[st.page].firstOffset), (0, sound.offset));
    expect(measured.every((r) => r.$1 == 0 && r.$2 >= sound.offset), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(32768));
    st.goToPosition(const ReadingPosition(2, 700000));
    await tester.pump();
    await tester.pump();
    expect(st.following, isFalse);
    measured.clear();
    tester.widget<FilledButton>(find.byKey(const Key('to-reading-place'))).onPressed!();
    await tester.pump();
    await tester.pump();
    expect(st.following, isTrue);
    expect(st.layout.pages[st.page].firstOffset, sound.offset);
    expect(measured, isNotEmpty);
    expect(measured.every((r) => r.$1 == 0 && r.$2 >= sound.offset), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(32768));
    await tester.pumpWidget(const SizedBox());
  });
}
