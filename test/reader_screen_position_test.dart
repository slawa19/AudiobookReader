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

// The saved line of a huge paragraph is checked separately. Arbitrary targets are calculated from
// the start of the paragraph, so checking independence of book size needs ordinary separate paragraphs.
Book millionParagraphBook() => Book(id: 'million-paragraphs', title: 'Три миллиона', author: '', language: 'ru',
    chapters: [for (var i = 0; i < 3; i++) Chapter(title: 'Глава $i', level: 1, firstBlock: i * 1000, blockCount: 1000)],
    blocks: [for (var i = 0; i < 3000; i++) Block(index: i, kind: BlockKind.paragraph,
        text: List.filled(100, 'Текст тут ').join())], notes: const {});

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

  testWidgets('3 million: opening at 90 % measures only the text from the position; a font change keeps the anchor immediately', (tester) async {
    final p = await pumpPrototype(tester);
    final book = millionBook();
    expect(book.totalChars, 3000000);
    final st = await openAt(tester, p, book, const ReadingPosition(0, 2700000));
    expect(find.byType(BookPage), findsWidgets);
    expect(measured, isNotEmpty);
    expect(measured.every((r) => r.$2 >= 2700000), isTrue,
        reason: 'the first page must not measure 2.7 million characters before the place');
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

  testWidgets('3 million: the 50 % slider calculates only the target block, not the previous chapters', (tester) async {
    final p = await pumpPrototype(tester);
    final book = millionParagraphBook();
    final st = await openAt(tester, p, book, const ReadingPosition(0, 0));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.tapAt(tester.getRect(find.byKey(const Key('page-area'))).center);
    await tester.pump();
    measured.clear();
    const fraction = 0.500123;
    final target = book.placeAt(fraction);
    tester.widget<Slider>(find.byKey(const Key('book-slider'))).onChangeEnd!(fraction);
    await tester.pump();
    expect(measured, isNotEmpty, reason: 'the target page is calculated in this command, not after the queue tail');
    expect(measured.every((r) => r.$1 >= target.$1), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(16384));
    final page = st.layout.pages[st.page];
    expect(page.contains(target.$1, target.$2), isTrue);
    expect((page.firstBlock, page.firstOffset), (target.$1, 0));
    expect(p.library.positionOf(book.id), ReadingPosition(page.firstBlock, page.firstOffset));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a distant table of contents, voice and voice return start the page at the place', (tester) async {
    final p = await pumpPrototype(tester);
    final book = millionParagraphBook();
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
    expect((st.layout.pages[st.page].firstBlock, st.layout.pages[st.page].firstOffset), (2000, 0));
    expect(measured, isNotEmpty);
    expect(measured.every((r) => r.$1 >= 2000), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(16384));
    measured.clear();
    p.narration.demoShow('paused', book: book, fromBlock: 0);
    await tester.pump();
    await tester.pump();
    final sound = st.soundingPosition!;
    expect((st.layout.pages[st.page].firstBlock, st.layout.pages[st.page].firstOffset), (0, 0));
    expect(st.layout.pages[st.page].contains(0, sound.offset), isTrue);
    expect(measured.every((r) => r.$1 < 2), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(32768));
    st.goToPosition(const ReadingPosition(2700, 700));
    await tester.pump();
    await tester.pump();
    expect(st.following, isFalse);
    measured.clear();
    tester.widget<IconButton>(find.byKey(const Key('to-reading-place'))).onPressed!();
    await tester.pump();
    await tester.pump();
    expect(st.following, isTrue);
    expect(st.layout.pages[st.page].firstOffset, 0);
    expect(st.layout.pages[st.page].contains(0, sound.offset), isTrue);
    expect(measured, isNotEmpty);
    expect(measured.every((r) => r.$1 < 2), isTrue);
    expect(measured.fold(0, (n, r) => n + r.$3 - r.$2), lessThan(32768));
    await tester.pumpWidget(const SizedBox());
  });
}
